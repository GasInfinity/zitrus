pub const description = "Make a RomFS";

pub const descriptions = .{
    .output = "Output file, if none stdout is used.",
};

pub const switches = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .directory = "Directory to convert",
    };

    directory: []const u8,
},

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const dir_path = args.@"--".directory;

    var root = cwd.openDir(dir_path, .{ .iterate = true }) catch |err| {
        log.err("error opening directory '{s}': {t}", .{ dir_path, err });
        return 1;
    };
    defer root.close();

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);

    var builder: romfs.Builder = try .init(arena);
    defer builder.deinit(arena);

    addDirectory(&builder, arena, &root, &builder.root) catch |err| {
        log.err("couldn't create RomFS: {t}", .{err});
        return 1;
    };

    try builder.rehash(arena);
    try builder.write(&output_writer.interface);
    try output_writer.interface.flush();
    return 0;
}

fn addDirectory(builder: *romfs.Builder, gpa: std.mem.Allocator, dir: *std.fs.Dir, b_dir: *romfs.Builder.Directory) !void {
    var it = dir.iterate();

    const Entry = struct {
        b_dir: romfs.Builder.Directory,
        dir: std.fs.Dir,
    };

    var directories: std.ArrayList(Entry) = .empty;
    defer directories.deinit(gpa);

    while (try it.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

        switch (entry.kind) {
            .directory => {
                const sub = dir.openDir(entry.name, .{ .iterate = true }) catch |err| {
                    log.err("error while opening directory '{s}': {t}... skipping", .{ entry.name, err });
                    continue;
                };

                try directories.append(gpa, .{
                    .b_dir = try builder.addDirectory(gpa, b_dir, .utf8(entry.name)),
                    .dir = sub,
                });
            },
            .file => {
                const file = dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                    log.err("error while opening file '{s}': {t}... skipping", .{ entry.name, err });
                    continue;
                };
                defer file.close();

                var reader = file.reader(&.{});
                const contents = try reader.interface.allocRemaining(gpa, .unlimited);
                defer gpa.free(contents);

                // TODO: streamFile to not allocate 2 times the same data and write it directly!
                try builder.addFile(gpa, b_dir, .utf8(entry.name), contents);
            },
            else => log.warn("ignoring entry '{s}', cannot handle entry kind: {t}", .{ entry.name, entry.kind }),
        }
    }

    for (directories.items) |*entry| {
        defer entry.dir.close();

        try addDirectory(builder, gpa, &entry.dir, &entry.b_dir);
    }
}

const Make = @This();

const log = std.log.scoped(.romfs);

const std = @import("std");
const zitrus = @import("zitrus");
const romfs = zitrus.horizon.fmt.ncch.romfs;
