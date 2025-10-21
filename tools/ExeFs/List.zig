pub const description = "List the files of an ExeFS and optionally check their hash.";

pub const descriptions = .{
    .minify = "Emit the neccesary whitespace only",
    .check_hash = "Check hashes of files inside the ExeFS",
};

pub const switches = .{
    .minify = 'm',
    .check_hash = 'c',
};

minify: bool = false,
check_hash: bool = false,

@"--": struct {
    pub const descriptions = .{
        .input = "ExeFS file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: List, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    if (!input_should_close and args.check_hash) {
        log.err("cannot check hashes while piping", .{}); // XXX: arbitrary, we could obviously support that by allocating the piped ExeFS contents.
        return 1;
    }

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&buf); // XXX: Hangs on positional mode with discardAll
    const reader = &input_reader.interface;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout_writer.interface;

    var serializer: std.zon.Serializer = .{
        .options = .{
            .whitespace = !args.minify,
        },
        .writer = writer,
    };

    const header = try reader.takeStruct(exefs.Header, .little);

    var it = header.iterator();
    var all_files_tup = try serializer.beginTuple(.{});
    while (it.next()) |file| {
        var file_info = try all_files_tup.beginStructField(.{});
        try file_info.field("name", file.name, .{});
        try file_info.field("offset", file.offset, .{});
        try file_info.field("size", file.size, .{});
        var hash_tuple = try file_info.beginTupleField("hash", .{ .whitespace_style = .{ .wrap = false } });
        for (file.hash) |b| try hash_tuple.field(b, .{});
        try hash_tuple.end();

        if (args.check_hash) {
            try input_reader.seekTo(@sizeOf(exefs.Header) + file.offset);

            const data = try reader.readAlloc(arena, file.size);
            defer arena.free(data);

            try file_info.field("hash-check", file.check(data), .{});
        }

        try file_info.end();
    }
    try all_files_tup.end();

    try writer.writeAll("\n");
    try writer.flush();
    _ = try reader.discardRemaining(); // don't produce broken pipes
    return 0;
}

const List = @This();

const log = std.log.scoped(.exefs);

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;
