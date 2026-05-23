pub const description = "Make PICA200-native texture files";

pub const descriptions: plz.Descriptions(@This()) = .{
    .output = "Output file, if none stdout is used",
    .format = "Output format of the image, lossy conversion is performed",
    .quality = "Quality of ETC compression",
};

pub const short: plz.Short(@This()) = .{
    .output = 'o',
    .format = 'f',
    .quality = 'q',
};

const OutputFormat = zptx.Header.Metadata.Format;
const Quality = etc.Block.Packed.Quality;

output: ?[]const u8,
format: OutputFormat = .abgr8888,
quality: Quality = .medium,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "File to convert, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Make, io: std.Io, arena: std.mem.Allocator) !u8 {
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
    var img = zigimg.Image.fromFile(arena, io, input_file, &input_buffer) catch |err| {
        log.err("could not load input image: {t}", .{err});
        return 1;
    };
    defer img.deinit(arena);

    if (!std.math.isPowerOfTwo(img.width) or !std.math.isPowerOfTwo(img.height)) {
        log.err("image dimensions {d}x{d} are not a power of two (e.g 64x64, 64x128, etc...)", .{img.width, img.height});
        return 1;
    }

    if (img.width < 8 or img.height < 8) {
        log.err("image dimensions {d}x{d} below minimum of 8x8", .{img.width, img.height});
        return 1;
    }

    if (img.width > 1024 or img.height > 1024) {
        log.err("image dimensions {d}x{d} exceed maximum of 1024x1024", .{img.width, img.height});
        return 1;
    }

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(io, &output_buffer);
    const out = &output_writer.interface;

    const width_log2: u4 = @intCast(std.math.log2(img.width));
    const height_log2: u4 = @intCast(std.math.log2(img.height));
    const full_size = args.format.scale(img.width * img.height);

    const hdr: zptx.Header = .{
        .meta = .{
            .width_log2 = width_log2,
            .height_log2 = height_log2,
            .format = args.format,
            // TODO: Mips
            .levels = 1,
            // TODO: Layers (required for cubemaps)
            .layers = 1,
            .compression = .uncompressed,
        },
        .uncompressed_len = @intCast(full_size),
    };

    try out.writeStruct(hdr, .little);

    switch (args.format) {
        .abgr8888 => {
            const pixels = try arena.alloc(OutputFormat.Abgr8888, @sizeOf(OutputFormat.Abgr8888) * img.width * img.height);
            defer arena.free(pixels); 
            try img.convert(arena, .rgba32);

            pica.morton.convert(.tile, 8, @ptrCast(pixels), @ptrCast(img.pixels.rgba32), .full(img.width, img.height, @sizeOf(OutputFormat.Abgr8888)));

            for (pixels) |*pixel| pixel.* = @bitCast(@byteSwap(@as(u32, @bitCast(pixel.*))));
            try out.writeAll(@ptrCast(pixels));
        },
        .etc1 => {
            const etc_width = @divExact(img.width, etc.pixels_per_block);
            const etc_height = @divExact(img.height, etc.pixels_per_block);
            try img.convert(arena, .rgb24);

            const tiled_blocks = try arena.alloc(etc.Block, etc_width * etc_height);
            defer arena.free(tiled_blocks);

            const blocks = try arena.alloc(etc.Block, etc_width * etc_height);
            defer arena.free(blocks);

            var encoding: Io.Group = .init;
            defer encoding.cancel(io);

            var i: usize = 0;
            for (0..etc_height) |y| {
                for (0..etc_width) |x| {
                    encoding.async(io, encodeOneEtc, .{&img, x, y, &blocks[i], args.quality});
                    i += 1;
                }
            }

            try encoding.await(io);
            pica.morton.convert(.tile, 2, @ptrCast(tiled_blocks), @ptrCast(blocks), .full(etc_width, etc_height, @sizeOf(etc.Block)));
            try out.writeAll(@ptrCast(tiled_blocks)); // NOTE: encodeOne already stores it as little endian.
        },
        else => @panic("TODO"),
    }

    try out.flush();
    return 0;
}

fn encodeOneEtc(img: *const zigimg.Image, block_x: usize, block_y: usize, result: *etc.Block, quality: Quality) void {
    const pixels = img.pixels.rgb24;
    var etc_pixels: [16][4]u8 = undefined;

    const cx = block_x * etc.pixels_per_block;
    const cy = block_y * etc.pixels_per_block;

    var i: usize = 0;
    for (0..etc.pixels_per_block) |dy| {
        const y = cy + dy;
        const pix_start = y * img.width;

        for (0..etc.pixels_per_block) |dx| {
            const x = cx + dx;
            const pix = pixels[pix_start + x];
            etc_pixels[i] = .{pix.r, pix.g, pix.b, 255};
            i += 1;
        }
    }

    const pack = etc.Block.pack(&etc_pixels, .{ .quality = quality });
    result.* = @bitCast(std.mem.nativeToLittle(u64, @bitCast(pack.block)));
}

const Make = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const zigimg = @import("zigimg");

const Io = std.Io;

const zptx = zitrus.fmt.zptx;
const etc = zitrus.compress.etc;
const pica = zitrus.hardware.pica;
