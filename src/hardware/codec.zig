//! Definitions for codec registers.
//!
//! All multi-byte values coming from the codec are in BIG endian.
//!
//! A lot of these definitions come from the TSC2117 datasheet.

pub const Coefficient = zsflt.Fixed(.signed, 0, 15);
pub const CircleTouchReport = extern struct {
    touch_x: [5]u16,
    touch_y: [5]u16,
    circle_y: [8]u16,
    circle_x: [8]u16,
};

/// Big endian
/// H(z) = (n_0 + n_1 * z^(-1)) / (2 ^ 15 - d_1 * z^(-1))
pub const Iir = extern struct {
    pub const passthrough: Iir = .{ .n = .{ .ofSaturating(1.0), .ofSaturating(0.0) }, .d = .ofSaturating(0.0) };

    n: [2]Coefficient,
    d: Coefficient,
};

/// Big endian
/// H(z) = (n_0 + 2 * n_1 * z^(-1) + n_2 * z^(-2)) / (2 ^ 15 - 2 * d_1 * z^(-1) - d_2 * z^(-2))
pub const Biquad = extern struct {
    pub const passthrough: Biquad = .{ .n = .{ .ofSaturating(1.0), .ofSaturating(0.0), .ofSaturating(0.0) }, .d = .{ .ofSaturating(0.0), .ofSaturating(0.0) } };

    n: [3]Coefficient,
    d: [2]Coefficient,
};

/// See also `Iir` and `Biquad`
pub const IirBiquad = extern struct {
    pub const passthrough: IirBiquad = .{ .iir = .passthrough, .biquads = @splat(.passthrough) };

    iir: Iir,
    biquads: [5]Biquad,
};

pub const Register = struct {
    pub const dac_ndac: Register = .reg(dac.Divider, 0, 0x0b);

    pub const mic_adc_status: Register = .reg(mic.AnalogToDigitalStatus, 0, 0x24);
    pub const dac_status: Register = .reg(dac.Status, 0, 0x24);
    pub const gpi1_gpi2_control: Register = .reg(pin.ControlGeneral12, 0, 0x39);
    pub const gpi3_control: Register = .reg(pin.ControlGeneral3, 0, 0x3a);

    pub const dac_instruction_set: Register = .reg(dac.InstructionSet, 0, 0x3c);
    pub const dac_setup: Register = .reg(dac.Setup, 0, 0x3f);
    pub const dac_volume_control: Register = .reg(dac.Gain.Control, 0, 0x40);
    pub const dac_left_volume: Register = .reg(dac.Gain, 0, 0x41);
    pub const dac_right_volume: Register = .reg(dac.Gain, 0, 0x42);

    pub const mic_control: Register = .reg(mic.Control, 0, 0x51);
    pub const mic_volume_fine: Register = .reg(mic.Fine.Control, 0, 0x52);
    pub const mic_volume_coarse: Register = .reg(mic.Coarse.Control, 0, 0x53);

    pub const mic_bias: Register = .reg(mic.Bias, 1, 0x2e);
    pub const mic_pga: Register = .reg(mic.ProgrammableGainAmplifier, 1, 0x2f);
    pub const mic_p_input_selection: Register = .reg(mic.AnalogToDigitalInput.P, 1, 0x30);
    pub const mic_m_input_selection: Register = .reg(mic.AnalogToDigitalInput.M, 1, 0x31);

    pub const sar_adc_control: Register = .reg();

    pub const mic_agc_iir: Register = .reg(Iir, 4, 0x02);
    pub const mic_adc_iir: Register = .reg(Iir, 4, 0x08);
    pub const mic_adc_biquad_abcde: Register = .reg([5]Biquad, 4, 0x0e);
    pub const mic_adc_biquad_a: Register = .reg(Biquad, 4, 0x0e);
    pub const mic_adc_biquad_b: Register = .reg(Biquad, 4, 0x18);
    pub const mic_adc_biquad_c: Register = .reg(Biquad, 4, 0x22);
    pub const mic_adc_biquad_d: Register = .reg(Biquad, 4, 0x2c);
    pub const mic_adc_biquad_e: Register = .reg(Biquad, 4, 0x36);

    pub const dac_left_iir: Register = .reg(Iir, 9, 0x02);
    pub const dac_right_iir: Register = .reg(Iir, 9, 0x08);

    pub const dac_left_biquad_a: Register = .reg(Biquad, 8, 0x02);
    pub const dac_left_biquad_bcdef: Register = .reg([5]Biquad, 8, 0x0c);
    pub const dac_left_biquad_b: Register = .reg(Biquad, 8, 0x0c);
    pub const dac_left_biquad_c: Register = .reg(Biquad, 8, 0x16);
    pub const dac_left_biquad_d: Register = .reg(Biquad, 8, 0x20);
    pub const dac_left_biquad_e: Register = .reg(Biquad, 8, 0x2a);
    pub const dac_left_biquad_f: Register = .reg(Biquad, 8, 0x34);
    pub const dac_right_biquad_a: Register = .reg(Biquad, 8, 0x42);
    pub const dac_right_biquad_bcdef: Register = .reg([5]Biquad, 8, 0x4c);
    pub const dac_right_biquad_b: Register = .reg(Biquad, 8, 0x4c);
    pub const dac_right_biquad_c: Register = .reg(Biquad, 8, 0x56);
    pub const dac_right_biquad_d: Register = .reg(Biquad, 8, 0x60);
    pub const dac_right_biquad_e: Register = .reg(Biquad, 8, 0x6a);
    pub const dac_right_biquad_f: Register = .reg(Biquad, 8, 0x74);

    pub const i2s1_left_iir: Register = dac_left_iir;
    pub const i2s1_right_iir: Register = dac_right_iir;

    pub const i2s2_iir: Register = .reg(Iir, 10, 0x02);
    pub const i2s2_biquads: Register = .reg([5]Biquad, 10, 0x0c);

    pub const mic_32khz_iir_biquads: Register = .reg(IirBiquad, 5, 0x08);
    pub const mic_47khz_iir_biquads: Register = .reg(IirBiquad, 5, 0x48);

    pub const headphones_left_32khz_biquads: Register = .reg([3]Biquad, 11, 0x02);
    pub const headphones_right_32khz_biquads: Register = .reg([3]Biquad, 11, 0x42);
    pub const headphones_left_47khz_biquads: Register = .reg([3]Biquad, 11, 0x20);
    pub const headphones_right_47khz_biquads: Register = .reg([3]Biquad, 11, 0x60);
    pub const speakers_left_32khz_biquads: Register = .reg([3]Biquad, 12, 0x02);
    pub const speakers_right_32khz_biquads: Register = .reg([3]Biquad, 12, 0x42);
    pub const speakers_left_47khz_biquads: Register = .reg([3]Biquad, 12, 0x20);
    pub const speakers_right_47khz_biquads: Register = .reg([3]Biquad, 12, 0x60);

    // NOTE: From here all names are not accurate in terms that these are fully undocumented/unknown.
    // May be 99.9% inaccurate but the possible meaning is what matters (they can always be renamed)
    pub const ctr_soft_reset: Register = .reg(bool, 100, 0x01);
    pub const i2s2_dac_status: Register = .reg(dac.Status, 100, 0x25);
    pub const i2s_status: Register = .reg(i2s.Status, 100, 0x26);

    pub const ctr_headset: Register = .reg(Headset, 100, 0x43);

    // Maybe (?)
    pub const i2s2_dac_setup: Register = .reg(dac.Setup, 100, 0x76);
    pub const i2s2_dac_volume_control: Register = .reg(dac.Gain.Control, 100, 0x77);

    pub const i2s2_volume: Register = .reg(i2s.Gain, 100, 0x78);
    pub const i2s1_volume: Register = .reg(i2s.Gain, 100, 0x7a);

    page: u8,
    register: u7,
    type: *const type,

    pub fn reg(comptime T: type, page: u8, register: u8) Register {
        return .{ .page = page, .register = register, .type = &T };
    }
};

