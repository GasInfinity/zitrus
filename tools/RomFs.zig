pub const description = "Dump / Make / Show a RomFS";

const Subcommand = enum {
    // info,
    // dump,
    make,
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

@"-": union(Subcommand) {
    make: Make,
},

pub fn main(args: RomFs, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    return switch (args.@"-") {
        .make => |i| m: {
            const dir_path = i.@"--".directory;
            var root = cwd.openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
                else => {
                    std.debug.print("error opening directory '{s}': {t}", .{ dir_path, err });
                    break :m 1;
                },
            };
            defer root.close();

            const output_path = i.output;
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
