// TODO: Extract this into a separate library
pub fn Context(Color: type) type {
    return struct {
        const Ctx = @This();

        pub const PixelColor = Color;
        pub const SpriteDrawingOptions = struct {
            x: usize = 0,
            y: usize = 0,
            width: usize = 0,
            height: usize = 0,
            transparency_color: ?PixelColor = null,

            flip_h: bool = false,
            flip_v: bool = false,
        };

        framebuffer: []PixelColor,
        width: usize,

        pub fn init(framebuffer: []PixelColor, width: usize) Ctx {
            return Ctx{
                .framebuffer = framebuffer,
                .width = width,
            };
        }

        pub fn initBuffer(framebuffer: []u8, width: usize) Ctx {
            return Ctx{
                .framebuffer = std.mem.bytesAsSlice(PixelColor, framebuffer),
                .width = width,
            };
        }

        pub fn drawRectangle(ctx: Ctx, x: isize, y: isize, width: usize, height: usize, color: PixelColor) void {
            const x2: usize = @as(usize, @bitCast(x)) +% width;
            const y2: usize = @as(usize, @bitCast(y)) +% height;

            const x1: usize = @max(0, x);
            const y1: usize = @max(0, y);
            for (y1..y2) |j| {
                const offset = j * ctx.width;

                // TODO: Make wrapping configurable
                if (offset >= ctx.framebuffer.len) {
                    break;
                }

                for (x1..x2) |i| {
                    if (i >= ctx.width) {
                        break;
                    }

                    ctx.framebuffer[offset + i] = color;
                }
            }
        }

        pub fn drawSprite(ctx: Ctx, x: isize, y: isize, total_width: usize, sprite: []const PixelColor, options: SpriteDrawingOptions) void {
            const total_height = @divExact(sprite.len, total_width);

            const x1: usize = @max(0, x);
            const y1: usize = @max(0, y);

            const abs_x = @abs(x);
            const abs_y = @abs(y);

            const sprite_width = if (options.width == 0) total_width else options.width;
            const sprite_height = if (options.height == 0) total_height else options.height;

            if ((x < 0 and abs_x >= sprite_height) or (y < 0 and abs_y >= sprite_height)) {
                return;
            }

            const sprite_x1, const width = if (x < 0)
                .{ options.x + if (options.flip_h) 0 else abs_x, sprite_width - abs_x }
            else
                .{ options.x, sprite_width };

            const sprite_x2 = sprite_x1 + width;

            const sprite_y1, const height = if (y < 0)
                .{ options.y + if (options.flip_v) 0 else abs_y, sprite_height - abs_y }
            else
                .{ options.y, sprite_height };

            const sprite_y2 = sprite_y1 + height;

            var cy: usize = y1;
            for (0..height) |j| {
                defer cy += 1;
                const offset = cy * ctx.width;
                const sprite_offset = (if (options.flip_v) (sprite_y2 - j - 1) else (sprite_y1 + j)) * total_width;

                // TODO: Make wrapping configurable
                if (offset >= ctx.framebuffer.len) {
                    break;
                }

                var cx: usize = x1;
                for (0..width) |i| {
                    defer cx += 1;

                    if (cx >= ctx.width) {
                        break;
                    }

                    const sprite_index = sprite_offset + (if (options.flip_h) (sprite_x2 - i - 1) else (sprite_x1 + i));
                    const color = sprite[sprite_index];

                    if (options.transparency_color) |transparent| {
                        if (std.meta.eql(color, transparent)) {
                            continue;
                        }
                    }

                    ctx.framebuffer[offset + cx] = color;
                }
            }
        }
    };
}

const std = @import("std");