pub const SoftStep = enum(u2) {
    per_sample,
    per_two_samples,
    disabled,
    _,
};

pub const Headset = packed struct(u8) {
    /// Times based on 1Mhz reference clock
    pub const DetectionDebounce = enum(u3) {
        @"16ms",
        @"32ms",
        @"64ms",
        @"128ms",
        @"256ms",
        @"512ms",
        _,
    };

    /// Times based on 1Mhz reference clock
    pub const ButtonDebounce = enum(u2) {
        @"0ms",
        @"8ms",
        @"16ms",
        @"32ms",
    };

    pub const Detected = enum(u2) {
        none,
        without_microphone,
        with_microphone = 3,
        _,
    };

    /// Times based on 1Mhz reference clock
    button_debounce: ButtonDebounce = .@"0ms",
    /// Times based on 1Mhz reference clock
    detection_debounce: DetectionDebounce = .@"16ms",
    detected: Detected = .none,
    detection: bool = false,
};

pub const i2s = struct {
    pub const Gain = enum(i8) {
        _,

        /// Range -127 (?dB) to 0? (?dB), other values are not used.
        pub fn gain(value: i8) Gain {
            return @enumFromInt(value);
        }
    };

    pub const Status = packed struct(u8) {
        // Left/Right or Right/Left?
        _unk0: u2 = 0,
        i2s1_right_muted: bool,
        i2s2_right_muted: bool,
        _unk1: u2 = 0,
        i2s1_left_muted: bool,
        i2s2_left_muted: bool,
    };
};

