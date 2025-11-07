pub const description = "List the files of a SARC.";

pub const descriptions = .{
    .minify = "Emit the neccesary whitespace only",
};

pub const switches = .{
    .minify = 'm',
};

minify: bool = false,

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Info, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open SARC '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(&buf);
    const input = &input_reader.interface;

    const init = sarc.View.initReader(input, arena) catch |err| {
        log.err("could not open SARC: {t}", .{err});
        return 1;
    };

    const view = init.view;
    defer view.deinit(arena);

    var it = view.iterator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout_writer.interface;

    var serializer: std.zon.Serializer = .{
        .options = .{
            .whitespace = !args.minify,
        },
        .writer = writer,
    };

    var sarc_info = try serializer.beginTuple(.{});
    while (it.next()) |entry| {
        var file = try sarc_info.beginStructField(.{});
        try file.field("name", entry.name(view), .{});
        try file.field("stat", entry.stat(view), .{});
        try file.end();
    }
    try sarc_info.end();

    try writer.flush();
    return 0;
}

const Info = @This();

const log = std.log.scoped(.sarc);

const std = @import("std");
const zitrus = @import("zitrus");
const sarc = zitrus.horizon.fmt.archive.sarc;
