pub const description = "Dump sections of a 3DS firmware file.";

pub const descriptions = .{ .section = "Section to dump, if none all sections are dumped", .output = "Output directory / file. Directory outputs must be specified, if none stdout is used" };

pub const switches = .{
    .section = 's',
    .output = 'o',
};

section: ?u2,
output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{ .input = "Input file, if none stdin is used" };

    input: ?[]const u8,
},

pub fn main(args: Dump, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open FIRM '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(&buf);
    const reader = &input_reader.interface;

    const header = reader.takeStruct(firm.Header, .little) catch |err| {
        log.err("could not read FIRM header: {t}", .{err});
        return 1;
    };

    header.check() catch |err| switch (err) {
        error.UnalignedSectionOffset => log.warn("a section in the FIRM is not aligned!", .{}),
        else => {
            log.err("could not open FIRM: {t}", .{err});
            return 1;
        },
    };

    if (args.section) |section_index| {
        const section = header.sections[section_index];

        if (section.size == 0) {
            log.err("section {} is empty", .{section_index});
            return 1;
        }

        try reader.discardAll(section.offset - @sizeOf(firm.Header));

        const contents = try reader.readAlloc(arena, section.size);
        defer arena.free(contents);

        if (!section.check(contents)) {
            log.err("stored hash for section {} does not match the newly computed hash, contents may be corrupted", .{section});
            return 1;
        }

        const output_file, const output_should_close = if (args.output) |out|
            .{ cwd.createFile(out, .{}) catch |err| {
                log.err("could not open output file '{s}': {t}", .{ out, err });
                return 1;
            }, true }
        else
            .{ std.fs.File.stdout(), false };
        defer if (output_should_close) output_file.close();

        var out_buf: [4096]u8 = undefined;
        var output_writer = output_file.writerStreaming(&out_buf);
        const writer = &output_writer.interface;

        try writer.writeAll(contents);
        try writer.flush();

        // Needed if we don't want broken pipes.
        _ = try reader.discardRemaining();
        return 0;
    }

    if (args.output == null) {
        log.err("output path is required when dumping all FIRM sections", .{});
        return 1;
    }

    const output_path = args.output.?;
    var output_directory = cwd.makeOpenPath(output_path, .{}) catch |err| {
        log.err("could not make path '{s}': {t}", .{ output_path, err });
        return 1;
    };
    defer output_directory.close();

    var section_name_buf: [128]u8 = undefined;
    for (&header.sections, 0..) |section, i| {
        if (section.size == 0) continue;

        const section_name = try std.fmt.bufPrint(&section_name_buf, "{}-{X}", .{ i, section.hash });
        const new_file = output_directory.createFile(section_name, .{
            .exclusive = true,
        }) catch |err| {
            log.err("error dumping section {}, '{s}' into '{s}': {t}", .{ i, section_name, output_path, err });
            continue;
        };
        defer new_file.close();

        var new_writer_buffer: [512]u8 = undefined;
        var new_writer = new_file.writerStreaming(&new_writer_buffer);

        try input_reader.seekTo(section.offset);
        try reader.streamExact(&new_writer.interface, section.size);
        try new_writer.interface.flush();
    }
    return 0;
}

const Dump = @This();

const log = std.log.scoped(.firm);

const std = @import("std");
const zitrus = @import("zitrus");
const firm = zitrus.fmt.firm;
