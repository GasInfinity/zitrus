pub const description = "Dump the contents of an ExeFS.";

pub const descriptions = .{
    .file = "Dump a specific file instead of the entire ExeFS",
    .output = "Output directory / file. Directory outputs must be specified, if none stdout is used",
};

pub const switches = .{
    .file = 'f',
    .output = 'o',
};

file: ?[]const u8 = null,
output: ?[]const u8 = null,

@"--": struct {
    pub const descriptions = .{
        .input = "The ExeFS file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Dump, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if(input_should_close) input_file.close();

    var buf: [4096]u8 = undefined; 
    var exefs_reader = input_file.readerStreaming(&buf);
    const reader = &exefs_reader.interface;

    const header = reader.takeStruct(exefs.Header, .little) catch |err| {
        log.err("could not read ExeFS header: {t}", .{err});
        return 1;
    };

    if (args.file) |file_name| {
        const file = header.find(file_name) orelse {
            log.err("could not find file '{s}' in ExeFS", .{file_name});
            return 1;
        };

        try exefs_reader.seekBy(file.offset);
        const contents = try reader.readAlloc(arena, file.size);
        defer arena.free(contents);

        if (!file.check(contents)) {
            log.err("stored hash for '{s}' does not match the newly computed hash, contents may be corrupted", .{file_name});
            return 1;
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
        var output_writer = output_file.writerStreaming(&out_buf);
        const writer = &output_writer.interface;

        try writer.writeAll(contents);
        try writer.flush();

        // Needed if we don't want broken pipes.
        _ = try reader.discardRemaining();
        return 0;
    }
    
    if(args.output == null) {
        log.err("output path is required when dumping all ExeFS contents", .{});
        return 1;
    }

    const output_path = args.output.?;
    var output_directory = cwd.makeOpenPath(output_path, .{}) catch |err| {
        log.err("could not make path '{s}': {t}", .{output_path, err});
        return 1;
    };
    defer output_directory.close();

    var it = header.iterator();

    while (it.next()) |file| {
        const new_file = output_directory.createFile(file.name, .{
            .exclusive = true,
        }) catch |err| {
            log.err("error dumping '{s}' into '{s}': {t}", .{file.name, output_path, err});
            continue;
        };
        defer new_file.close();

        var new_writer_buffer: [512]u8 = undefined;
        var new_writer = new_file.writerStreaming(&new_writer_buffer);

        try exefs_reader.seekTo(@sizeOf(exefs.Header) + file.offset);
        try exefs_reader.interface.streamExact(&new_writer.interface, file.size);
    }
    return 0;
}

const Dump = @This();

const log = std.log.scoped(.exefs);

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;
