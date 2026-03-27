//! Software bitmap font renderer using PSF fonts. 
//!
//! Assumes 3DS framebuffers as such it will render the text rotated.
//!
//! Can be used for both general purpose text rendering (by setting x and y)
//! or as a debug console.
//!   
//! All coordinates should be given as if you were rendering to the rotated screen,
//! i.e rendering to 400x240 instead of 240x400. Rotation is handled transparently.

const vtable: Writer.VTable = .{
    .drain = drain,
};

/// A simple PSF parser, assumes data is alive until deinit.
///
/// - https://en.wikipedia.org/wiki/PC_Screen_Font#File_header
/// - https://wiki.osdev.org/PC_Screen_Font
pub const Font = struct {
    /// 3x6
    pub const tom_thumb: Font = blk: {
        @setEvalBranchQuota(200000);
        break :blk .initComptime(256, @embedFile("font/tom-thumb.psfu"));
    };

    pub const spleen_5x8: Font = blk: {
        @setEvalBranchQuota(200000);
        break :blk .initComptime(256, @embedFile("font/spleen-5x8.psfu"));
    };

    pub const spleen_6x12: Font = blk: {
        @setEvalBranchQuota(200000);
        break :blk .initComptime(256, @embedFile("font/spleen-6x12.psfu"));
    };

    /// 8x16
    pub const bizcat: Font = blk: {
        @setEvalBranchQuota(200000);
        break :blk .initComptime(256, @embedFile("font/bizcat.psfu"));
    };

    pub const HeaderV1 = extern struct {
        pub const CheckError = error{NotPsf1};
        pub const magic_value: [2]u8 = .{0x36, 0x04};

        pub const Mode = packed struct(u8) {
            @"512": bool = false,
            has_unicode: bool = false,
            has_unicode_also: bool = false,
            _: u5 = 0,
        };

        magic: [2]u8 = magic_value,
        mode: Mode,
        height: u8,

        pub fn check(hdr: HeaderV1) CheckError!void {
            if (!std.mem.eql(u8, &hdr.magic, &magic_value)) return error.NotPsf1;
        }
    };

    pub const HeaderV2 = extern struct {
        pub const CheckError = error{NotPsf2};
        pub const magic_value: [4]u8 = .{0x72, 0xB5, 0x4A, 0x86};

        pub const Flags = packed struct(u8) {
            has_unicode: bool = false,
            _: u7 = 0,
        };

        magic: [4]u8 = magic_value,
        version: u32 = 0,
        header_size: u32 = @sizeOf(HeaderV2),
        flags: Flags,
        glyphs: u32,
        bytes_per_glyph: u32,
        glyph_height: u32,
        glyph_width: u32,

        pub fn check(hdr: HeaderV2) CheckError!void {
            if (!std.mem.eql(u8, &hdr.magic, &magic_value)) return error.NotPsf2;
        }
    };

    map: []const u32,
    glyphs: []const u8,
    glyphs_count: u32,
    bytes_per_glyph: u32,
    glyph_width: u32,
    glyph_height: u32,

    pub fn initComptime(comptime unicode_map_len: usize, comptime data: []const u8) Font {
        var unicode_map_buffer: [unicode_map_len]u32 = undefined;
        const fnt = Font.init(&unicode_map_buffer, data) catch unreachable; 
        const unicode_map = unicode_map_buffer; // needed to avoid "X depends on comptime var"

        return .{
            .map = &unicode_map,
            .glyphs = fnt.glyphs,
            .glyphs_count = fnt.glyphs_count,
            .bytes_per_glyph = fnt.bytes_per_glyph,
            .glyph_width = fnt.glyph_width,
            .glyph_height = fnt.glyph_height,
        };
    }

    pub fn init(map_buffer: []u32, data: []const u8) error{NotPsf, InvalidPsf}!Font {
        const psf_v1: HeaderV1 = std.mem.bytesAsValue(HeaderV1, data).*;
        const psf_v2: HeaderV2 = std.mem.bytesAsValue(HeaderV2, data).*;

        if (psf_v1.check()) |_| {
            const glyphs: u32 = if (psf_v1.mode.@"512") @as(u32, 512) else 256;
            const bytes_per_glyph: u32 = @divExact(std.mem.alignForward(u32, psf_v1.height, 8), 8);

            const map: []const u32 = if (psf_v1.mode.has_unicode or psf_v1.mode.has_unicode_also) map: {
                const uni_info: []align(1) const u16 = @ptrCast(data[@sizeOf(HeaderV1) + (glyphs * bytes_per_glyph)..]);

                @memset(map_buffer, 0);
                
                var i: u32 = 0;
                var glyph: u32 = 0;

                while (glyph < glyphs and i < uni_info.len) {
                    switch (uni_info[i]) {
                        0xFFFE => while (uni_info[i] != 0xFFFF) : (i += 1) {},
                        0xFFFF => {
                            glyph += 1;
                            i += 1;
                        },
                        else => |v| {
                            if (v < map_buffer.len) map_buffer[v] = glyph;
                            i += 1;
                        },
                    }
                }

                break :map map_buffer;
            } else &.{};

            return .{
                .map = map,
                .glyphs = data[@sizeOf(HeaderV1)..][0..glyphs * bytes_per_glyph],
                .glyphs_count = glyphs,
                .bytes_per_glyph = bytes_per_glyph,
                .glyph_width = 8,
                .glyph_height = psf_v1.height,
            };
        } else |_| {}        

        if (psf_v2.check()) |_| {
            const map: []const u32 = if (psf_v2.flags.has_unicode) map: {
                const uni_info: []const u8 = @ptrCast(data[psf_v2.header_size + (psf_v2.glyphs * psf_v2.bytes_per_glyph)..]);

                var i: u32 = 0;
                var glyph: u32 = 0;

                while (glyph < psf_v2.glyphs and i < uni_info.len) {
                    switch (uni_info[i]) {
                        0xFE => while (uni_info[i] != 0xFF) : (i += 1) {},
                        0xFF => {
                            glyph += 1;
                            i += 1;
                        },
                        else => |v| {
                            const seq_len = std.unicode.utf8ByteSequenceLength(v) catch return error.InvalidPsf;

                            const c = switch (seq_len) {
                                1 => v,
                                2 => std.unicode.utf8Decode2(uni_info[i..][0..2].*) catch return error.InvalidPsf,
                                3 => std.unicode.utf8Decode3(uni_info[i..][0..3].*) catch return error.InvalidPsf,
                                // outside of the map
                                4 => {
                                    i += seq_len;
                                    continue;
                                },
                                else => unreachable,
                            };

                            if (c < map_buffer.len) map_buffer[c] = glyph;
                            i += seq_len;
                        },
                    }
                }

                break :map map_buffer;
            } else &.{};

            return .{
                .map = map,
                .glyphs = data[psf_v2.header_size..][0..psf_v2.glyphs * psf_v2.bytes_per_glyph],
                .glyphs_count = psf_v2.glyphs,
                .bytes_per_glyph = psf_v2.bytes_per_glyph,
                .glyph_width = psf_v2.glyph_width,
                .glyph_height = psf_v2.glyph_height,
            }; 
        } else |_| {}

        return error.NotPsf;
    }

    pub fn deinit(psf: Font, gpa: std.mem.Allocator) void {
        gpa.free(psf.map);
    }

    pub fn glyphOf(psf: Font, c: u16) []const u8 {
        const glyph = if (c < psf.map.len)
            psf.map[c]
        else if(c < psf.glyphs_count)
            c
        else 
            0;
        return psf.glyphs[glyph * psf.bytes_per_glyph..][0..psf.bytes_per_glyph];
    }
};

