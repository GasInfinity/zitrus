//! Hardware calibration data.
//!
//! Based on documentation found in 3dbrew: https://www.3dbrew.org/wiki/Hardware_calibration

pub const Codec = extern struct {
    pub const Coefficient = hardware.codec.Coefficient;
    pub const Iir = hardware.codec.Iir;
    pub const Biquad = hardware.codec.Biquad;
    pub const IirBiquad = hardware.codec.IirBiquad;

    headphones_gain: u8,
    speakers_gain: u8,
    headphones_analog_volume: u8,
    speakers_analog_volume: u8,
    shutter_volume: [2]i8,
    microphone_bias: u8,
    quick_charge: u8,
    microphone_pga_gain: u8,
    _reserved0: [3]u8  = @splat(0),
    headphones_filter_32: [3]Biquad,
    headphones_filter_47: [3]Biquad,
    speakers_filter_32: [3]Biquad,
    speakers_filter_47: [3]Biquad,
    microphone_filter_32: IirBiquad,
    microphone_filter_47: IirBiquad,
    i2s_filter: IirBiquad,
    analog_interval: u8,
    analog_stabilize: u8,
    analog_precharge: u8,
    analog_sense: u8,
    analog_debounce: u8,
    analog_xp_pullup: u8,
    ym_driver: u8,
    _reserved1: u8 = 0,

    // Taken directly from the codec sysmodule
    pub const default: Codec = .{
        .headphones_gain = 0,
        .speakers_gain = 1,
        .headphones_analog_volume = 0,
        .speakers_analog_volume = 10,
        .shutter_volume = .{ -3, -19 },
        .microphone_bias = 3,
        .quick_charge = 2,
        .microphone_pga_gain = 0,
        .headphones_filter_32 = .{
            .passthrough,
            .passthrough,
            .{ .n = .{ oS(0.9990234375), oS(-0.49951171875), oS(0.0) }, .d = .{ oS(0.4990234375), oS(0.0) } },
        },
        .headphones_filter_47 = .{
            .passthrough,
            .passthrough,
            .{ .n = .{ oS(0.999298095703125), oS(-0.4996337890625), oS(0.0) }, .d = .{ oS(0.499298095703125), oS(0.0) } },
        },
        .speakers_filter_32 = .{
            .{ .n = .{ oS(1.0), oS(-0.840301513671875), oS(0.683990478515625) }, .d = .{ oS(0.94207763671875), oS(-0.887939453125) } },
            .{ .n = .{ oS(-0.42724609375), oS(0.91552734375), oS(-0.42724609375) }, .d = .{ oS(0.0), oS(0.0) } },
            .{ .n = .{ oS(0.9990234375), oS(-0.49951171875), oS(0.0) }, .d = .{ oS(0.4990234375), oS(0.0) } },
        },
        .speakers_filter_47 = .{
            .{ .n = .{ oS(1.0), oS(-0.884857177734375), oS(0.771392822265625) }, .d = .{ oS(0.9599609375), oS(-0.921630859375) } },
            .{ .n = .{ oS(-0.43951416015625), oS(0.91552734375), oS(-0.43951416015625) }, .d = .{ oS(0.0), oS(0.0) } },
            .{ .n = .{ oS(0.999298095703125), oS(-0.4996337890625), oS(0.0) }, .d = .{ oS(0.499298095703125), oS(0.0) } },
        },
        .microphone_filter_32 = .passthrough,
        .microphone_filter_47 = .passthrough,
        .i2s_filter = .{
            .iir = .{
                .n = .{ oS(0.999969482421875), oS(0.0) },
                .d = oS(0.0),
            },
            .biquads = .{
                .{ .n = .{ oS(-0.395477294921875), oS(-0.268096923828125), oS(0.999969482421875) }, .d = .{ oS(0.268096923828125), oS(0.395477294921875) } },
                .{ .n = .{ oS(-0.395477294921875), oS(-0.268096923828125), oS(0.999969482421875) }, .d = .{ oS(0.268096923828125), oS(0.395477294921875) } },
                .{ .n = .{ oS(-0.395477294921875), oS(-0.268096923828125), oS(0.999969482421875) }, .d = .{ oS(0.268096923828125), oS(0.395477294921875) } },
                .{ .n = .{ oS(-0.395477294921875), oS(-0.268096923828125), oS(0.999969482421875) }, .d = .{ oS(0.268096923828125), oS(0.395477294921875) } },
                .{ .n = .{ oS(0.0), oS(0.0), oS(0.0) }, .d = .{ oS(0.999969482421875), oS(0.0) } },
            },
        },
        .analog_interval = 1,
        .analog_stabilize = 9,
        .analog_precharge = 4,
        .analog_sense = 3,
        .analog_debounce = 0,
        .analog_xp_pullup = 6,
        .ym_driver = 1,
    };

    const oS = Coefficient.ofSaturating;
};

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
