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

        pub fn int(wake: Wake) u32 {
            return @bitCast(wake);
        }
    };

    /// 0x00
    control: Control,
    _unused0: [6]u8,
    /// 0x08
    wake_enable: Wake,
    /// 0x0C
    wake_reason: Wake,

    comptime {
        std.debug.assert(@offsetOf(Sleep, "wake_enable") == 0x08);
        std.debug.assert(@offsetOf(Sleep, "wake_reason") == 0x0C);
    }
};

pub const Legacy = extern struct {
    pub const Mode = packed struct(u16) {
        legacy_mode: u2,
        _unused: u13 = 0,
        enable: bool,
    };

    pub const Sleep = packed struct(u16) {
        wake_gpa: bool,
        sleep_ack: bool,
        _unk0: u1,
        _unused0: u12 = 0,
        irq_enable: bool,
    };

    pub const Pad = packed struct(u16) {
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
        _unk0: bool,
        _unused0: u3 = 0,
    };

    pub const Gpio = packed struct(u16) {
        debug: bool,
        touch_released: bool,
        hinge: bool,
        _unused0: u4 = 0,
        headphones_connected: bool,
        power_button: bool,
        sound_enable: bool,
        _unused1: u6 = 0,
    };

    pub const Card = packed struct(u8) {
        ejected: bool,
        _unused0: u7 = 0,
    };

    /// 0x00
    mode: Mode,
    _unused0: [2]u8,
    /// 0x04
    sleep: Legacy.Sleep,
    _unused1: [2]u8,
    /// 0x08
    irq_enable: u16,
    /// 0x0A
    pad: u16,
    _unused2: [4]u8,
    /// 0x010
    emulated_pad_mask: Legacy.Pad,
    /// 0x012
    emulated_pad: Legacy.Pad,
    /// 0x014
    emulated_gpio_mask: Legacy.Gpio,
    /// 0x016
    emulated_gpio: Legacy.Gpio,
    /// 0x018
    emulated_card_mask: Legacy.Card,
    /// 0x019
    emulated_card: Legacy.Card,
    _unused3: [6]u8,
    /// 0x020
    _unk0: u8,

    comptime {
        std.debug.assert(@offsetOf(Legacy, "pad") == 0x0A);
        std.debug.assert(@offsetOf(Legacy, "emulated_pad_mask") == 0x10);
        std.debug.assert(@offsetOf(Legacy, "_unk0") == 0x20);
    }
};

pub const Clock = extern struct {
    pub const Gpu = packed struct(u32) {
        main: hardware.ResetLow,
        psc: hardware.ResetLow,
        geometry_shader: hardware.ResetLow,
        rasterization: hardware.ResetLow,
        ppf: hardware.ResetLow,
        /// (?)
        pdc: hardware.ResetLow,
        pdc_related: hardware.ResetLow,
        _unused0: u9 = 0,
        enable: bool,
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

    /// ARM11 holds reset for 0x0C cycles.
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
    /// ARM11 holds reset for 0x30 cycles.
    /// 0x30
    dsp: Dsp,
    _unused5: [15]u8,
    /// 0x40
    mvd: ResetLow,
    _unused6: [3]u8,

    comptime {
        std.debug.assert(@offsetOf(Clock, "gpu") == 0x00);
        std.debug.assert(@offsetOf(Clock, "vram") == 0x04);
        std.debug.assert(@offsetOf(Clock, "lcd") == 0x08);
        std.debug.assert(@offsetOf(Clock, "fcram") == 0x10);
        std.debug.assert(@offsetOf(Clock, "i2s") == 0x20);
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
    /// 0x000
    sleep: Sleep,
    _unused0: [0xf0]u8,
    /// 0x100
    legacy: Legacy,
    _unused1: [0xdc]u8,
    /// 0x200
    clock: Clock,
    _unused2: [0xbc]u8,
    /// 0x300
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
