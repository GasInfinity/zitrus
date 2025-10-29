pub const description = "List files in a RomFS directory.";

pub const descriptions = .{
    .zon = "Output zon instead",
    .minify = "Minify the output if zon",
};

pub const switches = .{
    .zon = 'z',
    .minify = 'm',
};

zon: bool,
minify: bool,

@"--": struct {
    pub const descriptions = .{
        .path = "Path inside the RomFS to list files from.",
        .input = "RomFS to list files from, if none stdin is used",
    };

    path: ?[]const u8,
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

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&input_buffer); // XXX: positional reader hangs in discardRemaining

    const init = try romfs.View.initReader(&input_reader.interface, arena);
    const view = init.view;
    defer view.deinit(arena);

    const real_path = args.@"--".path orelse ".";
    const utf16_path = try std.unicode.utf8ToUtf16LeAlloc(arena, real_path);
    defer arena.free(utf16_path);

    const dir = view.openDir(.root, utf16_path) catch |err| {
        log.err("error opening directory in RomFS '{s}': {t}\n", .{ real_path, err });
        return 1;
    };

    const tty_conf: std.Io.tty.Config = .detect(std.fs.File.stdout());
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var it = view.iterator(dir);

    if (args.zon) {
        var serializer: std.zon.Serializer = .{
            .options = .{
                .whitespace = !args.minify,
            },
            .writer = &stdout_writer.interface,
        };

        var path_buf: [1024]u8 = undefined;
        var all_files_tup = try serializer.beginTuple(.{});
        while (it.next(view)) |entry| {
            // XXX: Should not allocate.
            const written = try std.unicode.utf16LeToUtf8(&path_buf, entry.name(view));

            var zon_entry = try all_files_tup.beginStructField(.{});
            try zon_entry.field("name", path_buf[0..written], .{});
            try zon_entry.field("kind", entry.kind, .{});
            try zon_entry.end();
        }
        try all_files_tup.end();
    } else {
        while (it.next(view)) |entry| {
            switch (entry.kind) {
                .directory => {
                    try tty_conf.setColor(&stdout_writer.interface, .bold);
                    try tty_conf.setColor(&stdout_writer.interface, .bright_blue);
                },
                .file => try tty_conf.setColor(&stdout_writer.interface, .reset),
            }

            try stdout_writer.interface.print("{f}   ", .{std.unicode.fmtUtf16Le(entry.name(view))});
        }
    }

    try stdout_writer.interface.print("\n", .{});
    try stdout_writer.interface.flush();
    _ = try input_reader.interface.discardRemaining(); // Avoid broken pipes
    return 0;
}

const List = @This();

const log = std.log.scoped(.romfs);

const std = @import("std");
const zitrus = @import("zitrus");
const romfs = zitrus.horizon.fmt.ncch.romfs;
