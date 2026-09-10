//! Definitions for MMIO `MIC` (MICrophone) registers.
//!
//! Based on the documentation found in 3dbrew & GBATEK:
//!   - https://www.3dbrew.org/wiki/MIC_Registers 
//!   - https://problemkaputt.de/gbatek.htm#3dssoundandmicrophone

pub const SampleRate = enum(u2) {
    /// 32.73 KHz / 47.61 KHz
    @"1/1",
    /// 16.36 KHz / 23.81 KHz
    @"1/2",
    /// 10.91 KHz / 15.87 KHz
    @"1/3",
    /// 8.18 KHz / 11.90 KHz
    @"1/4",
};

pub const Format = enum(u2) {
    stereo,
    mono = 2,
    _,
};

pub const Interrupt = enum(u2) {
    none,
    full = 2,
    half_full,
    _,
};

pub const Control = packed struct(u16) {
    format: Format, 
    sample_rate: SampleRate,
    _unused0: u4,
    fifo_empty: bool,
    fifo_half_full: bool,
    fifo_full: bool,
    fifo_overrun: bool,
    clear_fifo: bool,
    irq: Interrupt,
    enable: bool,
};

pub const Registers = extern struct {
    control: Control,
    _unused0: [2]u8,
    fifo: [2]i16,
};
