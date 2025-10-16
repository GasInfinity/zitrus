pub const description = "Dump the SMDH or RomFS of a 3DSX";

// TODO: We could maybe allow dumping the elf.

pub const Region = enum { smdh, romfs };

pub const descriptions = .{
    .smdh = "Output SMDH file, use - for stdout",
    .romfs = "Output RomFS file, use - for stdout",
};

pub const switches = .{
    .smdh = 's',
    .romfs = 'r',
};

smdh: ?[]const u8,
romfs: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .input = "3dsx to dump from, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    _ = arena;

    const cwd = std.fs.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if(input_should_close) input_file.close();
    
    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&input_buffer);

    const hdr = try input_reader.interface.takeStruct(@"3dsx".Header, .little);
    
    hdr.check() catch |err| switch(err) {
        error.UnrecognizedHeaderSize => {
            log.err("unrecognized header size {}, expected {} or {}", .{hdr.header_size, @sizeOf(@"3dsx".Header), @sizeOf(@"3dsx".Header) + @sizeOf(@"3dsx".ExtendedHeader)});
            return 1;
        },
        error.UnrecognizedVersion => {
            log.err("unrecognized version {}, expected 0", .{hdr.version});
            return 1;
        },
        else => {
            log.err("header check failed: {t}", .{err});
            return 1;
        }
    };

    if(hdr.header_size != @sizeOf(@"3dsx".Header) + @sizeOf(@"3dsx".ExtendedHeader)) {
        log.err("3dsx doesn't have a SMDH or RomFS", .{});
        return 1;
    }

    const ex_hdr = try input_reader.interface.takeStruct(@"3dsx".ExtendedHeader, .little);

    if(ex_hdr.smdh_size != 0 and ex_hdr.smdh_size != @sizeOf(fmt.smdh.Smdh)) {
        log.err("3dsx does not contain a valid SMDH, size is {}", .{ex_hdr.smdh_size});
        return 1;
    }

    try input_reader.interface.discardAll(ex_hdr.smdh_offset - (@sizeOf(@"3dsx".Header) + @sizeOf(@"3dsx".ExtendedHeader)));

    var out_buffer: [4096]u8 = undefined;
    const smdh_read = if(args.smdh) |out_smdh| blk: {
        const output_file, const output_should_close = if (!std.mem.eql(u8, out_smdh, "-"))
            .{ cwd.createFile(out_smdh, .{}) catch |err| {
                log.err("could not open output SMDH file '{s}': {t}", .{ out_smdh, err });
                return 1;
            }, true }
        else
            .{ std.fs.File.stdout(), false };
        defer if (output_should_close) output_file.close();

        var out_writer = output_file.writerStreaming(&out_buffer);
        const writer = &out_writer.interface;

        if(ex_hdr.smdh_size == 0) {
            log.err("3dsx does not contain a SMDH", .{});
            return 1;
        }

        try input_reader.interface.streamExact(writer, @sizeOf(fmt.smdh.Smdh));
        try writer.flush();

        break :blk true;
    } else false;

    if(args.romfs) |out_romfs| {
        if(!smdh_read) try input_reader.interface.discardAll(ex_hdr.smdh_size);

        const output_file, const output_should_close = if (!std.mem.eql(u8, out_romfs, "-")) 
            .{ cwd.createFile(out_romfs, .{}) catch |err| {
                log.err("could not open output RomFS file '{s}': {t}", .{ out_romfs, err });
                return 1;
            }, true }
        else
            .{ std.fs.File.stdout(), false };
        defer if (output_should_close) output_file.close();

        var out_writer = output_file.writerStreaming(&out_buffer);
        const writer = &out_writer.interface;

        const streamed = try input_reader.interface.streamRemaining(writer);

        if(streamed == 0) {
            log.err("3dsx does not contain a RomFS", .{});
            return 1;
        }

        try writer.flush();
    }

    _ = try input_reader.interface.discardRemaining();
    return 0;
}

const Make = @This();

const log = std.log.scoped(.@"3dsx");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");

const fmt = zitrus.horizon.fmt;
const @"3dsx" = zitrus.fmt.@"3dsx";
