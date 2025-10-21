//! Definitions for MMIO `HID` registers.
//!
//! Used for numerous things.
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsi2cregisters

pub const Direction = enum(u1) { write, read };

pub const Control = packed struct(u8) {
    stop: bool,
    start: bool,
    pause: bool,
    _unknown0: u1 = 0,
    ack: bool,
    direction: Direction,
    irq_enable: bool,
    busy: bool,
};

pub const ControlExtended = packed struct(u16) {
    clock: bool,
    wait_if_clock_low: bool,
    _unused0: u13 = 0,
    _unknown1: u1 = 0,
};

pub const Speed = enum(u6) {
    _,
};

pub const Bus = extern struct {
    pub const Clock = packed struct(u16) {
        low: Speed,
        _unused0: u2 = 0,
        high: Speed,
        _unused1: u2 = 0,
    };

    data: u8,
    control: Control,
    control_extended: ControlExtended,
    clock: Clock,
};
