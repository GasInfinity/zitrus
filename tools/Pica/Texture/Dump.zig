pub const description = "Dump PICA200-native texture files";

pub const descriptions: plz.Descriptions(@This()) = .{
    .output = "Output file, if none stdout is used",
};

pub const short: plz.Short(@This()) = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "File to assemble, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Dump, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |input|
        .{ cwd.openFile(io, input, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ input, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(io, out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdout(), false };
    defer if (output_should_close) output_file.close(io);

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &input_buffer);
    const in = &input_reader.interface;

    const hdr: zptx.Header = try in.takeStruct(zptx.Header, .little);
    const width = @as(usize, 1) << hdr.meta.width_log2;
    const height = @as(usize, 1) << hdr.meta.height_log2;

    var img = try zigimg.Image.create(arena, width, height, .rgba32);
    defer img.deinit(arena);

    switch (hdr.meta.format) {
        .abgr8888 => {
            const tiled_pixels: []u8 = try in.readAlloc(arena, width * height * @sizeOf(zptx.Header.Metadata.Format.Abgr8888));
            defer arena.free(tiled_pixels);

            pica.morton.convert(.untile, 8, @ptrCast(img.pixels.rgba32), tiled_pixels, .full(width, height, @sizeOf(zptx.Header.Metadata.Format.Abgr8888)));

            for (img.pixels.rgba32) |*pixel| pixel.* = @bitCast(@byteSwap(@as(u32, @bitCast(pixel.*))));
        },
        else => @panic("TODO"),
    }

    var output_buffer: [4096]u8 = undefined;
    try img.writeToFile(arena, io, output_file, &output_buffer, .{ .png = .{} });
    return 0;
}

const Dump = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const zigimg = @import("zigimg");

const zptx = zitrus.fmt.zptx;
const etc = zitrus.compress.etc;
const pica = zitrus.hardware.pica;
