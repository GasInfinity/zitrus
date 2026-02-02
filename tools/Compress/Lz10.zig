pub const description = "Compress / Decompress LZ10 (.lz, .lz77), used in 3DS titles.";

pub const descriptions: plz.Descriptions(@This()) = .{
    .header = "Add extra bytes as a header, e.g: 'LZ77'",
    .output = "Output file, if none stdout is used",
    .decompress = "Decompress data",
};

pub const short: plz.Short(@This()) = .{
    .header = 'H',
    .output = 'o',
    .decompress = 'd',
    .verbose = 'v',
};

header: ?[]const u8,
decompress: ?void,
output: ?[]const u8,
verbose: ?void,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Lz10, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(io, in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    const output_file, const should_close = if (args.output) |out|
        .{ cwd.createFile(io, out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdout(), false };
    defer if (should_close) output_file.close(io);

    var input_buf: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(io, &input_buf);

    if (args.decompress) |_| {
        const maybe_hdr = try input_reader.interface.peekArray(4);

        // The decompressor works with the raw stream and doesn't (and shouldn't) handle this.
        if (std.mem.eql(u8, maybe_hdr, "LZ77") or std.mem.eql(u8, maybe_hdr, "CMPR")) input_reader.interface.toss(4);

        var decompressor: lz10.Decompress = .init(&input_reader.interface, &.{});

        var decompress_buf: [lz10.max_window_len]u8 = undefined;
        var output_writer = output_file.writerStreaming(io, &decompress_buf);

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
        if (args.verbose) |_| log.info("Decompressed size: {} bytes", .{streamed});

        const input_remaining = try input_reader.interface.discardRemaining();
        if (input_remaining != 0) log.warn("Got {} more bytes after decompressing", .{input_remaining});
        return 0;
    }

    log.warn("Only a 'fastestest' compression is currently supported (a.k.a: no compression), file size will be bigger!", .{});

    // TODO: Migrate to normal `Compress` when implemented.
    var output_buf: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(io, &output_buf);

    var compress_buf: [lz10.max_window_len]u8 = undefined;
    var compressor: lz10.Compress.Raw = .init(&output_writer.interface, &compress_buf);

    if (args.header) |hdr| try output_writer.interface.writeAll(hdr);

    if (input_reader.getSize()) |size| {
        if (size >= std.math.maxInt(u24)) {
            log.err("cannot compress, file size is too big, {} > {}!", .{ size, std.math.maxInt(u24) });
            return 1;
        }

        try output_writer.interface.writeStruct(lz10.Header{
            .uncompressed_len = @intCast(size),
        }, .little);
        try input_reader.interface.streamExact64(&compressor.writer, size);
    } else |_| {
        var allocating: std.Io.Writer.Allocating = .init(arena);
        defer allocating.deinit();

        const size = try input_reader.interface.streamRemaining(&allocating.writer);

        if (size >= std.math.maxInt(u24)) {
            log.err("cannot compress, file size is too big, {} > {}!", .{ size, std.math.maxInt(u24) });
            return 1;
        }

        try output_writer.interface.writeStruct(lz10.Header{
            .uncompressed_len = @intCast(size),
        }, .little);
        try compressor.writer.writeAll(allocating.written());
        // We need to allocate as we don't know the size in advance :(
    }

    try compressor.end();
    try output_writer.interface.flush();
    return 0;
}

const Lz10 = @This();

const log = std.log.scoped(.lz10);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const lz10 = zitrus.compress.lz10;
