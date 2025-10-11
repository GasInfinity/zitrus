//! Definitions for MMIO `CSND` registers.
//!
//! Based on the documentation found in GBATEK and 3dbrew:
//! - https://problemkaputt.de/gbatek.htm#3dssoundandmicrophone
//! - https://www.3dbrew.org/wiki/CSND_Registers

pub const Volume = enum(u16) {
    pub const min: Volume = .volume(0);
    pub const max: Volume = .volume(0);

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
        std.debug.assert(value <= 0xFFBE);
        return @enumFromInt(value);
    }
};

pub const MasterControl = packed struct(u32) {
    volume: Volume,
    mute: bool,
    _unused0: u13,
    dissonant_disable: bool,
    /// When this is not true, some registers won't be written.
    read_write: bool,
};

pub const Channel = extern struct {
    pub const WaveDuty = enum(u3) { _ };
    pub const Format = enum(u2) { pcm8, pcm16, ima_adpcm, psg };
    pub const Repeat = enum(u2) { manual, loop, one_shot, loop_constant };

    pub const Control = packed struct(u32) {
        wave_duty: WaveDuty,
        _unused0: u2 = 0,
        interpolate_linearly: bool,
        hold_last: bool,
        _unused1: u2 = 0,
        repeat: Repeat,
        format: Format,
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
        right: csnd.Volume,
        left: csnd.Volume,
    };

    control: Control,
    output_volume: Channel.Volume,
    capture_volume: Channel.Volume,
    start_address: PhysicalAddress,
    total_size: hardware.LsbRegister(u27),
    // So you can start with some sound and then loop with another? If true cool.
    // XXX: 3dbrew says this is the other channel? When this is 0x0 then mono audio is played. Name is not accurate
    loop_restart_address: PhysicalAddress,
    start_ima_state: ImaAdPcm,
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
    length: LsbRegister(u24),
    address: PhysicalAddress,
};

pub const Registers = extern struct {
    master: MasterControl,
    _unused0: [0x3FC]u8,
    channels: [32]Channel,
    captures: [2]Capture,
};

const csnd = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const LsbRegister = hardware.LsbRegister;
const MsbRegister = hardware.MsbRegister;

const PhysicalAddress = hardware.PhysicalAddress;
