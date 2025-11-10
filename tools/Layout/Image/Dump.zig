pub const description = "Dump a (CTR) Layout Image to a PKM (if ETC1) or to the specified output format.";

pub const descriptions = .{
    .output = "Output directory / file. Directory outputs must be specified, if none stdout is used",
    .ofmt = "Output format, it is not guaranteed that all work, support depends on zigimg as-is. PNG is used by default",
};

pub const switches = .{
    .output = 'o',
    .verbose = 'v',
};

pub const OutputFormat = zigimg.Image.Format;

output: ?[]const u8,
ofmt: OutputFormat = .png,
verbose: bool,

@"--": struct {
    pub const descriptions = .{ .input = "Input file, if none stdin is used" };

    input: ?[]const u8,
},

pub fn main(args: Dump, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open CLIM '{s}': {t}", .{ in, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(&buf);
    const in_reader = &input_reader.interface;

    const file_data = try in_reader.allocRemaining(arena, .unlimited);
    defer arena.free(file_data);

    var reader: std.Io.Reader = .fixed(file_data);

    var out_buf: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&out_buf);
    const writer = &output_writer.interface;

    reader.seek = reader.end - @sizeOf(clim.Footer);
    const footer = try reader.takeStruct(clim.Footer, .little);

    if (footer.header_offset > file_data.len) {
        log.err("not a CLIM or corrupted, invalid file offset, bigger than file?", .{});
        return 1;
    }

    reader.seek = footer.header_offset;
    const hdr = try reader.takeStruct(lyt.Header, .little);

    hdr.check(clim.magic) catch |err| {
        log.err("could not open CLIM: {t}", .{err});
        return 1;
    };

    try reader.discardAll(hdr.header_size - @sizeOf(lyt.Header));

    var maybe_meta: ?clim.Image = null;

    for (0..hdr.blocks) |_| {
        const block_hdr = try reader.takeStruct(lyt.block.Header, .little);

        switch (block_hdr.kind) {
            .image => {
                const meta = try reader.takeStruct(clim.Image, .little);

                maybe_meta = meta;
                if (args.verbose) log.info("Width: {} | Height: {} | Format: {}", .{ meta.width, meta.height, meta.format });
            },
            else => {
                log.warn("Unknown block kind: {}. PLEASE, open an issue! Skipping...", .{block_hdr.kind});
                try reader.discardAll(block_hdr.size - @sizeOf(lyt.block.Header));
            },
        }
    }

    const meta = maybe_meta orelse {
        log.err("could not find 'imag' metadata block in CLIM", .{});
        return 1;
    };

    switch (meta.format) {
        _ => {
            log.err("unknown pixel format: {}", .{@intFromEnum(meta.format)});
            return 1;
        },
        else => {},
    }

    const width_po2: u16 = @intCast(@max(8, std.math.ceilPowerOfTwoPromote(u16, meta.width)));
    const height_po2: u16 = @intCast(@max(8, std.math.ceilPowerOfTwoPromote(u16, meta.height)));
    const tiled_image_data: []const u8 = file_data[0..meta.format.native().scale(@as(usize, width_po2) * height_po2)];

    const untiled_image_data: []u8 = try arena.alloc(u8, tiled_image_data.len);
    defer arena.free(untiled_image_data);

    const default_encoder_opts = switch (args.ofmt) {
        inline else => |t| @unionInit(zigimg.Image.EncoderOptions, @tagName(t), if(@FieldType(zigimg.Image.EncoderOptions, @tagName(t)) == void) {} else .{}), 
    };

    switch (meta.format) {
        .i4, .a4 => {
            @memset(untiled_image_data, 0x00); // NOTE: undefined bits make partial updates impossible, we MUST do this!
            zitrus.hardware.pica.morton.convertNibbles(.untile, 8, width_po2, untiled_image_data, tiled_image_data);
            
            var img: zigimg.Image = try .create(arena, width_po2, height_po2, .grayscale4);
            defer img.deinit(arena);

            for (untiled_image_data, 0..) |src, i| {
                img.pixels.grayscale4[i*2] = .{ .value = @intCast(src & 0xF) };
                img.pixels.grayscale4[i*2+1] = .{ .value = @intCast(src >> 4) };
            }

            try img.writeToFile(arena, output_file, &out_buf, default_encoder_opts);
        },
        .ia88 => {
            zitrus.hardware.pica.morton.convert(.untile, 8, width_po2, @sizeOf(u16), untiled_image_data,  tiled_image_data);

            const img: zigimg.Image = try .fromRawPixelsOwned(width_po2, height_po2, untiled_image_data, .grayscale8Alpha);
            try img.writeToFile(arena, output_file, &out_buf, default_encoder_opts);
        },
        .etc1 => {
            // NOTE: Tile size of 2 as each ETC block is 4x4, also as we convert to ETC "pixels" we must divide width/height by 4!
            zitrus.hardware.pica.morton.convert(.untile, 2, @divExact(width_po2, etc.pixels_per_block), @sizeOf(etc.Block), untiled_image_data,  tiled_image_data);

            // NOTE: The 3DS stores ETC1 in little endian instead of big...
            const as_u64: []align(1) u64 = std.mem.bytesAsSlice(u64, untiled_image_data);
            for (as_u64) |*d| d.* = @byteSwap(d.*);

            try writer.writeStruct(etc.Pkm{
                .format = .etc1_rgb,
                .width = @intCast(width_po2),
                .height = @intCast(height_po2),
                .real_width = meta.width,
                .real_height = meta.height,
            }, .big);
            try writer.writeAll(untiled_image_data);
        },
        else => {
            log.err("TODO: {t}", .{meta.format});
            return 1;
        },
    }
    try writer.flush();
    return 0;
}

const Dump = @This();

const log = std.log.scoped(.clim);

const std = @import("std");
const zitrus = @import("zitrus");

const zigimg = @import("zigimg");
const etc = zitrus.compress.etc;

const lyt = zitrus.horizon.fmt.layout;
const clim = lyt.clim;
