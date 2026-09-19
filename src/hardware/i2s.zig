//! Definitions for MMIO `I2S` registers (audio).
//!
//! Used for DSP/GBA and CSND output.
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/I2S_Registers

pub const Frequency = enum(u1) { @"32.728498046875Khz", @"47.605088068181818181818Khz" };
pub const Clock = enum(u1) { @"8.3784955Mhz", @"16.756991Mhz" };
pub const Line = enum(u1) {
    /// DSP/GBA
    @"1",
    /// CSND
    @"2",
};

pub const @"1" = packed struct(u16) {
    dsp_volume: u6,
    gba_volume: u6,
    _unk0: u1,
    frequency: Frequency,
    master_clock: Clock,
    enable: bool,
};

pub const @"2" = packed struct(u16) {
    _unused0: u13,
    frequency: Frequency,
    master_clock: Clock,
    enable: bool,
};

pub const Registers = extern struct {
    @"1": @"1",
    @"2": @"2",
};
