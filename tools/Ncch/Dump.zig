pub const description = "Dump files from a NCCH.";

const Region = enum {
    pub const descriptions = .{
        .settings = "Dump the settings.zon of an NCCH. The NCCH must have an extended header.",
    };

    settings,
    plain,
    logo,
    exefs,
    romfs,
};

pub const descriptions = .{
    .output = "Output filename. If not specified stdout will be used.",
    .minify = "Emit the neccesary whitespace only",
    .region = "NCCH region to dump",
};

pub const switches = .{
    .output = 'o',
    .minify = 'm',
    .region = 'r',
};

output: ?[]const u8 = null,
minify: bool = false,
region: Region,

@"--": struct {
    pub const descriptions = .{
        .input = "The NCCH file, if none stdin is used",
    };

    input: ?[]const u8 = null,
},

pub fn main(args: Dump, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open NCCH '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    var in_buf: [4096]u8 = undefined;
    var ncch_reader = input_file.reader(&in_buf);
    const reader = &ncch_reader.interface;

    const header = try reader.takeStruct(ncch.Header, .little);

    header.check() catch |err| {
        log.err("could not read NCCH: {t}", .{err});
        return 1;
    };

    const offset: u64, const size: usize, const hash_region_size, const hash = switch (args.region) {
        .settings => .{ @sizeOf(ncch.Header), header.extended_header_size, header.extended_header_size, &header.extended_header_hash },
        .plain => .{ @as(u64, header.plain_region_offset) * ncch.media_unit, @as(usize, header.plain_region_size) * ncch.media_unit, 0x00, &.{} },
        .logo => .{ @as(u64, header.logo_region_size) * ncch.media_unit, @as(usize, header.logo_region_size) * ncch.media_unit, @as(usize, header.logo_region_size) * ncch.media_unit, &.{} },
        .exefs => .{ @as(u64, header.exefs_offset) * ncch.media_unit, @as(usize, header.exefs_size) * ncch.media_unit, @as(usize, header.exefs_hash_region_size) * ncch.media_unit, &header.exefs_superblock_hash },
        .romfs => .{ @as(u64, header.romfs_offset) * ncch.media_unit, @as(usize, header.romfs_size) * ncch.media_unit, @as(usize, header.romfs_hash_region_size) * ncch.media_unit, &header.romfs_superblock_hash },
    };

    if (offset == 0x00 or size == 0x00) {
        log.err("NCCH does not contain a '{t}' region.", .{args.region});
        return 1;
    }

    try ncch_reader.seekTo(offset);

    const region_data = try reader.readAlloc(arena, size);
    defer arena.free(region_data);

    if (hash.len > 0) {
        if (hash_region_size > size) {
            log.err("invalid NCCH hash for '{t}' size {} > {}", .{ args.region, hash_region_size, size });
            return 1;
        }

        var real_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(region_data[0..hash_region_size], &real_hash, .{});

        if (!std.mem.eql(u8, hash, &real_hash)) {
            log.err("stored hash for '{t}' does not match the newly computed hash, contents may be corrupted", .{args.region});
            return 1;
        }
    }

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var out_buf: [4096]u8 = undefined;
    var output_writer = output_file.writer(&out_buf);
    const writer = &output_writer.interface;

    switch (args.region) {
        .settings => {
            const exheader: *ncch.ExtendedHeader = @alignCast(std.mem.bytesAsValue(ncch.ExtendedHeader, region_data));

            if (builtin.cpu.arch.endian() != .little) std.mem.byteSwapAllFields(ncch.ExtendedHeader, exheader);

            const access_descriptor = try reader.takeStruct(ncch.AccessDescriptor, .little);

            try dumpSettings(args, arena, writer, header, exheader.*, access_descriptor);
        },
        .plain => {
            var plain_it = std.mem.splitScalar(u8, region_data, 0);

            while (plain_it.next()) |text| {
                const trimmed = std.mem.trim(u8, text, " \t\n");

                if (trimmed.len == 0) continue;

                try writer.print("{s}\n", .{trimmed});
            }
        },
        .romfs => {
            const ivfc = blk: {
                var ivfc = std.mem.bytesToValue(ncch.romfs.IvfcHeader, region_data[0..@sizeOf(ncch.romfs.IvfcHeader)]);

                if (builtin.cpu.arch.endian() != .little) {
                    std.mem.byteSwapAllFields(ncch.romfs.IvfcHeader, &ivfc);
                }

                break :blk ivfc;
            };

            // TODO: Verify data within ivfc
            const romfs_start = std.mem.alignForward(usize, std.mem.alignForward(usize, @sizeOf(ncch.romfs.IvfcHeader), 0x20) + ivfc.master_hash_size, (@as(usize, 1) << @intCast(ivfc.levels[2].block_size)));
            const romfs = region_data[romfs_start..][0..@intCast(ivfc.levels[2].hash_data_size)];
            try writer.writeAll(romfs);
        },
        .logo, .exefs => try writer.writeAll(region_data),
    }

    try writer.flush();
    return 0;
}

pub fn dumpSettings(args: Dump, arena: std.mem.Allocator, writer: *std.Io.Writer, header: ncch.Header, exheader: ncch.ExtendedHeader, access_descriptor: ncch.AccessDescriptor) !void {
    _ = access_descriptor;

    const settings = try Settings.initNcch(&header, &exheader, arena);
    defer settings.deinit(arena);

    try std.zon.stringify.serialize(settings, .{
        .whitespace = !args.minify,
        .emit_default_optional_fields = false,
    }, writer);
    try writer.writeByte('\n');
}

comptime {
    _ = Settings;
}

const Dump = @This();

const log = std.log.scoped(.ncch);

const Settings = @import("Settings.zig");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;
