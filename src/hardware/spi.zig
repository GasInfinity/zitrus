//! Definitions for MMIO `SPI` registers.
//!
//! Based on the documentation found in 3dbrew & GBATEK:
//!  - https://www.3dbrew.org/wiki/SPI_Registers#SPI_CNT
//!  - https://www.problemkaputt.de/gbatek-3ds-spi-registers.htm

pub const Device = enum(u2) {
    @"0",
    @"1",
    @"2",
    @"3",

    pub fn device(dev: u2) Device {
        return @enumFromInt(dev);
    }
};

pub const Bus = extern struct {
    pub const Rate = enum(u3) {
        @"4Mhz",
        @"2Mhz",
        @"1Mhz",
        @"512Khz",
        @"8Mhz",
        _,
    };

    pub const Control = packed struct(u16) {
        rate: Rate,
        _unk0: u4 = 0,
        busy: bool = false,
        select: Device,
        /// Supposedly bugged
        @"16bit": bool = false,
        hold_selected: bool = false,
        _unused0: u2 = 0,
        irq_enable: bool = false,
        enable: bool = false,
    };

    pub const Data = extern union {
        u8: u8,
        u16: u16,
    };

    control: Control,
    /// A transfer is started after writing to this register, even when reading
    data: Data,
};

pub const NewBus = extern struct {
    pub const Rate = enum(u3) {
        @"512Khz",
        @"1Mhz",
        @"2Mhz",
        @"4Mhz",
        @"8Mhz",
        @"16Mhz",
        _,
    };

    pub const Direction = enum(u1) { read, write };

    pub const Control = packed struct(u16) {
        rate: Rate,
        _unused0: u3 = 0,
        select: Device,
        _unused1: u4 = 0,
        @"4bit": bool = false,
        direction: Direction,
        _unused2: u1 = 0,
        busy: bool = false,
    };

    pub const AutoPoll = packed struct(u32) {
        command: u8,
        _unused0: u8 = 0,
        timeout: u4,
        _unused1: u4 = 0,
        poll_offset: u3,
        _unused2: u3 = 0,
        poll_set: bool,
        busy: bool,
    };

    pub const Interrupt = packed struct(u32) {
        finished: bool,
        auto_poll_success: bool,
        auto_poll_timeout: bool,
        _: u29 = 0,
    };

    control: LsbRegister(Control),
    selected: LsbRegister(bool),
    len: LsbRegister(u21),
    fifo: u32,
    /// Looks like that when reading, this is true if the FIFO is empty.
    /// Otherwise this is true when it is full.
    fifo_status: LsbRegister(bool),
    auto_poll: AutoPoll,
    irq_disable_mask: Interrupt,
    irq_status: Interrupt,
};

pub const Registers = extern struct {
    /// 0x000
    bus: Bus,
    _unused0: [0x7fc]u8,
    /// 0x800
    new_bus: NewBus,

    comptime {
        std.debug.assert(@offsetOf(Registers, "bus") == 0x000);
        std.debug.assert(@offsetOf(Registers, "new_bus") == 0x800);
    }
};

comptime {
    _ = Registers;
    _ = Bus;
    _ = NewBus;
}

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const LsbRegister = hardware.LsbRegister;
