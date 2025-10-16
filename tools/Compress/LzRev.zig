pub const description = "Compress / Decompress LzRev, the compression algorithm used for 3DS's code.";

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

pub fn main(args: LzRev, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    if(!args.decompress) @panic("TODO: Compress :(");

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if(input_should_close) input_file.close();

    // Unfortunately, this algorithm cannot be streamed, we must read the entire file/reach to the end to decompress it.
    const output_file, const should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (should_close) output_file.close();
    
    var input_reader = input_file.readerStreaming(&.{});
    var output_writer = output_file.writerStreaming(&.{});

    const compressed = try input_reader.interface.allocRemaining(arena, .unlimited);
    defer arena.free(compressed);

    if(compressed.len <= 8) {
        log.err("compressed data is too short", .{});
        return 1;
    }

    const decompressed_len = zitrus.compress.lzrev.len(compressed);

    if(args.verbose) log.info("lzrev compressed {} vs decompressed {}", .{compressed.len, decompressed_len});

    const decompressed = try arena.alloc(u8, decompressed_len);
    defer arena.free(decompressed);

    lzrev.bufDecompress(decompressed, compressed) catch |err| {
        log.err("decompression error: {t}", .{err});
        return 1;
    };

    try output_writer.interface.writeAll(decompressed);
    try output_writer.interface.flush();
    return 0;
}

const LzRev = @This();

const log = std.log.scoped(.lzrev);

const std = @import("std");
const zitrus = @import("zitrus");
const lzrev = zitrus.compress.lzrev;
