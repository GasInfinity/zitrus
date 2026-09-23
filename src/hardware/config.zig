//! Based on the documentation found in GBATEK & 3dbrew:
//! - https://www.3dbrew.org/wiki/CONFIG11_Registers
//! - https://www.3dbrew.org/wiki/CONFIG9_Registers
//! - https://problemkaputt.de/gbatek.htm#3dsconfigconfig9registers
//! - https://problemkaputt.de/gbatek.htm#3dsconfigconfig11registers

pub const @"9" = extern struct {
    pub const Cpu = extern struct {
        pub const Protection = extern struct {
            pub const Arm9 = packed struct(u8) {
                disable_bootrom: bool,
                disable_otp: bool,
                _unused0: u6 = 0,
            };

            pub const Arm11 = packed struct(u8) {
                disable_bootrom: bool,
                _unused0: u7 = 0,
            };

            arm9: Arm9,
            arm11: Arm11,
        };

        protection: Protection,
    };

    pub const ResetArm11 = enum(u8) {
        running,
        reset,
        _,
    };

    pub const Debug = extern struct {
        _unknown0: u32 = 0,
    };

    pub const Card = extern struct {
        pub const Controller = enum(u2) { ntr, ctr0 = 2, ctr1 };
        pub const SpiMode = enum(u1) { fifo, manual };
        pub const SpiController = enum(u1) { ntr, spi };

        pub const Control = packed struct(u16) {
            active: Controller,
            _unused0: u2 = 0,
            spi_card_mode: SpiMode,
            _unused1: u3 = 0,
            spi_controller: SpiController,
            _unused2: u3 = 0,
            _unknown0: u1 = 0,
            _unused3: u3 = 0,
        };

        pub const Power = packed struct(u16) {
            pub const State = enum(u2) { off, reset, on, off_requested };

            ejected: bool,
            _unused0: u1 = 0,
            state: State,
            _unused1: u14 = 0,
        };
        pub const Delay = extern struct {
            pub const Unit = enum(u16) { _ };

            insert: Unit,
            power_off: Unit,
        };
    };

    pub const UnitInfo = extern struct {
        ctr: u8,
        _unused0: [3]u8 = @splat(0),
        twl: u8,
        _unused1: [3]u8 = @splat(0),
    };

    pub const BootEnvironment = enum(u32) {
        cold = 0,
        ctr = 0b1,
        twl = 0b11,
        gba = 0b111,
        _,
    };
};

pub const @"11" = extern struct {
    pub const Shared = extern struct {
        pub const Master = enum(u2) { arm9, arm11, dsp };
        pub const Mapping = packed struct(u8) {
            master: Master,
            offset: u3,
            _unused0: u2 = 0,
            enable: bool,
        };

        code: [8]Mapping,
        data: [8]Mapping,
    };

    pub const NullPage = packed struct(u32) {
        enable_trap: bool,
        _unused0: u15 = 0,
        trapped: bool,
        _unused1: u15 = 0,
    };

    // NOTE: This is unknown
    pub const FastInterrupt = packed struct(u8) {
        cpu: hardware.BitpackedArray(bool, 4),
        _unused0: u4 = 0,
    };

    // NOTE: This is unknown
    pub const Debug = packed struct(u8) {
        cpu: hardware.BitpackedArray(bool, 4),
        _unused0: u4 = 0,
    };

    pub const Cdma = packed struct(u16) {
        mic: bool,
        ntrcard: bool,
        _unused0: u2 = 0,
        wifi: bool,
        _unk0: bool = false,
        _unused1: u10 = 0,
    };

    pub const GpuProtection = packed struct(u32) {
        pub const Cutoff = enum(u4) { disabled, _ };
        pub const SmallCutoff = enum(u2) { disabled, _ };

        /// 0x28000000-(0x800000*x); first 0x800000 cannot be protected.
        first_fcram_half: Cutoff,
        /// 0x30000000-(0x800000*x); when `first_fcram_half_cutoff` is not `disabled`, the first 0x800000 are protected.
        second_fcram_half: Cutoff,
        axiwram: bool,
        /// 0x1F400000-(0x100000*x); first 0x100000 cannot be protected.
        qtm_dma_size: SmallCutoff,
        _unused0: u21 = 0,
    };

    pub const Wifi = packed struct(u8) {
        enable: bool,
        _unused0: u7 = 0,
    };

    pub const Spi = packed struct(u16) {
        new_bus_enabled: hardware.BitpackedArray(bool, 3),
        _unused0: u13 = 0,
    };

    pub const New = extern struct {
        pub const Gpu = packed struct(u8) {
            enable: bool,
            texture_fix: bool,
            _unused0: u6 = 0,
        };

        pub const CdmaPeripherals = packed struct(u32) {
            new: hardware.BitpackedArray(bool, 18),
            _unused0: u14 = 0,
        };

        pub const Bootrom = extern struct {
            enable: bool,
            _pad0: [3]u8,
            value: u32,
        };

        gpu: Gpu,
        _unused0: [15]u8,
        cdma: CdmaPeripherals,
        _unused1: [12]u8,
        bootrom: Bootrom,
        _unk0: u32,
        _unused2: [4]u8,
    };

    pub const SocInfo = packed struct(u16) {
        /// O3DS
        ctr: bool,
        /// N3DS Prototype
        lgr1: bool,
        /// N3DS
        lgr2: bool,
        _unused0: u13 = 0,
    };

    shared: Shared,
    _unused0: [0xf0]u8,
    null_page: NullPage,
    fiq: FastInterrupt,
    debug: Debug,
    _unused1: [6]u8,
    cdma: Cdma,
    _unused2: [0x32]u8,
    gpu_protection: GpuProtection,
    _unused3: [0x3c]u8,
    wifi: Wifi,
    _unused4: [0x3f]u8,
    spi: Spi,
    _unused5: [0x3e]u8,
    _unk0: u32,
    _unused6: [0x1fc]u8,
    new: New,
    _unused7: [0xbcc]u8,
    soc_info: SocInfo,

    comptime {
        std.debug.assert(@offsetOf(@"11", "debug") == 0x105);
        std.debug.assert(@offsetOf(@"11", "gpu_protection") == 0x140);
        std.debug.assert(@offsetOf(@"11", "wifi") == 0x180);
        std.debug.assert(@offsetOf(@"11", "new") == 0x400);
        std.debug.assert(@offsetOf(@"11", "soc_info") == 0xffc);
    }
};

comptime {
    _ = @"9";
    _ = @"11";
}

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
