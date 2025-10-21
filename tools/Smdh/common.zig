const tile_size = 8;

pub const TilingStrategy = enum { tile, untile };

// TODO: This can be in zitrus
pub fn tileImage(comptime strategy: TilingStrategy, size: usize, dst_pixels: []Rgb565, src_pixels: []const Rgb565) void {
    const tiles = @divExact(size, tile_size);

    var i: u16 = 0;
    for (0..tiles) |y_tile| {
        for (0..tiles) |x_tile| {
            const y_start = y_tile * tile_size;
            const x_start = x_tile * tile_size;

            for (0..(tile_size * tile_size)) |tile| {
                // NOTE: We know the max size is 63 so we can squeeze it into 6 bits
                const x, const y = pica.morton.toDimensions(u6, 2, @intCast(tile));
                const src_pixel, const dst_pixel = switch (strategy) {
                    .tile => .{ &src_pixels[(y_start + y) * size + x_start + x], &dst_pixels[i] },
                    .untile => .{ &src_pixels[i], &dst_pixels[(y_start + y) * size + x_start + x] },
                };

                dst_pixel.* = src_pixel.*;
                i += 1;
            }
        }
    }
}

const Rgb565 = pica.ColorFormat.Rgb565;

const std = @import("std");
const zigimg = @import("zigimg");
const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;
