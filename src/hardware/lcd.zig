//! Definitions for MMIO `LCD` registers.
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsvideolcdregisters

pub const Parallax = extern struct {
    pub const Control = packed struct(u32) {
        pub const Enable = enum(u2) { off, enable, _ };

        tp27_enable: Enable,
        tp27_invert_output: bool,
        _unused0: u13 = 0,
        tp29_enable: Enable,
        tp29_invert_output: bool,
        _unused1: u13 = 0,
    };

    pub const Duty = packed struct(u32) {
        /// (off + 1) * 0.9us
        off: u16,
        /// (on + 1) * 0.9us
        on: u16,
    };

    control: Control,
    /// Controls the TP27 parallax PWM
    duty: Duty,
};

pub const Screen = extern struct {
    pub const Flags = packed struct(u32) {
        abl_enable: bool,
        _unused0: u7 = 0,
        dither_related: BitpackedArray(bool, 2),
        _unused1: u22 = 0,
    };

    pub const Fill = packed struct(u32) {
        r: u8,
        g: u8,
        b: u8,
        enable: bool,
        _unused0: u7 = 0,
    };

    pub const AdaptiveBacklight = extern struct {
        // TODO: lazy
        _todo: [0x5F8]u8,
    };

    flags: Flags,
    fill: Fill,
    adaptive_backlight: AdaptiveBacklight,

    comptime {
        std.debug.assert(@sizeOf(Screen) == 0x600);
    }
};

pub const Clock = packed struct(u32) {
    top_disable: bool = false,
    _unused0: u15 = 0,
    bottom_disable: bool = false,
    _unused1: u15 = 0,
};

pub const Status = packed struct(u32) {
    _: u32 = 0,
};

pub const Reset = enum(u1) { reset, enable };

pub const Registers = extern struct {
    parallax: Parallax,
    status: Status,
    clock: Clock,
    _unknown0: u32,
    reset: LsbRegister(Reset),
    _unused0: [122]u32,
    top: Screen,
    _unused1: [128]u32,
    bottom: Screen,
};

const lcd = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const LsbRegister = hardware.LsbRegister;
const BitpackedArray = hardware.BitpackedArray;
