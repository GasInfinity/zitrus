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
    .verbose = 'v',
};

output: ?[]const u8 = null,
minify: bool = false,
region: Region,
verbose: bool,

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

    const full = try reader.takeStruct(ncch.Header.WithSignature, .little);
    const header = full.header;

    header.check() catch |err| {
        log.err("could not read NCCH: {t}", .{err});
        return 1;
    };

    const media_unit = hfmt.media_unit * (@as(u64, 1) << @truncate(header.flags.extra_unit_exponent));

    const offset: u64, const size: u64, const hash_region_size: u64, const hash = switch (args.region) {
        .settings => .{ @sizeOf(ncch.Header.WithSignature), header.extended_header_size, header.extended_header_size, &header.extended_header_hash },
        .plain => .{ @as(u64, header.plain_region_offset) * media_unit, @as(usize, header.plain_region_size) * media_unit, 0x00, &.{} },
        .logo => .{ @as(u64, header.logo_region_size) * media_unit, @as(usize, header.logo_region_size) * media_unit, @as(usize, header.logo_region_size) * media_unit, &.{} },
        .exefs => .{ @as(u64, header.exefs_offset) * media_unit, @as(usize, header.exefs_size) * media_unit, @as(usize, header.exefs_hash_region_size) * media_unit, &header.exefs_superblock_hash },
        .romfs => .{ @as(u64, header.romfs_offset) * media_unit, @as(usize, header.romfs_size) * media_unit, @as(usize, header.romfs_hash_region_size) * media_unit, &header.romfs_superblock_hash },
    };

    if (offset == 0x00 or size == 0x00) {
        log.err("NCCH does not contain a '{t}' region.", .{args.region});
        return 1;
    }

    if (args.verbose) {
        log.info("Platform: {t}", .{header.flags.platform});
        log.info("Type: {t} | Form: {t}", .{ header.flags.content.form, header.flags.content.type });
        log.info("Media unit size: 0x{X:0>8}", .{media_unit});
        log.info("Offset (B):      0x{X:0>16}", .{offset});
        log.info("Size (B):        0x{X:0>16}", .{size});
        log.info("Hashed size (B): 0x{X:0>16}", .{hash_region_size});
    }

    try ncch_reader.seekTo(offset);

    if (hash_region_size > std.math.maxInt(usize)) {
        log.err("cannot read NCCH region to hash, it's bigger than '{}' (usize)", .{std.math.maxInt(usize)});
        return 1;
    }

    if (hash_region_size > size) {
        log.err("invalid NCCH hash for '{t}', hashed region is bigger than the region size {}: > {}", .{ args.region, hash_region_size, size });
        return 1;
    }

    const safe_hash_region_size: usize = @intCast(hash_region_size);

    const hashed_region_data: []u8 = if (hash.len > 0 and safe_hash_region_size > 0) blk: {
        const hashed: []u8 = try reader.readAlloc(arena, safe_hash_region_size);
        errdefer arena.free(hashed);

        var real_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(hashed, &real_hash, .{});

        if (!std.mem.eql(u8, hash, &real_hash)) {
            arena.free(hashed);
            log.err("stored hash for '{t}' does not match the newly computed hash, contents may be corrupted", .{args.region});
            return 1;
        }

        break :blk hashed;
    } else &.{};
    defer arena.free(hashed_region_data);

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
            // NOTE: It is guaranteed that the hashed region data will be equal to the exheader.
            const exheader: *ncch.ExtendedHeader = @alignCast(std.mem.bytesAsValue(ncch.ExtendedHeader, hashed_region_data));
            if (builtin.cpu.arch.endian() != .little) std.mem.byteSwapAllFields(ncch.ExtendedHeader, exheader);

            const access_descriptor = try reader.takeStruct(ncch.AccessDescriptor, .little);

            try dumpSettings(args, arena, writer, header, exheader.*, access_descriptor);
        },
        .plain => {
            // NOTE: It is guaranteed that the plain region doesn't have a hash so we haven't allocated a buffer :p
            var remaining = size;
            while (remaining > 0) {
                var text = reader.takeDelimiterExclusive(0) catch |err| switch (err) {
                    error.ReadFailed => return err,
                    error.EndOfStream => break,
                    error.StreamTooLong => {
                        log.err("a string in the plain region is bigger than {} bytes, streaming instead of pretty printing", .{reader.buffer.len});
                        try reader.streamExact64(writer, remaining);
                        break;
                    },
                };

                // Could happen if the string was not null terminated and we've read stale data
                if (text.len + 1 > remaining) {
                    text.len = @intCast(remaining);
                    remaining = 0;
                } else remaining -= text.len + 1;

                const trimmed = std.mem.trim(u8, text, " \t\n");
                if (trimmed.len == 0) continue;

                try writer.print("{s}\n", .{trimmed});
            }
        },
        .romfs => {
            var ivfc_header: ncch.romfs.IvfcHeader = undefined;

            if (hashed_region_data.len < @sizeOf(ncch.romfs.IvfcHeader)) {
                const as_u8: []u8 = @ptrCast(&ivfc_header);
                @memcpy(as_u8[0..hashed_region_data.len], hashed_region_data);
            } else @memcpy(@as([]u8, @ptrCast(&ivfc_header)), hashed_region_data[0..@sizeOf(ncch.romfs.IvfcHeader)]);

            if (builtin.cpu.arch.endian() != .little) std.mem.byteSwapAllFields(ncch.romfs.IvfcHeader, &ivfc_header);

            // TODO: Verify data within ivfc / proper IVFC parsing
            if (ivfc_header.levels[2].block_size > @bitSizeOf(u64)) {
                log.err("RomFS block size is bigger than an `u64`", .{});
                return 1;
            }

            const block_size = @as(u64, 1) << @intCast(ivfc_header.levels[2].block_size);
            const romfs_start = std.mem.alignForward(u64, std.mem.alignForward(usize, @sizeOf(ncch.romfs.IvfcHeader), 0x20) + @as(u64, ivfc_header.master_hash_size), block_size);
            const romfs_size = ivfc_header.levels[2].hash_data_size;

            if (romfs_start < hashed_region_data.len) {
                try writer.writeAll(hashed_region_data[@intCast(romfs_start)..]);
                try reader.streamExact64(writer, romfs_size -| (hashed_region_data.len - romfs_start));
            } else {
                try reader.discardAll64(romfs_start - hashed_region_data.len);
                try reader.streamExact64(writer, romfs_size);
            }
        },
        .logo, .exefs => {
            try writer.writeAll(hashed_region_data);
            try reader.streamExact64(writer, (size - hash_region_size));
        },
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

const hfmt = zitrus.horizon.fmt;
const ncch = hfmt.ncch;
