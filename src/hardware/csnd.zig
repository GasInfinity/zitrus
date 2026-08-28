//! Definitions for MMIO `CSND` registers.
//!
//! Based on the documentation found in GBATEK and 3dbrew:
//! - https://problemkaputt.de/gbatek.htm#3dssoundandmicrophone
//! - https://www.3dbrew.org/wiki/CSND_Registers

pub const channels = 32;
pub const captures = 2;

pub const Volume = enum(u16) {
    pub const min: Volume = .volume(0);
    pub const max: Volume = .volume(0x8000);

    _,

    pub fn volume(value: u16) Volume {
        return @enumFromInt(@min(value, 0x8000));
    }
};

pub const SampleRate = enum(u16) {
    pub const min: SampleRate = .rate(0);
    pub const max: SampleRate = .rate(0xFFBE);

    _,

    pub fn rate(value: u16) SampleRate {
        return @enumFromInt(@as(u32, 67_027_964) / value);
    }

    pub fn raw(value: u16) SampleRate {
        std.debug.assert(value <= 0xFFBE);
        return @enumFromInt(value);
    }
};

pub const Master = extern struct {
    pub const Control = packed struct(u32) {
        volume: Volume,
        mute: bool,
        _unused0: u13,
        dissonant_disable: bool,
        /// When this is not true, some registers won't be written.
        read_write: bool,
    };

    control: Control,
    _unused0: [3]u32,
    // CSND writes the process acquired channel mask (0xFFFFFF00 always) here on cmd 0x200
    // CSND reads two times on cmd 0x300; ANDs it with acquired channels and captures and writes both at `acquired_state_offset`
    unk_channels: u32,
    // CSND writes the process acquired capture mask (depends) here on cmd 0x200
    unk_capture_units: u8,
    _unused1: [3]u8,
};

pub const Channel = extern struct {
    pub const WaveDuty = enum(u3) {
        pub const @"12.5": WaveDuty = .duty(0);
        pub const @"25.0": WaveDuty = .duty(1);
        pub const @"37.5": WaveDuty = .duty(2);
        pub const @"50.0": WaveDuty = .duty(3);
        pub const @"62.5": WaveDuty = .duty(4);
        pub const @"75.0": WaveDuty = .duty(5);
        pub const @"87.5": WaveDuty = .duty(6);
        pub const @"0.0": WaveDuty = .duty(7);
        _,

        pub fn duty(value: u3) WaveDuty {
            return @enumFromInt(value);
        }
    };
    pub const Format = enum(u2) { pcm8, pcm16, ima_adpcm, psg };
    pub const Repeat = enum(u2) { manual, loop, one_shot, loop_constant };

    pub const Control = packed struct(u32) {
        wave_duty: WaveDuty,
        _unused0: u3 = 0,
        linearly_interpolate: bool,
        hold_last: bool,
        _unused1: u2 = 0,
        repeat: Repeat,
        format: Format,
        // Supposedly no effect on PSG?
        pause_disable: bool,
        busy: bool,
        sample_rate: SampleRate,
    };

    pub const ImaAdPcm = packed struct(u32) {
        value: i16,
        index_value: u7,
        _unused0: u8,
        reload_second_buffer_state: bool,
    };

    pub const Volume = packed struct(u32) {
        left: csnd.Volume,
        right: csnd.Volume,

        pub fn init(volume: u15, pan: i16) Channel.Volume {
            return .{
                .left = @enumFromInt(std.math.clamp(@as(i32, volume) - @max(0, pan), 0, @intFromEnum(csnd.Volume.max))),
                .right = @enumFromInt(std.math.clamp(@as(i32, volume) + @min(pan, 0), 0, @intFromEnum(csnd.Volume.max))),
            };
        }
    };

    /// 0x00
    control: Control,
    /// 0x04
    output_volume: Channel.Volume,
    /// 0x08
    capture_volume: Channel.Volume,
    /// 0x0C
    start_address: PhysicalAddress,
    /// 0x10
    size: hardware.LsbRegister(u27),
    // So you can start with some sound and then loop with another? If true cool.
    /// 0x14
    restart_address: PhysicalAddress,
    /// 0x18
    start_ima_state: ImaAdPcm,
    /// 0x1C
    restart_ima_state: ImaAdPcm,
};

pub const Capture = extern struct {
    pub const Format = enum(u1) { pcm16, pcm8 };

    pub const Control = packed struct(u32) {
        one_shot: bool,
        format: Format,
        _unknown0: u1,
        _unused0: u12 = 0,
        busy: bool,
        _unused1: u16 = 0,
    };

    control: Control,
    sample_rate: LsbRegister(SampleRate),
    size: LsbRegister(u24),
    address: PhysicalAddress,
};

pub const Registers = extern struct {
    master: Master,
    _unused0: [0x3e8]u8,
    /// PSG Support:
    /// - Square on channels 8-13
    /// - Noise on channels 14-15
    channels: [channels]Channel,
    captures: [captures]Capture,
};

comptime {
    _ = Registers;
}

const csnd = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const LsbRegister = hardware.LsbRegister;
const MsbRegister = hardware.MsbRegister;

const PhysicalAddress = hardware.PhysicalAddress;
