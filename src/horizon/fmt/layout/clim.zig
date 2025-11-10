//! **L**ayout **Im**age
//!
//! Weirdly it has a footer instead of a header and obviously image data is tiled.
//!
//! Based on the documentation found in GBATEK:
//! * https://www.problemkaputt.de/gbatek.htm#3dsfilesvideolayoutimagesclimflim 

pub const magic = "CLIM";

pub const Format = enum(u8) {
    i8,
    a8,
    ia44,
    ia88,
    hilo88,
    rgb565,
    bgr888,
    rgba5551,
    rgba4444,
    abgr8888,
    etc1,
    etc1a4,
    i4,
    a4,
    _,

    pub fn native(format: Format) zitrus.hardware.pica.TextureUnitFormat {
        return switch (format) {
            .i8 => .i8,
            .a8 => .a8,
            .ia44 => .ia44,
            .ia88 => .ia88,
            .hilo88 => .hilo88,
            .rgb565 => .rgb565,
            .bgr888 => .bgr888,
            .rgba5551 => .rgba5551,
            .rgba4444 => .rgba4444,
            .abgr8888 => .abgr8888,
            .etc1 => .etc1,
            .etc1a4 => .etc1a4,
            .i4 => .i4,
            .a4 => .a4,
            _ => unreachable,
        };
    }
};

pub const Footer = extern struct {
    /// Offset of the header in the file.
    header_offset: u32,
};

pub const Image = extern struct {
    width: u16,
    height: u16,
    format: Format,
    _unused0: [3]u8 = @splat(0),
};

const std = @import("std");
const zitrus = @import("zitrus");

const hfmt = zitrus.horizon.fmt;
