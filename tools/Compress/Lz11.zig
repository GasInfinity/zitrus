pub const description = "Compress / Decompress LZ11 (.lz, .lz77), used in 3DS titles.";

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
    .decompress = "Decompress data",
};

pub const switches = .{
    .output = 'o',
    .decompress = 'd',
    .verbose = 'v',
};

output: ?[]const u8,
decompress: bool,
verbose: bool,

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Lz11, arena: std.mem.Allocator) !u8 {
    _ = arena;
    const cwd = std.fs.cwd();

    if (!args.decompress) @panic("TODO: Compress :(");

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    const output_file, const should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (should_close) output_file.close();

    var input_buf: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&input_buf);
    var decompressor: lz11.Decompress = .init(&input_reader.interface, &.{});

    var decompress_buf: [lz11.max_window_len]u8 = undefined;
    var output_writer = output_file.writerStreaming(&decompress_buf);

    const streamed = decompressor.reader.streamRemaining(&output_writer.interface) catch |err| switch (err) {
        error.ReadFailed => {
            log.err("error decompressing, corrupted? {t}", .{decompressor.err.?});
            log.err("useful info: ", .{});
            log.err("  - remaining bytes to decompress: {}", .{decompressor.remaining_uncompressed});
            return 1;
        },
        error.WriteFailed => {
            log.err("error writing to output: {t}", .{output_writer.err.?});
            return 1;
        },
    };

    try output_writer.interface.flush();
    if (args.verbose) log.info("Decompressed size: {} bytes", .{streamed});
    if (try input_reader.interface.discardRemaining() != 0) log.warn("Got more data after decompressing", .{});
    return 0;
}

const Lz11 = @This();

const log = std.log.scoped(.lz11);

const std = @import("std");
const zitrus = @import("zitrus");
const lz11 = zitrus.compress.lz11;
