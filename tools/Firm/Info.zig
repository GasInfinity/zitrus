pub const description = "List the sections of a firmware and optionally check their hashes.";

pub const descriptions: plz.Descriptions(@This()) = .{
    .minify = "Emit the neccesary whitespace only",
    .@"check-hash" = "Check hashes of the sections inside the FIRM",
    .@"detect-content" = "Detect the content of the sections inside the FIRM",
};

pub const short: plz.Short(@This()) = .{
    .minify = 'm',
    .@"check-hash" = 'c',
    .@"detect-content" = 'd',
};

minify: ?void,
@"check-hash": ?void,
@"detect-content": ?void,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "Input file. Use '-' for standard input",
    };

    input: []const u8,
},

pub fn run(args: Info, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();
    const input_file, const input_should_close = if (!std.mem.eql(u8, args.@"--".input, "-"))
        .{ cwd.openFile(io, args.@"--".input, .{ .mode = .read_only }) catch |err| {
            log.err("could not open FIRM '{s}': {t}", .{ args.@"--".input, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    var buf: [@sizeOf(firm.Header)]u8 = undefined;
    var input_reader = input_file.reader(io, &buf);
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
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const writer = &stdout_writer.interface;

    var serializer: std.zon.Serializer = .{
        .options = .{
            .whitespace = args.minify == null,
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

        if (args.@"check-hash") |_| {
            try input_reader.seekTo(section.offset);

            const data = try reader.readAlloc(arena, section.size);
            defer arena.free(data);

            try section_info.field("hash-check", section.check(data), .{});
        }

        if (args.@"detect-content") |_| {
            const start = section.address;
            const end = start + section.size;
            const detected: Detected = if (firm_hdr.arm11_entry >= start and firm_hdr.arm11_entry <= end)
                .arm11
            else if (firm_hdr.arm9_entry >= start and firm_hdr.arm9_entry <= end)
                .arm9
            else
                .binary;

            try section_info.field("detected", detected, .{});
        }

        try section_info.end();
    }
    try sections_info.end();
    try firm_info.end();
    try writer.writeByte('\n');

    try writer.flush();
    return 0;
}

const Detected = enum {
    binary,
    arm9,
    arm11,
};

const Info = @This();

const log = std.log.scoped(.firm);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const firm = zitrus.fmt.firm;
