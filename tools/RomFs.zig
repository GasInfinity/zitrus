pub const description = "Dump / Make / Show a RomFS";

const Subcommand = enum {
    make,
    ls,
    // dump,
};

pub const Make = struct {
    pub const description = "Make a RomFS";

    pub const descriptions = .{
        .output = "Output RomFS filename.",
    };

    pub const switches = .{
        .output = 'o',
    };

    output: []const u8,

    @"--": struct {
        pub const descriptions = .{
            .directory = "Directory to convert",
        };

        directory: []const u8,
    },
};

pub const ListFiles = struct {
    pub const description = "List files in a RomFS directory.";

    pub const descriptions = .{
        .zon = "Output zon instead",
        .minify = "Minify the output if zon",
    };

    pub const switches = .{
        .minify = 'm',
    };

    zon: bool,
    minify: bool,

    @"--": struct {
        pub const descriptions = .{
            .romfs = "RomFS to list files from.",
            .path = "Path inside the RomFS to list files from.",
        };

        romfs: []const u8,
        path: ?[]const u8,
    },
};

@"-": union(Subcommand) {
    make: Make,
    ls: ListFiles,
},

pub fn main(args: RomFs, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    return switch (args.@"-") {
        .make => |make| m: {
            const dir_path = make.@"--".directory;
            var root = cwd.openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
                else => {
                    std.debug.print("error opening directory '{s}': {t}", .{ dir_path, err });
                    break :m 1;
                },
            };
            defer root.close();

            const output_path = make.output;
            const output = try cwd.createFile(output_path, .{});
            defer output.close();

            var output_buffer: [4096]u8 = undefined;
            var output_writer = output.writer(&output_buffer);

            var builder: romfs.Builder = try .init(arena);
            defer builder.deinit(arena);

            try addDirectory(&builder, arena, &root, &builder.root);

            try builder.rehash(arena);
            try builder.write(&output_writer.interface);
            try output_writer.interface.flush();
            break :m 0;
        },
        .ls => |ls| m: {
            const romfs_path = ls.@"--".romfs;
            const romfs_file = cwd.openFile(romfs_path, .{ .mode = .read_only }) catch |err| switch (err) {
                else => {
                    std.debug.print("error opening RomFS '{s}': {t}", .{ romfs_path, err });
                    break :m 1;
                },
            };
            defer romfs_file.close();

            var romfs_buffer: [4096]u8 = undefined;
            var romfs_reader = romfs_file.reader(&romfs_buffer);

            const init = try romfs.View.initFile(&romfs_reader, arena);
            const view = init.view;
            defer view.deinit(arena);

            const real_path = ls.@"--".path orelse ".";
            const utf16_path = try std.unicode.utf8ToUtf16LeAlloc(arena, real_path);
            defer arena.free(utf16_path);

            const dir = view.openDir(.root, utf16_path) catch |err| {
                std.debug.print("error opening directory in RomFS '{s}': {t}\n", .{ real_path, err });
                break :m 1;
            };

            const tty_conf: std.Io.tty.Config = .detect(std.fs.File.stdout());
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            var it = view.iterator(dir);

            if (ls.zon) {
                var serializer: std.zon.Serializer = .{
                    .options = .{
                        .whitespace = !ls.minify,
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
            std.debug.print("\n", .{});

            break :m 0;
        },
    };
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
                    std.debug.print("error while opening directory '{s}': {t}\n", .{ entry.name, err });
                    return err;
                };

                try directories.append(gpa, .{
                    .b_dir = try builder.addDirectory(gpa, b_dir, .utf8(entry.name)),
                    .dir = sub,
                });
            },
            .file => {
                const file = dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                    std.debug.print("error while opening file '{s}': {t}\n", .{ entry.name, err });
                    return err;
                };
                defer file.close();

                var reader = file.reader(&.{});
                const contents = try reader.interface.allocRemaining(gpa, .unlimited);
                defer gpa.free(contents);

                try builder.addFile(gpa, b_dir, .utf8(entry.name), contents);
            },
            else => std.debug.print("ignoring entry '{s}', cannot handle entry kind {t}", .{ entry.name, entry.kind }),
        }
    }

    for (directories.items) |*entry| {
        defer entry.dir.close();

        try addDirectory(builder, gpa, &entry.dir, &entry.b_dir);
    }
}

const RomFs = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const romfs = zitrus.horizon.fmt.ncch.romfs;