pub const dac = struct {
    pub const InstructionSet = enum(u8) {
        mini_dsp,
        // zig fmt: off
        p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13,
        p14, p15, p16, p17, p18, p19, p20, p21, p22, p23, p24, p25,
        // zig fmt: on
        _,
    };

    pub const Status = packed struct(u8) {
        right_d_driver_powered: bool,
        hpr_driver_powered: bool,
        _reserved0: u1 = 0,
        right_powered: bool,
        left_d_driver_powered: bool,
        hpl_driver_powered: bool,
        _reserved1: u1 = 0,
        left_powered: bool,
    };

    pub const Setup = packed struct(u8) {
        pub const LeftInput = enum(u2) {
            off,
            left,
            right,
            mixed,
        };

        pub const RightInput = enum(u2) {
            off,
            right,
            left,
            mixed,
        };

        volume_soft_stepping: SoftStep = .per_sample,
        right_data_path: RightInput = .right,
        left_data_path: LeftInput = .left,
        right_powered: bool = false,
        left_powered: bool = false,
    };

    pub const Gain = enum(i8) {
        pub const Status = packed struct(u8) {
            right_pga_applied: bool,
            _reserved0: u3 = 0,
            left_pga_applied: bool,
            _reserved1: u3 = 0,
        };

        pub const Control = packed struct(u8) {
            pub const Mode = enum(u2) {
                independent,
                left_uses_right,
                right_uses_left,
                _,
            };

            mode: Mode = .independent,
            right_muted: bool = true,
            left_muted: bool = true,
            _reserved0: u4 = 0,
        };

        _,

        /// Range -127 (-63.5dB) to 48 (24dB), other values are reserved.
        pub fn gain(value: i8) Gain {
            return @enumFromInt(value);
        }
    };

    pub const Divider = packed struct(u8) {
        pub const Divisor = enum(u7) {
            @"128" = 0,
            _,

            pub fn divisor(val: u7) Divisor {
                return @enumFromInt(val);
            }
        };

        divisor: Divisor = .divisor(1),
        powered: bool = false,
    };
};

pub const mic = struct {
    pub const Input = enum(u2) {
        gpio1,
        sclk,
        sdin,
        gpio2,
    };

    pub const AnalogToDigitalStatus = packed struct(u8) {
        _reserved0: u5 = 0,
        agc_saturated: bool = false,
        adc_powered: bool = false,
        adc_pga_applied: bool = false,
    };

    pub const Control = packed struct(u8) {
        soft_stepping: SoftStep = .per_sample,
        _reserved0: u1 = 0,
        digital_delta_sigma_modulation: bool = false,
        digital_input: Input = .gpio1,
        _reserved1: u1 = 0,
        adc_powered: bool = false,
    };

    pub const Fine = enum(u3) {
        @"0dB",
        @"-0.1dB",
        @"-0.2dB",
        @"-0.3dB",
        @"-0.4dB",
        _,

        pub const Control = packed struct(u8) {
            _reserved0: u4 = 0,
            digital_delta_sigma_gain: Fine = .@"0dB",
            /// ADC is muted
            adc_muted: bool = true,
        };
    };

    /// Range -12dB to 20dB, other values are reserved
    pub const Coarse = enum(i7) {
        _,

        pub const Control = packed struct(u8) {
            digital_delta_sigma_gain: Coarse,
            _reserved0: u1 = 0,
        };
    };

    pub const Bias = packed struct(u8) {
        pub const Power = enum(u2) {
            down,
            @"2v",
            @"2.5v",
            /// ~3.3v according to TSC2117
            avdd,
        };

        power: Power = .down,
        _reserved0: u1 = 0,
        always_powered: bool = false,
        _reserved2: u3 = 0,
        software_power_down: bool = false,
    };

    pub const ProgrammableGainAmplifier = packed struct(u8) {
        /// In steps of 0.5dB
        pub const Gain = enum(u7) {
            _,

            pub fn gain(value: u7) Gain {
                return @enumFromInt(value);
            }
        };

        /// Values larger than 119 (59.5dB) are reserved
        gain: Gain = .gain(0),
        /// When `true`, the PGA will behave as if it had a gain of 0dB
        disabled: bool = false,
    };

    pub const AnalogToDigitalInput = enum(u2) {
        pub const P = packed struct(u8) {
            _reserved0: u2 = 0,
            aux2: AnalogToDigitalInput = .unselected,
            aux1: AnalogToDigitalInput = .unselected,
            mic: AnalogToDigitalInput = .unselected,
        };

        pub const M = packed struct(u8) {
            _reserved0: u4 = 0,
            aux2_left: AnalogToDigitalInput = .unselected,
            cm: AnalogToDigitalInput = .unselected,
        };

        unselected,
        @"10kOhm",
        @"20kOhm",
        @"40kOhm",
    };
};

pub const pin = struct {
    pub const General = enum(u2) {
        disabled,
        enabled,
        enabled_general_purpose,
        _,
    };

    pub const General2 = enum(u2) {
        disabled,
        enabled,
        enabled_general_purpose,
        enabled_hp_sp_switch,
    };

    pub const ControlGeneral12 = packed struct(u8) {
        gpi2_value: u1 = 0,
        gpi2: General2 = .disabled,
        _reserved0: u1 = 0,
        gpi1_value: u1 = 0,
        gpi1: General = .disabled,
        _reserved1: u1 = 0,
    };

    pub const ControlGeneral3 = packed struct(u8) {
        _reserved0: u4 = 0,
        gpi3: General = .disabled,
        gpi3_value: u1 = 0,
        _reserved1: u1 = 0,
    };
};

const zsflt = @import("zsflt");
const zitrus = @import("zitrus");
