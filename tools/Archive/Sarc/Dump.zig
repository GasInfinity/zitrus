pub const description = "Dump the contents of a SARC.";

pub const descriptions: plz.Descriptions(@This()) = .{
    .output = "Output directory / file. Directory outputs must be specified, if none stdout is used",
    .hash = "Hash of the file in the SARC to dump, cannot be used with '--path'",
    .path = "Path of the file in the SARC to dump, cannot be used with '--hash'",
};

pub const short: plz.Short(@This()) = .{
    .output = 'o',
    .hash = 'H',
    .path = 'p',
};

output: ?[]const u8,
hash: ?u32,
path: ?[]const u8,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "SARC to dump from, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Dump, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();

    if (args.hash != null and args.path != null) {
        log.err("Specify either --path or --hash", .{});
        return 1;
    }

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(io, in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &input_buffer); // XXX: positional reader hangs in discardRemaining
    const input = &input_reader.interface;

    const init = sarc.View.initReader(input, arena) catch |err| {
        log.err("could not open DARC: {t}", .{err});
        return 1;
    };

    // NOTE: Now input_reader points to data_offset as described in the doc comment (important for piping as we can't seek)
    const view = init.view;
    defer view.deinit(arena);

    const real_path = args.path orelse ".";
    const utf16_path = try std.unicode.utf8ToUtf16LeAlloc(arena, real_path);
    defer arena.free(utf16_path);

    const maybe_hash: ?u32 = if (args.hash) |hash|
        hash
    else if (args.path) |path|
        sarc.hashName(path, view.hash_multiplier)
    else
        null;

    if (maybe_hash) |hash| {
        const opened = view.openFileAbsoluteHash(hash) catch |err| {
            if (args.path) |path|
                log.err("could not open file '{s}' (hash {}) in SARC: {t}", .{ path, hash, err })
            else
                log.err("could not open file with hash {} in SARC: {t}", .{ hash, err });
            return 1;
        };

        const output_file, const output_should_close = if (args.output) |out|
            .{ cwd.createFile(io, out, .{}) catch |err| {
                log.err("could not open output file '{s}': {t}", .{ out, err });
                return 1;
            }, true }
        else
            .{ std.Io.File.stdout(), false };
        defer if (output_should_close) output_file.close(io);

        const stat = opened.stat(view);

        var out_buf: [4096]u8 = undefined;
        var output_writer = output_file.writerStreaming(io, &out_buf);
        const writer = &output_writer.interface;

        try input.discardAll(stat.offset);
        try input.streamExact(writer, stat.size);
        try writer.flush();
        return 0;
    }

    if (args.output == null) {
        log.err("directory outputs must be specified", .{});
        return 1;
    }

    if (!input_should_close) {
        // XXX: arbitrary limitation, we could technically read the full SARC
        log.err("cannot dump full SARC contents while piping", .{});
        return 1;
    }

    var output_directory = cwd.createDirPathOpen(io, args.output.?, .{}) catch |err| {
        log.err("could not make path '{s}': {t}", .{ args.output.?, err });
        return 1;
    };
    defer output_directory.close(io);

    // enough for formatting 'unnamed_{X:0>8}'
    var hash_name_buf: [32]u8 = undefined;

    var it = view.iterator();
    while (it.next()) |file| {
        const name = file.name(view);
        const stat = file.stat(view);

        var parent: std.Io.Dir, const close_parent, const display_name = if (name.len == 0)
            .{ output_directory, false, std.fmt.bufPrint(&hash_name_buf, "unnamed_{X:0>8}", .{stat.hash}) catch unreachable }
        else if (std.fs.path.dirname(name)) |dir|
            .{ try output_directory.createDirPathOpen(io, dir, .{}), true, std.fs.path.basenamePosix(name) }
        else
            .{ output_directory, false, name };
        defer if (close_parent) parent.close(io);

        const output_file = parent.createFile(io, display_name, .{}) catch |err| {
            log.err("could not create file '{s}': {t}", .{ display_name, err });
            continue;
        };
        defer output_file.close(io);

        var file_buf: [2048]u8 = undefined;
        var file_writer = output_file.writerStreaming(io, &file_buf);

        try input_reader.seekTo(init.data_offset + stat.offset);
        try input.streamExact64(&file_writer.interface, stat.size);
        try file_writer.interface.flush();
    }

    return 0;
}

const Dump = @This();

const log = std.log.scoped(.darc);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const sarc = zitrus.horizon.fmt.archive.sarc;
