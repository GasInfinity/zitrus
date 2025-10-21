pub const description = "Make an ExeFS.";

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
    .file = "Add a file to the ExeFS",
};

pub const switches = .{
    .output = 'o',
    .file = 'f',
};

pub const File = struct {
    pub const descriptions = .{
        .name = "Name stored in the ExeFS, maximum is 8 characters long",
        .path = "Input file to include",
    };

    name: []const u8,
    path: []const u8,
};

const ProcessedFile = struct {
    opened: std.fs.File,
    reader: std.fs.File.Reader,
};

output: ?[]const u8,
file: zdap.BoundedArray(File, exefs.max_files),

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&output_buffer);

    var file_data: zdap.BoundedArray(exefs.File, exefs.max_files) = .empty;
    defer for (file_data.constSlice()) |f| arena.free(f.data);

    for (args.file.constSlice()) |f| {
        if (f.name.len > 8) {
            log.err("file name '{s}' is longer than 8 characters", .{f.name});
            return 1;
        }
    }

    for (args.file.constSlice()) |f| {
        const input_file = cwd.openFile(f.path, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ f.path, err });
            return 1;
        };

        var reader = input_file.readerStreaming(&.{});
        const data = try reader.interface.allocRemaining(arena, .unlimited);

        file_data.appendAssumeCapacity(.init(f.name, data));
    }

    try exefs.write(&output_writer.interface, file_data.constSlice());
    try output_writer.interface.flush();
    return 0;
}

const Make = @This();

const log = std.log.scoped(.exefs);

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;

const zdap = @import("zdap");
