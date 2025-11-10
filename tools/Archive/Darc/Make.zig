pub const description = "Make a DARC";

pub const descriptions = .{
    .output = "Output file, if none stdout is used.",
    .prefix = "Prefix to add, i.e multiple DARCs contain a '.' prefix before their contents. Can be none",
};

pub const switches = .{
    .output = 'o',
    .prefix = 'p',
};

output: ?[]const u8,
prefix: ?[]const u8,

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

    var builder: darc.Builder = .empty;
    defer builder.deinit(arena);

    {
        var darc_root = try builder.beginRoot(arena);
        defer darc_root.end(&builder);

        var prefixed_root, const end_root = if(args.prefix) |prefix| 
            .{ try darc_root.beginDirectory(&builder, arena, .utf8(prefix)), true }
        else 
            .{ darc_root, false};
        defer if(end_root) prefixed_root.end(&builder);

        addDirectory(&builder, arena, &root, &prefixed_root) catch |err| {
            log.err("couldn't create DARC: {t}", .{err});
            return 1;
        };
    }

    try builder.write(&output_writer.interface);
    try output_writer.interface.flush();
    return 0;
}

fn addDirectory(builder: *darc.Builder, gpa: std.mem.Allocator, dir: *std.fs.Dir, b_dir: *darc.Builder.Directory) !void {
    var it = dir.iterate();

    while (try it.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

        switch (entry.kind) {
            .directory => {
                var sub = dir.openDir(entry.name, .{ .iterate = true }) catch |err| {
                    log.err("error while opening directory '{s}': {t}... skipping", .{ entry.name, err });
                    continue;
                };
                defer sub.close();

                var sub_darc = try b_dir.beginDirectory(builder, gpa, .utf8(entry.name));
                defer sub_darc.end(builder);

                try addDirectory(builder, gpa, &sub, &sub_darc);
            },
            .file => {
                const file = dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                    log.err("error while opening file '{s}': {t}... skipping", .{ entry.name, err });
                    continue;
                };
                defer file.close();

                var buf: [@sizeOf(lyt.Header)]u8 = undefined;
                var reader = file.reader(&buf);

                const end_pos = try file.getEndPos();

                // XXX: Maybe we could allow doing this by file extension instead of all this dance?
                const alignment: std.mem.Alignment = if(end_pos > 4) blk: {
                    try reader.seekTo(try file.getEndPos() - 4);

                    const maybe_footer_header_offset = try reader.interface.peekInt(u32, .little);

                    if(maybe_footer_header_offset + @sizeOf(lyt.Header) > end_pos)
                        break :blk darc.min_alignment
                    else {
                        try reader.seekTo(maybe_footer_header_offset);

                        const hdr = try reader.interface.takeStruct(lyt.Header, .little);

                        hdr.check(lyt.clim.magic) catch break :blk darc.min_alignment;

                        break :blk .fromByteUnits(0x80); // XXX: Why do CLIMs have a bigger alignment? Do texture units need this? Wasn't it a minimum of 8?
                    }
                } else darc.min_alignment;

                try reader.seekTo(0);
                try b_dir.streamFile(builder, gpa, .utf8(entry.name), &reader.interface, alignment);
            },
            else => log.warn("ignoring entry '{s}', cannot handle entry kind: {t}", .{ entry.name, entry.kind }),
        }
    }
}

const Make = @This();

const log = std.log.scoped(.darc);

const std = @import("std");
const zitrus = @import("zitrus");
const hfmt = zitrus.horizon.fmt;
const darc = hfmt.archive.darc;

const lyt = hfmt.layout;
