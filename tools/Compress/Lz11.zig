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
    const cwd = std.fs.cwd();
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

    if(args.decompress) {
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
        const input_remaining = try input_reader.interface.discardRemaining();
        if (input_remaining != 0) log.warn("Got {} more bytes after decompressing", .{input_remaining});
        return 0;
    }

    log.warn("Only a 'fastestest' compression is currently supported (a.k.a: no compression), file size will be bigger!", .{});
    
    // TODO: Migrate to normal `Compress` when implemented.
    var output_buf: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&output_buf);

    var compress_buf: [lz11.max_window_len]u8 = undefined;
    var compressor: lz11.Compress.Raw = .init(&output_writer.interface, &compress_buf);

    if(input_reader.getSize()) |size| {
        if(size >= std.math.maxInt(u24)) {
            log.err("cannot compress, file size is too big, {} > {}!", .{size, std.math.maxInt(u24)});
            return 1;
        }

        try output_writer.interface.writeStruct(lz11.Header{
            .uncompressed_len = @intCast(size),
        }, .little);
        try input_reader.interface.streamExact64(&compressor.writer, size);
    } else |_| {
        var allocating: std.Io.Writer.Allocating = .init(arena);
        defer allocating.deinit();

        const size = try input_reader.interface.streamRemaining(&allocating.writer);

        if(size >= std.math.maxInt(u24)) {
            log.err("cannot compress, file size is too big, {} > {}!", .{size, std.math.maxInt(u24)});
            return 1;
        }

        try output_writer.interface.writeStruct(lz11.Header{
            .uncompressed_len = @intCast(size),
        }, .little);
        try compressor.writer.writeAll(allocating.written());
        // We need to allocate as we don't know the size in advance :(
    }

    try compressor.end();
    try output_writer.interface.flush();
    return 0;
}

const Lz11 = @This();

const log = std.log.scoped(.lz11);

const std = @import("std");
const zitrus = @import("zitrus");
const lz11 = zitrus.compress.lz11;