pub const VerticalBehavior = enum {
    @"error",
    scroll,
    wrap,
};

pub const HorizontalBehavior = enum {
    wrap,
    wrap_next_line,
    discard,
};

fb: []u8,
stride: usize,

psf: Font,

cx: u16,
cy: u16,
x: u16,
y: u16,
width: u16,
height: u16,
bytes_per_pixel: u8,
color: [4]u8,
clear_color: [4]u8,
horizontal_overflow: HorizontalBehavior,
vertical_overflow: VerticalBehavior,

writer: Writer,

pub fn init(buffer: []u8, psf: Font, fb: []u8, stride: usize, x: u16, y: u16, width: u16, height: u16, bpp: u8) error{InvalidPsf}!PsfWriter {
    std.debug.assert(x < width and y < height);

    return .{
        .fb = fb,
        .stride = stride,
        .psf = psf,

        .cx = 0,
        .cy = 0,
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .bytes_per_pixel = bpp,
        .color = @splat(0xFF),
        .clear_color = @splat(0x00),
        .horizontal_overflow = .wrap_next_line,
        .vertical_overflow = .scroll,

        .writer = .{
            .buffer = buffer,
            .end = 0,
            .vtable = &vtable,
        },
    };
}

fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    defer w.end = 0;

    const psf: *PsfWriter = @alignCast(@fieldParentPtr("writer", w));
    try psf.writeAll(w.buffered());

    var written: usize = 0;
    for (data[0..data.len - 1]) |buf| {
        try psf.writeAll(buf);
        written += buf.len;
    }

    const splatted = data[data.len - 1];
    written += splatted.len * splat;

    for (0..splat) |_| try psf.writeAll(splatted);
    return written;
}

pub fn writeAll(psf_w: *PsfWriter, bytes: []const u8) Writer.Error!void {
    for (bytes) |c| try psf_w.writeCharacter(c);
}

