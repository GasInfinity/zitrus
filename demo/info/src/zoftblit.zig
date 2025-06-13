// TODO: Extract this into a separate library, II warning
pub fn Context(Color: type) type {
    return struct {
        const Ctx = @This();

        pub const PixelColor = Color;
        pub const Sprite = union(enum) {
            pub const Options = struct {
                x: usize = 0,
                y: usize = 0,
                width: usize = 0,
                height: usize = 0,
                flip_h: bool = false,
                flip_v: bool = false,
            };

            pub const Bit = struct { off: ?PixelColor = null, on: PixelColor };

            pub const Bitmap = struct {};

            pub const TransparentBitmap = struct {
                transparent: PixelColor,
            };

            bit,
            bitmap,
            transparent_bitmap,

            pub fn Data(comptime sprite: Sprite) type {
                return switch (sprite) {
                    .bit => type,
                    .bitmap, .transparent_bitmap => usize,
                };
            }

            pub fn Parameters(comptime sprite: Sprite) type {
                return switch (sprite) {
                    .bit => Bit,
                    .bitmap => Bitmap,
                    .transparent_bitmap => TransparentBitmap,
                };
            }

            pub fn width(comptime sprite: Sprite, data: sprite.Data()) usize {
                return switch (sprite) {
                    .bit => @bitSizeOf(data),
                    .bitmap, .transparent_bitmap => data,
                };
            }
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

        pub fn drawSprite(ctx: Ctx, comptime sprite: Sprite, x: isize, y: isize, data: sprite.Data(), buffer: []const (if (sprite == .bit) data else PixelColor), parameters: sprite.Parameters(), options: Sprite.Options) void {
            const width = sprite.width(data);
            const height = if (sprite == .bit) buffer.len else @divExact(buffer.len, width);

            const x1: usize = @max(0, x);
            const y1: usize = @max(0, y);

            const abs_x = @abs(x);
            const abs_y = @abs(y);

            const sprite_width = if (options.width == 0) width else @min(width, options.width);
            const sprite_height = if (options.height == 0) height else @min(height, options.height);

            if ((x < 0 and abs_x >= sprite_width) or (y < 0 and abs_y >= sprite_height)) {
                return;
            }

            const sprite_x1, const drawn_width = if (x < 0)
                .{ options.x + if (options.flip_h) 0 else abs_x, sprite_width - abs_x }
            else
                .{ options.x, sprite_width };

            const sprite_x2 = sprite_x1 + drawn_width;

            const sprite_y1, const drawn_height = if (y < 0)
                .{ options.y + if (options.flip_v) 0 else abs_y, sprite_height - abs_y }
            else
                .{ options.y, sprite_height };

            const sprite_y2 = sprite_y1 + drawn_height;

            var cy: usize = y1;
            for (0..drawn_height) |j| {
                defer cy += 1;
                const offset = cy * ctx.width;

                // TODO: Make wrapping configurable
                if (offset >= ctx.framebuffer.len) {
                    break;
                }

                var cx: usize = x1;
                switch (sprite) {
                    .bit => {
                        const sprite_offset = (if (options.flip_v) (sprite_y2 - j - 1) else (sprite_y1 + j));
                        const current_unit = buffer[sprite_offset];

                        for (0..drawn_width) |i| {
                            defer cx += 1;

                            if (cx >= ctx.width) {
                                break;
                            }

                            const current_bit = ((if (options.flip_h) (current_unit >> @intCast(width - i - 1)) else (current_unit >> @intCast(i))) & 0b1) != 0;
                            const color = if (current_bit) parameters.on else parameters.off;

                            if (color) |c| {
                                ctx.framebuffer[offset + cx] = c;
                            }
                        }
                    },
                    .bitmap, .transparent_bitmap => {
                        const sprite_offset = (if (options.flip_v) (sprite_y2 - j - 1) else (sprite_y1 + j)) * width;

                        for (0..drawn_width) |i| {
                            defer cx += 1;

                            if (cx >= ctx.width) {
                                break;
                            }

                            const sprite_index = sprite_offset + (if (options.flip_h) (sprite_x2 - i - 1) else (sprite_x1 + i));
                            const color = buffer[sprite_index];

                            if (sprite == .transparent_bitmap and std.meta.eql(color, parameters.transparent)) {
                                continue;
                            }

                            ctx.framebuffer[offset + cx] = color;
                        }
                    },
                }
            }
        }
    };
}

const std = @import("std");
