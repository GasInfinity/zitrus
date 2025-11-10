pub const description = "List the sections of a firmware and optionally check their hashes.";

pub const descriptions = .{
    .minify = "Emit the neccesary whitespace only",
    .check_hash = "Check hashes of files inside the FIRM",
};

pub const switches = .{
    .minify = 'm',
    .check_hash = 'c',
};

minify: bool = false,
check_hash: bool = false,

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Info, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open FIRM '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    var buf: [@sizeOf(firm.Header)]u8 = undefined;
    var input_reader = input_file.reader(&buf);
    const reader = &input_reader.interface;

    const firm_hdr = reader.takeStruct(firm.Header, .little) catch |err| {
        log.err("could not read FIRM header: {t}", .{err});
        return 1;
    };

    firm_hdr.check() catch |err| switch (err) {
        error.UnalignedSectionOffset => log.warn("a section in the FIRM is not aligned!", .{}),
        else => {
            log.err("could not open FIRM: {t}", .{err});
            return 1;
        },
    };

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const writer = &stdout_writer.interface;

    var serializer: std.zon.Serializer = .{
        .options = .{
            .whitespace = !args.minify,
        },
        .writer = writer,
    };

    var firm_info = try serializer.beginStruct(.{});
    try firm_info.field("boot_priority", firm_hdr.boot_priority, .{});
    try firm_info.field("arm9_entry", firm_hdr.arm9_entry, .{});
    try firm_info.field("arm11_entry", firm_hdr.arm11_entry, .{});
    var sections_info = try firm_info.beginTupleField("sections", .{});
    for (&firm_hdr.sections) |section| {
        if (section.size == 0) continue;

        var section_info = try sections_info.beginStructField(.{});
        try section_info.field("address", section.address, .{});
        try section_info.field("offset", section.offset, .{});
        try section_info.field("size", section.size, .{});

        // Don't panic!
        switch (section.copy_method) {
            .ndma, .xdma, .memcpy => {
                try section_info.fieldPrefix("copy_method");
                try serializer.ident(@tagName(section.copy_method));
            },
            _ => try section_info.field("copy_method", @intFromEnum(section.copy_method), .{}),
        }

        if (args.check_hash) {
            try input_reader.seekTo(section.offset);

            const data = try reader.readAlloc(arena, section.size);
            defer arena.free(data);

            try section_info.field("hash-check", section.check(data), .{});
        }
        try section_info.end();
    }
    try sections_info.end();
    try firm_info.end();
    try writer.writeByte('\n');

    try writer.flush();
    return 0;
}

const Info = @This();

const log = std.log.scoped(.firm);

const std = @import("std");
const zitrus = @import("zitrus");
const firm = zitrus.fmt.firm;
