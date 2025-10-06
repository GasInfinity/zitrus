//! Definitions for MMIO `HID` registers.
//!
//! Used only for main PAD buttons (Cicle Pad + New3DS buttons not included)
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsmiscregisters

pub const State = packed struct(u16) {
    a: bool,
    b: bool,
    select: bool,
    start: bool,
    right: bool,
    left: bool,
    up: bool,
    down: bool,
    r: bool,
    l: bool,
    x: bool,
    y: bool,
    _unused0: u3 = 0,
};

pub const Interrupt = packed struct(u16) {
    pub const Condition = enum(u1) { @"or", @"and" };

    pub const Source = packed struct(u12) {
        a: bool,
        b: bool,
        select: bool,
        start: bool,
        right: bool,
        left: bool,
        up: bool,
        down: bool,
        r: bool,
        l: bool,
        x: bool,
        y: bool,
    };

    source: Source,
    _unused0: u2 = 0,
    enable: bool,
    condition: Condition,
};

pub const Registers = extern struct {
    released: State,
    irq: Interrupt,
};

const hid = @This();

const zitrus = @import("zitrus");
