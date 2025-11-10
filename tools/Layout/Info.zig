pub const description = "WIP Layout Info RE";

pub const descriptions = .{
};

pub const switches = .{
};

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
            log.err("could not open CLYT '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(&buf);
    const reader = &input_reader.interface;

    const hdr = try reader.takeStruct(lyt.Header, .little);

    hdr.check(clyt.magic) catch |err| {
        log.err("could not open CLIM: {t}", .{err});
        return 1;
    };

    try reader.discardAll(hdr.header_size - @sizeOf(lyt.Header));

    for (0..hdr.blocks) |_| {
        const block_hdr = try reader.takeStruct(lyt.block.Header, .little);

        switch (block_hdr.kind) {
            .layout => {
                const lyt_hdr = try reader.takeStruct(clyt.Layout, .little);
                log.info("{t} | ({}, {})", .{lyt_hdr.origin, lyt_hdr.canvas_size[0], lyt_hdr.canvas_size[1]});
            },
            .textures, .fonts => |kind| {
                const kind_name: []const u8 = switch (kind) {
                    .textures => "texture",
                    .fonts => "font",
                    else => unreachable,
                };

                const entries = try reader.takeInt(u32, .little);
                const name_offsets = try reader.readSliceEndianAlloc(arena, u32, entries, .little);
                defer arena.free(name_offsets);

                const name_table = try reader.readAlloc(arena, block_hdr.size - (@sizeOf(lyt.block.Header) + @sizeOf(u32) + entries * @sizeOf(u32)));
                defer arena.free(name_table);

                for (name_offsets) |offset| {
                    const name = std.mem.span(@as([*:0]const u8, @ptrCast(name_table))[offset - (entries * @sizeOf(u32))..]);

                    log.info("Dependency on {s}: {s}", .{kind_name, name});
                }
            },
            .materials => {
                const entries = try reader.takeInt(u32, .little);
                const entry_offsets = try reader.readSliceEndianAlloc(arena, u32, entries, .little);
                defer arena.free(entry_offsets);

                var last: usize = 0;
                for (entry_offsets) |offset| {
                    const real_offset = offset - (@sizeOf(lyt.block.Header) + @sizeOf(u32) + entry_offsets.len * @sizeOf(u32));
                    try reader.discardAll(real_offset - last);

                    const mat = try reader.takeStruct(clyt.Material, .little); 
                    const name = mat.name[0..std.mem.indexOfScalar(u8, &mat.name, 0) orelse mat.name.len];

                    log.info("Material {s}", .{name});
                    log.info("Combiner Buffer Color: {any}", .{mat.combiner_buffer_constant});
                    log.info("Flags: {}", .{mat.flags});
                    last = real_offset + @sizeOf(clyt.Material);
                }

                try reader.discardAll(block_hdr.size - (@sizeOf(lyt.block.Header) + @sizeOf(u32) + entry_offsets.len * @sizeOf(u32) + last));
            },
            .pane => {
                const pane = try reader.takeStruct(clyt.Pane, .little);
                const name = pane.name[0..std.mem.indexOfScalar(u8, &pane.name, 0) orelse pane.name.len];
                log.info("Pane {s}: {}", .{name, pane});
            },
            .picture => {
                const picture = try reader.takeStruct(clyt.Picture, .little);
                try reader.discardAll(picture.coordinate_entries * @sizeOf([4][2]f32));

                const name = picture.pane.name[0..std.mem.indexOfScalar(u8, &picture.pane.name, 0) orelse picture.pane.name.len];
                log.info("Picture {s}: {}", .{name, picture});
            },
            .group => {
                const group = try reader.takeStruct(clyt.Group, .little);
                const name = group.name[0..std.mem.indexOfScalar(u8, &group.name, 0) orelse group.name.len];

                const references = try reader.readSliceEndianAlloc(arena, clyt.Pane.Reference, group.panes, .little);
                defer arena.free(references);

                log.info("Group {s}", .{name});

                for (references) |ref| {
                    const ref_slice = ref[0..std.mem.indexOfScalar(u8, &ref, 0) orelse ref.len];
                    log.info("references: {s}", .{ref_slice});
                }
            },
            else => {
                try reader.discardAll(block_hdr.size - @sizeOf(lyt.block.Header));
                log.err("TODO unhandled block kind: {s}", .{@as([4]u8, @bitCast(@intFromEnum(block_hdr.kind)))});
                continue;
            }
        }
    }

    return 0;
}

const Info = @This();

const log = std.log.scoped(.clyt);

const std = @import("std");
const zitrus = @import("zitrus");
const etc = zitrus.compress.etc;

const lyt = zitrus.horizon.fmt.layout;
const clyt = lyt.clyt;
