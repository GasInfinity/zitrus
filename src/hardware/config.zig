//! Based on the documentation found in GBATEK: 
//! - https://problemkaputt.de/gbatek.htm#3dsconfigconfig9registers
//! - https://problemkaputt.de/gbatek.htm#3dsconfigconfig11registers

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

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
