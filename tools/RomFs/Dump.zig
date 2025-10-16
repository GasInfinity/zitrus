pub const description = "Dump the contents of a RomFS.";

pub const descriptions = .{
    .output = "Output directory / file. Directory outputs must be specified, if none stdout is used",
};

pub const switches = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .path = "Path inside the RomFS to dump, directories are allowed",
        .input = "RomFS to dump from, if none stdin is used",
    };

    path: ?[]const u8,
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

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(&input_buffer);

    const init = try romfs.View.initReader(&input_reader.interface, arena);
    // NOTE: Now input_reader points to file_data_offset as described in the doc comment (important for piping as we can't seek)

    const view = init.view;
    defer view.deinit(arena);

    const real_path = args.@"--".path orelse ".";
    const utf16_path = try std.unicode.utf8ToUtf16LeAlloc(arena, real_path);
    defer arena.free(utf16_path);

    const opened = view.openAny(.root, utf16_path) catch |err| {
        log.err("could not open file '{s}' in RomFS: {t}", .{real_path, err});
        return 1;
    };
    
    switch (opened.kind) {
        .directory => if(args.output) |out| {
            if(!input_should_close) {
                // XXX: arbitrary limitation, we could technically read the full RomFS
                log.err("cannot dump full directory contents while piping", .{}); 
                return 1;
            }

            const romfs_dir = opened.asDirectory();

            var output_directory = cwd.makeOpenPath(out, .{}) catch |err| {
                log.err("could not make path '{s}': {t}", .{out, err});
                return 1;
            };
            defer output_directory.close();
            
            try dumpDirectory(&input_reader, init.data_offset, view, romfs_dir, output_directory);     
        } else {
            log.err("directory outputs must be specified", .{});
            return 1;
        },
        .file => {
            const output_file, const output_should_close = if (args.output) |out|
                .{ cwd.createFile(out, .{}) catch |err| {
                    log.err("could not open output file '{s}': {t}", .{ out, err });
                    return 1;
                }, true }
            else
                .{ std.fs.File.stdout(), false };
            defer if (output_should_close) output_file.close(); 

            const file = opened.asFile();
            const stat = file.stat(view);

            var out_buf: [4096]u8 = undefined;
            var output_writer = output_file.writerStreaming(&out_buf);
            const writer = &output_writer.interface;

            try input_reader.interface.discardAll(stat.offset);
            try input_reader.interface.streamExact64(writer, stat.size);
            _ = try input_reader.interface.discardRemaining();
            try writer.flush();
        },
    }

    return 0;
}

fn dumpDirectory(reader: *std.fs.File.Reader, data_offset: usize, view: romfs.View, romfs_dir: romfs.View.Directory, dir: std.fs.Dir) !void {
    var it = view.iterator(romfs_dir);

    while (it.next(view)) |entry| {
        var name_buf: [1024]u8 = undefined;
        const name_len = try std.unicode.utf16LeToUtf8(&name_buf, entry.name(view));
        const name = name_buf[0..name_len];

        switch (entry.kind) {
            .file => {
                const file = entry.asFile();
                const stat = file.stat(view);

                const output_file = dir.createFile(name, .{}) catch |err| {
                    log.err("could not create file '{s}': {t}", .{name, err});
                    continue;
                };
                defer output_file.close();

                var file_buf: [2048]u8 = undefined;
                var file_writer = output_file.writerStreaming(&file_buf);

                try reader.seekTo(data_offset + stat.offset);
                try reader.interface.streamExact64(&file_writer.interface, stat.size);
                try file_writer.interface.flush();
            },
            .directory => {
                const directory = entry.asDirectory();

                var output_directory = dir.makeOpenPath(name, .{}) catch |err| {
                    log.err("could not make dir '{s}': {t}", .{name, err});
                    continue;
                };
                defer output_directory.close();

                try dumpDirectory(reader, data_offset, view, directory, output_directory);
            },
        }
    }
}

const Dump = @This();

const log = std.log.scoped(.romfs);

const std = @import("std");
const zitrus = @import("zitrus");
const romfs = zitrus.horizon.fmt.ncch.romfs;
