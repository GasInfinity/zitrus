pub const description = "Dump / Make / Show an ExeFS";

const Subcommand = enum {
    info,
    dump,
    // make,
};

pub const Info = struct {
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
            .exefs = "The ExeFS binary",
        };

        exefs: []const u8,
    },
};

pub const Dump = struct {
    pub const description = "Dump the contents of an ExeFS.";

    pub const descriptions = .{
        .file = "Dump a specific file instead of the entire ExeFS",
        .output = "The output directory / file. Directory outputs must be specified and the default file output is stdout.",
    };

    pub const switches = .{
        .file = 'f',
        .output = 'o',
    };

    file: ?[]const u8 = null,
    output: ?[]const u8 = null,

    @"--": struct {
        pub const descriptions = .{
            .exefs = "The ExeFS binary",
        };

        exefs: []const u8,
    },
};

@"-": union(Subcommand) {
    info: Info,
    dump: Dump,
},

pub fn main(args: ExeFs, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    return switch (args.@"-") {
        .info => |i| m: {
            const exefs_path = i.@"--".exefs;
            const exefs_file = cwd.openFile(exefs_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open exefs '{s}': {s}\n", .{ exefs_path, @errorName(err) });
                break :m 1;
            };
            defer exefs_file.close();

            var buf: [@sizeOf(exefs.Header)]u8 = undefined;
            var exefs_reader = exefs_file.reader(&buf);
            const reader = &exefs_reader.interface;

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
            reader.toss(@sizeOf(exefs.Header));

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

                if (i.check_hash) {
                    try exefs_reader.seekTo(@sizeOf(exefs.Header) + file.offset);

                    const data = try reader.readAlloc(arena, file.size);
                    defer arena.free(data);

                    try file_info.field("hash-check", file.check(data), .{});
                }

                try file_info.end();
            }
            try all_files_tup.end();

            try writer.writeAll("\n");
            try writer.flush();
            break :m 0;
        },
        .dump => |i| m: {
            const exefs_path = i.@"--".exefs;
            const exefs_file = cwd.openFile(exefs_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open exefs '{s}': {s}\n", .{ exefs_path, @errorName(err) });
                break :m 1;
            };
            defer exefs_file.close();

            var buf: [@sizeOf(exefs.Header)]u8 = undefined;
            var exefs_reader = exefs_file.reader(&buf);
            const reader = &exefs_reader.interface;

            const header = try reader.peekStruct(exefs.Header, .little);
            reader.toss(@sizeOf(exefs.Header));

            if (i.file) |file_name| {
                const file = header.find(file_name) orelse {
                    std.debug.print("could not find file '{s}' in exefs\n", .{file_name});
                    break :m 1;
                };

                try exefs_reader.seekTo(@sizeOf(exefs.Header) + file.offset);
                const contents = try reader.readAlloc(arena, file.size);
                defer arena.free(contents);

                if (!file.check(contents)) {
                    std.debug.print("Stored hash in the ExeFS does not match the newly computed hash, aborting...\n", .{});
                    break :m 1;
                }

                const output_file, const should_close = if (i.output) |out|
                    .{ try cwd.createFile(out, .{}), true }
                else
                    .{ std.fs.File.stdout(), false };
                defer if (should_close) output_file.close();

                var out_buf: [4096]u8 = undefined;
                var output_writer = output_file.writer(&out_buf);
                const writer = &output_writer.interface;

                try writer.writeAll(contents);
                try writer.flush();
                break :m 0;
            } else @panic("TODO"); // Dump into a directory, output directory is mandatory
        },
    };
}

const ExeFs = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;
