pub const description = "List the sections of a firmware and optionally check their hashes.";

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
        .firm = "The firm to list from",
    };

    firm: []const u8,
},

pub fn main(args: Info, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const firm_file = cwd.openFile(args.@"--".firm, .{ .mode = .read_only }) catch |err| {
        log.err("could not open firm '{s}': {t}\n", .{ args.@"--".firm, err });
        return 1;
    };
    defer firm_file.close();

    var buf: [@sizeOf(firm.Header)]u8 = undefined;
    var exefs_reader = firm_file.reader(&buf);
    const reader = &exefs_reader.interface;

    const firm_hdr = try reader.takeStruct(firm.Header, .little);

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
        var section_info = try sections_info.beginStructField(.{});
        try section_info.field("address", section.address, .{});
        try section_info.field("offset", section.offset, .{});
        try section_info.field("size", section.size, .{});
        try section_info.field("copy_method", section.copy_method, .{});

        if (args.check_hash) {
            try exefs_reader.seekTo(section.offset);

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
