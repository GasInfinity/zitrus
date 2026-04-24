pub const description = "Dump a (CTR) Layout Image to a PKM (if ETC1) or to the specified output format.";

pub const descriptions: plz.Descriptions(@This()) = .{
    .output = "Output directory / file. Directory outputs must be specified, if none stdout is used",
    // .ofmt = "Output format, it is not guaranteed that all work, support depends on zigimg as-is. PNG is used by default",
};

pub const short: plz.Short(@This()) = .{
    .output = 'o',
    .verbose = 'v',
};

pub const OutputFormat = zigimg.Image.Format;

output: ?[]const u8,
ofmt: OutputFormat = .png,
verbose: ?void,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{ .input = "Input file, if none stdin is used" };

    input: ?[]const u8,
},

pub fn run(args: Dump, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();
    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(io, in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open CLIM '{s}': {t}", .{ in, err });
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

    var buf: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &buf);
    const in_reader = &input_reader.interface;

    const file_data = try in_reader.allocRemaining(arena, .unlimited);
    defer arena.free(file_data);

    var reader: std.Io.Reader = .fixed(file_data);

    var out_buf: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(io, &out_buf);
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
                if (args.verbose) |_| log.info("Width: {} | Height: {} | Format: {}", .{ meta.width, meta.height, meta.format });
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
        inline else => |t| @unionInit(zigimg.Image.EncoderOptions, @tagName(t), if (@FieldType(zigimg.Image.EncoderOptions, @tagName(t)) == void) {} else .{}),
    };

    switch (meta.format) {
        .i4, .a4 => {
            @memset(untiled_image_data, 0x00); // NOTE: undefined bits make partial updates impossible, we MUST do this!
            zitrus.hardware.pica.morton.convertNibbles(.untile, 8, width_po2, untiled_image_data, tiled_image_data);
            var img: zigimg.Image = try .create(arena, width_po2, height_po2, .grayscale4);
            defer img.deinit(arena);

            for (untiled_image_data, 0..) |src, i| {
                img.pixels.grayscale4[i * 2] = .{ .value = @intCast(src & 0xF) };
                img.pixels.grayscale4[i * 2 + 1] = .{ .value = @intCast(src >> 4) };
            }

            try img.writeToFile(arena, io, output_file, &out_buf, default_encoder_opts);
        },
        .ia88 => {
            zitrus.hardware.pica.morton.convert(.untile, 8, width_po2, @sizeOf(u16), untiled_image_data, tiled_image_data);

            const img: zigimg.Image = try .fromRawPixelsOwned(width_po2, height_po2, untiled_image_data, .grayscale8Alpha);
            try img.writeToFile(arena, io, output_file, &out_buf, default_encoder_opts);
        },
        .etc1 => {
            // NOTE: Tile size of 2 as each ETC block is 4x4, also as we convert to ETC "pixels" we must divide width/height by 4!
            const etc_width = @divExact(width_po2, etc.pixels_per_block);
            const etc_height = @divExact(height_po2, etc.pixels_per_block);
            zitrus.hardware.pica.morton.convert(.untile, 2, etc_width, @sizeOf(etc.Block), untiled_image_data, tiled_image_data);

            if (args.verbose) |_| log.info("ETC size in blocks {}x{}", .{ etc_width, etc_height });
            var img: zigimg.Image = try .create(arena, meta.width, meta.height, .rgb24);
            defer img.deinit(arena);

            const img_slice = img.pixels.rgb24;

            var etc_buf: [16][4]u8 = undefined;
            block_y: for (0..etc_height) |block_y| {
                if (block_y * 4 >= meta.height) break :block_y;

                for (0..etc_width) |block_x| {
                    if (block_x * 4 >= meta.width) continue :block_y;

                    const current = (block_y * etc_width + block_x) * @sizeOf(etc.Block);
                    const block: etc.Block = std.mem.littleToNative(etc.Block, @bitCast(untiled_image_data[current..][0..@sizeOf(etc.Block)].*));

                    block.bufUnpack(&etc_buf);
                    // XXX: remove this and make etc.zig its own thing!
                    // const repacked = etc.Block.pack(&etc_buf, .{ .quality = .high });
                    // repacked.block.bufUnpack(&etc_buf);

                    etc_y: for (0..etc.pixels_per_block) |etc_y| {
                        const y = block_y * 4 + etc_y;
                        if (y >= meta.height) break :etc_y;

                        for (0..etc.pixels_per_block) |etc_x| {
                            const x = block_x * 4 + etc_x;

                            if (x >= meta.width) continue :etc_y;

                            const index = y * meta.width + x;
                            const color = etc_buf[etc_y * 4 + etc_x];

                            img_slice[index] = .{
                                .r = color[0],
                                .g = color[1],
                                .b = color[2],
                            };
                        }
                    }
                }
            }

            try img.writeToFile(arena, io, output_file, &out_buf, default_encoder_opts);
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
const plz = @import("plz");
const zitrus = @import("zitrus");

const zigimg = @import("zigimg");
const etc = zitrus.compress.etc;

const lyt = zitrus.horizon.fmt.layout;
const clim = lyt.clim;
