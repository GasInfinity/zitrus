//! Definitions for MMIO `LGY` registers.
//!
//! Used for **L**e**g**ac**y** framebuffer conversion, NDS/GBA -> 3DS.
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsvideolgyregisterslegacygbandsvideotoframebuffer

pub const Framebuffer = extern struct {
    pub const Format = enum(u2) { abgr8888, bgr888, rgb5551, rgb565 };
    pub const Rotate = enum(u2) { none, @"90", @"180", @"270" };

    pub const Control = packed struct(u32) {
        start: bool,
        enable_vertical_scaling: bool,
        enable_horizontal_scaling: bool,
        _unused0: u1 = 0,
        brightness_dither_enable: bool,
        _brigness_dither_enable_too: bool,
        _unused1: u2 = 0,
        format: Format,
        /// Clockwise rotation
        rotate: Rotate,
        swizzle: bool,
        _unused2: u2 = 0,
        dma: bool,
        _unused3: u16 = 0,
    };

    pub const Dimensions = packed struct(u32) {
        width_minus_one: u9,
        _unused0: u7,
        height_minus_one: u9,
        _unused1: u7,

        pub fn init(width: u9, height: u9) Dimensions {
            return .{ .width_minus_one = width - 1, .height_minus_one = height - 1 };
        }
    };

    pub const InterruptStatus = packed struct(u32) {
        first_block: bool,
        next_block: bool,
        last_line: bool,
        _unused0: u13 = 0,
        current_block_line: u8,
        _unused1: u8 = 0,
    };

    pub const InterruptEnable = packed struct(u32) {
        first_block: bool,
        next_block: bool,
        last_line: bool,
        _unused0: u29 = 0,
    };

    pub const Scaling = extern struct {
        /// Scale according `length` output pixels.
        ///
        /// `bits` tell which input pixels get used, effectively making it `length` / `bits`
        pub const Pattern = extern struct {
            pub const @"1x": Pattern = .init(1, .splat(1));
            pub const @"1.16x": Pattern = .init(7, .init(.{ 1, 1, 0, 1, 1, 0, 1, 0 }));
            pub const @"1.2x": Pattern = .init(6, .init(.{ 1, 1, 1, 0, 1, 1, 0, 0 }));
            pub const @"1.25x": Pattern = .init(5, .init(.{ 1, 1, 0, 1, 1, 0, 0, 0 }));
            pub const @"1.33x": Pattern = .init(4, .init(.{ 1, 1, 1, 0, 0, 0, 0, 0 }));
            pub const @"1.4x": Pattern = .init(7, .init(.{ 1, 1, 1, 1, 1, 0, 0, 0 }));
            pub const @"1.5x": Pattern = .init(3, .init(.{ 1, 1, 0, 0, 0, 0, 0, 0 }));
            pub const @"1.66x": Pattern = .init(5, .init(.{ 1, 1, 1, 0, 1, 0, 0, 0 }));
            pub const @"1.75x": Pattern = .init(7, .init(.{ 1, 0, 1, 0, 1, 0, 1, 0 }));
            pub const @"2x": Pattern = .init(2, .init(.{ 1, 0, 0, 0, 0, 0, 0, 0 }));
            pub const @"2.33x": Pattern = .init(7, .init(.{ 1, 0, 0, 1, 0, 0, 1, 0 }));
            pub const @"2.5x": Pattern = .init(5, .init(.{ 1, 0, 1, 0, 0, 0, 0, 0 }));
            pub const @"2.66x": Pattern = .init(8, .init(.{ 1, 0, 0, 1, 0, 0, 0, 1 }));
            pub const @"3x": Pattern = .init(3, .init(.{ 1, 0, 0, 0, 0, 0, 0, 0 }));
            pub const @"3.5x": Pattern = .init(7, .init(.{ 1, 0, 0, 1, 0, 0, 0, 0 }));

            length: LsbRegister(u3),
            bits: LsbRegister(BitpackedArray(u1, 8)),

            pub fn init(length: u3, bits: BitpackedArray(u1, 8)) Pattern {
                return .{ .length = length, .bits = bits };
            }
        };

        pub const Brightness = enum(u16) { _ };

        pattern: Pattern,
        _unused0: [0x38]u8,
        brightness: [6][8]LsbRegister(Brightness),

        comptime {
            std.debug.assert(@sizeOf(Scaling) == 0x100);
        }
    };

    control: Control,
    size: Dimensions,
    irq_status: InterruptStatus,
    irq_enable: InterruptEnable,
    _unused0: [0x10]u8,
    alpha: LsbRegister(u8),
    _unused1: [0xCC]u8,
    prefetch: LsbRegister(u4),
    _unused2: [0x0C]u8,
    dither: [4]u64,
    _unused3: [0xE0]u8,
    vertical_scaling: Scaling,
    horizontal_scaling: Scaling,

    comptime {
        std.debug.assert(@sizeOf(Framebuffer) == 0x400);
    }
};

pub const Config = extern struct {
    bottom: Framebuffer,
    _unused0: [0xC00]u8,
    top: Framebuffer,
};

pub const Fifo = extern struct {
    bottom: [0x1000]u8,
    top: [0x1000]u8,
};

comptime {
    _ = Config;
    _ = Fifo;
}

const lgy = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const LsbRegister = hardware.LsbRegister;
const BitpackedArray = hardware.BitpackedArray;