pub fn writeCharacter(psf_w: *PsfWriter, c: u16) Writer.Error!void {
    const psf = psf_w.psf;

    switch(c) {
        '\n' => {
            psf_w.cx = 0;
            psf_w.cy += @intCast(psf.glyph_height);
            return;
        },
        else => {},
    }

    const end_x = blk: {
        const end = psf_w.cx + psf.glyph_width;

        const w = if (end > psf_w.width)
            w: switch (psf_w.horizontal_overflow) {
                .wrap => {
                    psf_w.cx = 0;
                    break :w psf.glyph_width;
                },
                .wrap_next_line => {
                    psf_w.cy += @intCast(psf.glyph_height);
                    continue :w .wrap;
                },
                .discard => psf_w.width - psf_w.cx,
            } 
        else
            psf.glyph_width;

        break :blk psf_w.cx + w;
    };

    const end_y = psf_w.cy + psf.glyph_height;

    const h: usize = if (end_y > psf_w.height)
        h: switch (psf_w.vertical_overflow) {
            .@"error" => return error.WriteFailed,
            .scroll => {
                psf_w.scrollUp(1);
                break :h psf.glyph_height;
            },
            .wrap => {
                psf_w.cy = 0;
                break :h psf.glyph_height;
            },
        }
    else 
        psf.glyph_height;
    defer psf_w.cx = @intCast(end_x);

    const glyph_bytes_per_width = std.mem.alignForward(usize, psf.glyph_width, 8) >> 3;
    const glyph: []const u8 = psf.glyphOf(c);
    const bpp: usize = psf_w.bytes_per_pixel;
    const color = psf_w.color[0..bpp];
    const height_bytes = (psf.glyph_height * bpp);
    const fb = psf_w.fb;

    // Basically:
    //
    // y + x where:
    // - y is only affected by the stride (obviously) doesn't need any more transformations.
    // - x starts at the top, which is in fact stride - bpp and obviously
    // subtracting the position instead of adding it (as we're going to lower positions).
    var fb_position = (psf_w.stride * (psf_w.x + psf_w.cx)) + ((psf_w.stride - bpp) - ((psf_w.y + psf_w.cy) * bpp));
    const y_advance = psf_w.stride + height_bytes;

    // NOTE: here we do width -> height instead of height -> width as 
    // we want to render the text rotated.
    for (0..psf.glyph_width) |gx| {
        const byte_offset = (gx >> 3);
        const bit_offset = 7 - (gx & 7);

        for (0..h) |gy| {
            defer fb_position -= bpp;

            const enabled = ((glyph[(gy * glyph_bytes_per_width) + byte_offset] >> @intCast(bit_offset)) & 1) != 0;
            if (!enabled) continue;
            @memcpy(fb[fb_position..][0..psf_w.bytes_per_pixel], color);
        }

        fb_position += y_advance;
    }
}

pub fn scrollUp(psf_w: *PsfWriter, lines: usize) void {
    const pixels_scrolled = lines * psf_w.psf.glyph_height;
    defer psf_w.cy -= @intCast(pixels_scrolled);

    const bytes_scrolled = pixels_scrolled * psf_w.bytes_per_pixel;
    const copied_line = ((psf_w.height - pixels_scrolled) * psf_w.bytes_per_pixel) - psf_w.y;
    const height_bytes = psf_w.height * psf_w.bytes_per_pixel;

    for (0..psf_w.width) |y| {
        const line = psf_w.fb[psf_w.y + (y * psf_w.stride)..][0..height_bytes];

        @memmove(line[bytes_scrolled..], line[0..copied_line]);

        const cleared_line = line[0..bytes_scrolled];

        var i: usize = 0;
        while (i < bytes_scrolled) : (i += psf_w.bytes_per_pixel) {
            @memcpy(cleared_line[i..][0..psf_w.bytes_per_pixel], psf_w.clear_color[0..psf_w.bytes_per_pixel]);
        }
    }
}

pub fn clear(psf_w: *PsfWriter) void {
    const height_bytes = psf_w.height * psf_w.bytes_per_pixel;

    for (0..psf_w.width) |y| {
        const line = psf_w.fb[psf_w.y + (y * psf_w.stride)..][0..height_bytes];
        
        var i: usize = 0;
        while (i < height_bytes) : (i += psf_w.bytes_per_pixel) {
            @memcpy(line[i..][0..psf_w.bytes_per_pixel], psf_w.clear_color[0..psf_w.bytes_per_pixel]);
        }
    }
}

pub fn setColor(psf_w: *PsfWriter, comptime T: type, color: T) void {
    std.debug.assert(psf_w.bytes_per_pixel == @sizeOf(T));
    psf_w.color[0..@sizeOf(T)].* = @bitCast(color);
}

pub fn setClearColor(psf_w: *PsfWriter, comptime T: type, color: T) void {
    std.debug.assert(psf_w.bytes_per_pixel == @sizeOf(T));
    psf_w.clear_color[0..@sizeOf(T)].* = @bitCast(color);
}

const PsfWriter = @This();

const std = @import("std");
const Writer = std.Io.Writer;
