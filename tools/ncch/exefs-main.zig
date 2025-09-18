const Subcommand = enum { info };

pub const description = "Extract / Make / Show ExeFS binaries";

pub const Arguments = struct {
    pub const description = Self.description;

    command: union(Subcommand) {
        pub const descriptions = .{
            .info = "Show info about an ExeFS",
        };

        info: struct {
            pub const descriptions = .{
                .minify = "Emit the neccesary whitespace only",
                .@"check-hash" = "Check hashes of files inside the ExeFS",
            };

            pub const switches = .{
                .minify = 'm',
            };

            minify: bool = false,
            @"check-hash": bool = false,

            positional: struct {
                pub const descriptions = .{
                    .exefs = "The ExeFS binary",
                };

                exefs: []const u8,
            },
        },
    },
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    const cwd = std.fs.cwd();

    return switch (arguments.command) {
        .info => |i| m: {
            const exefs_path = i.positional.exefs;
            const exefs_file = cwd.openFile(exefs_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open exefs '{s}': {s}\n", .{ exefs_path, @errorName(err) });
                break :m 1;
            };
            defer exefs_file.close();

            var buf: [@sizeOf(exefs.Header)]u8 = undefined;
            var ncch_reader = exefs_file.reader(&buf);
            const reader = &ncch_reader.interface;

            var stdout_buf: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
            const writer = &stdout_writer.interface;

            var serializer: std.zon.Serializer = .{
                .options = .{
                    .whitespace = !i.minify,
                },
                .writer = writer,
            };

            const header = try reader.peekStruct(exefs.Header, .little);
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

                if (i.@"check-hash") {
                    try ncch_reader.seekTo(@sizeOf(exefs.Header) + file.offset);

                    const data = try reader.readAlloc(arena, file.size);
                    defer arena.free(data);

                    var data_hash: [32]u8 = undefined;
                    std.crypto.hash.sha2.Sha256.hash(data, &data_hash, .{});

                    try file_info.field("hash-check", std.mem.eql(u8, file.hash, &data_hash), .{});
                }

                try file_info.end();
            }
            try all_files_tup.end();

            try writer.writeAll("\n");
            try writer.flush();
            break :m 0;
        },
    };
}

const Self = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;
