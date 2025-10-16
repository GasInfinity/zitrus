pub const description = "Convert a PIE ELF, SMDH and RomFS into a 3DSX";

pub const descriptions = .{
    .smdh = "SMDH metadata to embed",
    .romfs = "RomFS to embed",
};

pub const switches = .{
    .smdh = 's',
    .romfs = 'r',
    .verbose = 'v',
};

smdh: ?[]const u8,
romfs: ?[]const u8,
verbose: bool,

@"--": struct {
    pub const descriptions = .{
        .elf = "ELF PIE to convert",
        .@"3dsx" = "Output filename",
    };

    elf: []const u8,
    @"3dsx": []const u8,
},

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const elf_file = cwd.openFile(args.@"--".elf, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input file '{s}': {t}", .{ args.@"--".elf, err });
        return 1;
    };
    defer elf_file.close();

    var elf_reader_buf: [4096]u8 = undefined;
    var elf_reader = elf_file.reader(&elf_reader_buf);

    var processed = code.extractStaticElfAlloc(&elf_reader, arena) catch |err| switch (err) {
        error.NotElf,
        error.NotArm,
        error.NotLittleEndian,
        error.NotExecutable,
        error.DynamicallyLinked,
        error.DuplicatedSegment,
        error.InvalidRelocations,
        error.UnknownSegment,
        => {
            std.log.err("could not process elf: {t}", .{err});
            return 1;
        },
        else => return err,
    };
    defer processed.deinit(arena);

    if (processed.segments.get(.text) == null) {
        log.err("no .text segment", .{});
        return 1;
    }

    if (processed.findNonSequentialSegment()) |first_non_sequential| {
        log.err("segment {t} is not sequential [text->rodata->data] in memory!", .{first_non_sequential});
        return 1;
    }

    if (processed.findNonDataSegmentWithBss()) |first_bss| {
        log.err("non-data segment {t} has bss", .{first_bss});
        return 1;
    }

    const text = processed.segments.get(.text).?;

    if (processed.entrypoint != text.address) {
        log.err("entrypoint 0x{X:0>8} is not the base of the executable 0x{X:0>8}", .{ processed.entrypoint, text.address });
        return 1;
    }

    var romfs_buffer: [4096]u8 = undefined;
    const romfs_file: ?std.fs.File, var romfs_reader: ?std.fs.File.Reader = if (args.romfs) |romfs| blk: {
        const romfs_file = cwd.openFile(romfs, .{ .mode = .read_only }) catch |err| {
            log.err("could not open romfs file '{s}': {t}", .{ romfs, err });
            return 1;
        };

        break :blk .{ romfs_file, romfs_file.reader(&romfs_buffer) };
    } else .{ null, null };
    defer if (romfs_file) |romfs| romfs.close();

    const smdh_data = if (args.smdh) |smdh_path| data: {
        const smdh_file = cwd.openFile(smdh_path, .{ .mode = .read_only }) catch |err| {
            log.err("could not open SMDH file '{s}': {t}", .{ smdh_path, err });
            return 1;
        };
        defer smdh_file.close();

        var buf: [@sizeOf(fmt.smdh.Smdh)]u8 = undefined;
        var smdh_reader = smdh_file.reader(&buf);
        const smdh_data: fmt.smdh.Smdh = smdh_reader.interface.peekStruct(fmt.smdh.Smdh, .little) catch |err| {
            log.err("error reading SMDH file '{s}': {t}", .{ smdh_path, err });
            return 1;
        };

        if (!std.mem.eql(u8, &smdh_data.magic, fmt.smdh.magic_value)) {
            log.err("SMDH file '{s}' is invalid/corrupted", .{smdh_path});
            return 1;
        }

        break :data smdh_data;
    } else null;
    if (args.verbose) {
        log.info("ELF Segments: ", .{});

        var it = processed.segments.iterator();

        while (it.next()) |e| {
            const seg = e.key;
            const info = e.value;

            log.info("[{t:<6}] Base: 0x{X:0>8} | Size in disk: 0x{X:0>8} | Size in memory: 0x{X:0>8}", .{ seg, info.address, info.file_size, info.memory_size });
        }

        log.info("{} total relocations found.", .{processed.relocations.items.len});
        
        for (processed.relocations.items) |address| {
            it = processed.segments.iterator();

            while (it.next()) |s| {
                const seg = s.key;
                const data = s.value;

                if(address < data.address or address > data.address + data.file_size) {
                    if(s.key == .data) log.info("relocation at 0x{X:0>8} is unmapped", .{address});
                    continue;
                }

                try elf_reader.seekTo(s.value.file_offset + (address - data.address));
                const value = try elf_reader.interface.takeInt(u32, .little);
                log.info("relocation [{t:<6}] at 0x{X:0>8}: 0x{X:0>8} (0x{X:0>8})", .{seg, address, value, (value - text.address)});
                break;
            }
        }

        if (romfs_reader) |*romfs| log.info("{} RomFS bytes", .{try romfs.getSize()});
    }

    const output_file = cwd.createFile(args.@"--".@"3dsx", .{}) catch |err| {
        log.err("could not create/open output file '{s}' for writing: {t}", .{ args.@"--".@"3dsx", err });
        return 1;
    };
    defer output_file.close();

    var output_buffer: [8192]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);

    try @"3dsx".make(&output_writer.interface, &elf_reader, processed, arena, .{
        .smdh = smdh_data,
        .romfs = if (romfs_reader) |*romfs| &romfs.interface else null,
    });

    try output_writer.interface.flush();

    return 0;
}

const Make = @This();

const log = std.log.scoped(.@"3dsx");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");

const fmt = zitrus.horizon.fmt;
const @"3dsx" = zitrus.fmt.@"3dsx";

const code = zitrus.fmt.code;
