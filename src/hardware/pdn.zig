//! Definitions for MMIO `PDN` (PowerDowN? Power Distribution Network?) registers.
//!
//! Mainly used for enabling clocks and powering down/up devices.
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/PDN_Registers

pub const Sleep = extern struct {
    pub const Control = packed struct(u16) {
        enter: bool,
        _unused0: u14 = 0,
        vram_self_refresh: bool,
    };

    pub const Wake = packed struct(u32) {
        _unused0: u1 = 0,
        hid: bool,
        _unused1: u1 = 0,
        shell_opened: bool,
        headphones_unplugged: bool,
        _unused2: u3 = 0,
        /// (?)
        wifi: bool,
        _unused3: u10 = 0,
        /// (?)
        shell_gpio: bool,
        _unused4: u6 = 0,
        mcu_irq: bool,
        _unused5: u3 = 0,
        touch_screen_pressed: bool,
        gamecard_status_changed: bool,
    };

    control: Control,
    _unused0: [6]u8,
    wake_enable: Wake,
    wake_reason: Wake,
};

pub const Legacy = extern struct {
    /// TODO
    _: [0x21]u8,
};

pub const Clock = extern struct {
    pub const Gpu = packed struct(u32) {
        main: bool,
        psc: bool,
        geometry_shader: bool,
        rasterization: bool,
        ppf: bool,
        /// (?)
        pdc: bool,
        pdc_related: bool,
        _unused0: u9 = 0,
        all: bool,
        _unused1: u15 = 0,
    };

    pub const Enable = packed struct(u8) {
        enable: bool,
        _: u7 = 0,
    };

    pub const ResetLow = packed struct(u8) {
        reset: hardware.ResetLow,
        _: u7 = 0,
    };

    pub const FcRam = packed struct(u16) {
        reset: bool,
        enable: bool,
        ack_enable: bool,
        _: u13 = 0,
    };

    pub const I2s = packed struct(u8) {
        i2s1: bool,
        i2s2: bool,
        _: u6 = 0,
    };

    pub const Dsp = packed struct(u8) {
        reset: hardware.ResetLow,
        enable: bool,
        _: u6 = 0,
    };

    /// 0x00
    gpu: Gpu,
    /// 0x04
    vram: Enable,
    _unused0: [3]u8,
    /// 0x08
    lcd: Enable,
    _unused1: [7]u8,
    /// 0x10
    fcram: FcRam,
    _unused2: [14]u8,
    /// 0x20
    i2s: I2s,
    _unused3: [3]u8,
    /// 0x24
    camera: Enable,
    _unused4: [11]u8,
    /// 0x30
    dsp: Dsp,
    _unused5: [15]u8,
    /// 0x40
    mvd: ResetLow,
    _unused6: [3]u8,

    comptime {
        std.debug.assert(@offsetOf(Clock, "fcram") == 0x10);
        std.debug.assert(@offsetOf(Clock, "camera") == 0x24);
        std.debug.assert(@offsetOf(Clock, "dsp") == 0x30);
        std.debug.assert(@offsetOf(Clock, "mvd") == 0x40);
    }
};

pub const Lgr = extern struct {
    pub const Soc = packed struct(u16) {
        pub const Mode = enum(u3) {
            /// 2@256MHz
            ctr,
            /// 4@256Mhz, L2C
            lgr2_256Mhz,
            /// (2 or 4)@256Mhz, No L2C
            lgr1_256Mhz,
            /// (2 or 4)@536Mhz, No L2C
            lgr1_536Mhz,
            /// 4@804Mhz, L2C
            lgr2_804Mhz = 5,
            _,
        };

        mode: Mode,
        _: u12,
        irq: bool,
    };

    pub const Control = packed struct(u16) {
        enable_extra_memory: bool,
        _unused0: u7 = 0,
        enable_l2c: bool,
        _unused1: u7 = 0,
    };

    pub const Cpu = packed struct(u8) {
        power_request: bool,
        handshake: bool,
        _unused0: u2 = 0,
        powered: bool,
        present: bool,
        _unused1: u2 = 0,
    };

    soc: Soc,
    control: Control,
    _unused0: [8]u8,
    cpu: [4]Cpu,
};

pub const Registers = extern struct {
    sleep: Sleep,
    _unused0: [0xf0]u8,
    legacy: Legacy,
    _unused1: [0xdc]u8,
    clock: Clock,
    _unused2: [0xbc]u8,
    lgr: Lgr,

    comptime {
        std.debug.assert(@offsetOf(Registers, "sleep") == 0x000);
        std.debug.assert(@offsetOf(Registers, "legacy") == 0x100);
        std.debug.assert(@offsetOf(Registers, "clock") == 0x200);
        std.debug.assert(@offsetOf(Registers, "lgr") == 0x300);
    }
};

comptime {
    _ = Sleep;
    _ = Legacy;
    _ = Clock;
    _ = Lgr;
    _ = Registers;
}

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
