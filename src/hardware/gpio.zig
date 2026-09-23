//! Definitions for MMIO `GPIO` registers.
//!
//! Based on the documentation found in 3dbrew:
//! - https://www.3dbrew.org/wiki/GPIO_Registers

pub const Direction = enum(u1) { input, output };
pub const Edge = enum(u1) { rising, falling };

pub const Pin = enum(u8) {
    pub const Mask = GenericMask(bool, false);
    pub const DirectionMask = GenericMask(Direction, .input);
    pub const EdgeMask = GenericMask(Edge, .rising);

    pub const gpio1: Mask = .init(.{ .debug_pad = true, .touch_pressed = true, .shell_opened = true });
    pub const gpio2: Mask = .init(.{ .headphones_inserted = true, .twl_depop = true });
    pub const gpio2_extra: Mask = .init(.{ .wifi_mode = true });
    pub const gpio3: Mask = .init(.{
        .@"ctr_depop/new_hid" = true,
        .ir = true,
        .gyroscope = true,
        .new_hid_stop = true,
        .ir_tx = true,
        .ir_rx = true,
        .nfc_0 = true,
        .nfc_1 = true,
        .headphones_button = true,
        .mcu = true,
        .nfc_2 = true,
        .qtm = true,
    });
    pub const gpio3_extra: Mask = .init(.{ .wifi_enable = true });
    /// Pins that can be used/configured as outputs (or are only output pins)
    pub const output: Mask = .init(.{
        .headphones_inserted = true,
        .twl_depop = true,
        .wifi_mode = true,
        .@"ctr_depop/new_hid" = true,
        .ir = true,
        .gyroscope = true,
        .new_hid_stop = true,
        .ir_tx = true,
        .ir_rx = true,
        .nfc_0 = true,
        .nfc_1 = true,
        .headphones_button = true,
        .mcu = true,
        .nfc_2 = true,
        .qtm = true,
        .wifi_enable = true,
    });
    /// Pins that can be used/configured as inputs (or are only input pins)
    pub const input: Mask = .init(.{
        .debug_pad = true,
        .touch_pressed = true,
        .shell_opened = true,
        .headphones_inserted = true,
        .twl_depop = true,
        .wifi_mode = true,
        .@"ctr_depop/new_hid" = true,
        .ir = true,
        .gyroscope = true,
        .new_hid_stop = true,
        .ir_tx = true,
        .ir_rx = true,
        .nfc_0 = true,
        .nfc_1 = true,
        .headphones_button = true,
        .mcu = true,
        .nfc_2 = true,
        .qtm = true,
        .wifi_enable = true,
    });
    /// Pins that can be configured
    pub const configurable: Mask = .init(.{
        .headphones_inserted = true,
        .twl_depop = true,
        .@"ctr_depop/new_hid" = true,
        .ir = true,
        .gyroscope = true,
        .new_hid_stop = true,
        .ir_tx = true,
        .ir_rx = true,
        .nfc_0 = true,
        .nfc_1 = true,
        .headphones_button = true,
        .mcu = true,
        .nfc_2 = true,
        .qtm = true,
    });

    // GPIO1
    debug_pad,
    touch_pressed,
    shell_opened,
    // GPIO2
    headphones_inserted,
    twl_depop,
    // GPIO2 extra
    wifi_mode,
    // GPIO3
    @"ctr_depop/new_hid",
    ir,
    gyroscope,
    new_hid_stop,
    ir_tx,
    ir_rx,
    nfc_0,
    nfc_1,
    headphones_button,
    mcu,
    nfc_2,
    qtm,
    // GPIO3 extra
    wifi_enable,

    fn GenericMask(comptime T: type, comptime default: T) type {
        return packed struct(u32) {
            const RemainingInt = @Int(.unsigned, @bitSizeOf(u32) - std.meta.fieldNames(Pin).len);
            const Inner = @Struct(
                .@"packed",
                u32,
                std.meta.fieldNames(Pin) ++ [_][]const u8{"_"},
                &(@as([std.meta.fieldNames(Pin).len]type, @splat(T)) ++ [_]type{RemainingInt}),
                &(@as([std.meta.fieldNames(Pin).len]std.builtin.Type.StructField.Attributes, @splat(.{
                    .default_value_ptr = &default,
                })) ++ [_]std.builtin.Type.StructField.Attributes{.{ .default_value_ptr = &@as(RemainingInt, 0) }}),
            );
            pub const empty: @This() = .init(.{});

            mask: Inner,

            pub fn init(mask: Inner) @This() {
                return .{ .mask = mask };
            }

            pub fn int(mask: @This()) u32 {
                return @bitCast(mask.mask);
            }
        };
    }

    pub fn irq(pin: Pin) ?hardware.cpu.arm11.Interrupt {
        return switch (pin) {
            .touch_pressed => .touch_pressed,
            .shell_opened => .shell_opened,
            .headphones_inserted => .headphones_inserted,
            .twl_depop => .twl_depop,
            .@"ctr_depop/new_hid" => .new_hid,
            .ir => .ir,
            .gyroscope => .gyroscope,
            .new_hid_stop => .new_hid_stop,
            .ir_tx => .ir_tx,
            .ir_rx => .ir_rx,
            .nfc_0 => .nfc_0,
            .nfc_1 => .nfc_1,
            .headphones_button => .headphones_button,
            .mcu => .mcu,
            .nfc_2 => .nfc_2,
            .qtm => .qtm,
            else => null,
        };
    }
};

pub const @"1" = extern struct {
    data: hardware.BitpackedArray(bool, 16),
    _unused0: [14]u8,
};

pub const @"2" = extern struct {
    data: hardware.BitpackedArray(bool, 8),
    direction: hardware.BitpackedArray(Direction, 8),
    irq_config: hardware.BitpackedArray(Edge, 8),
    irq_enable: hardware.BitpackedArray(bool, 8),
    extra: hardware.BitpackedArray(bool, 16),
    _unused0: [10]u8,
};

pub const @"3" = extern struct {
    data: hardware.BitpackedArray(bool, 16),
    direction: hardware.BitpackedArray(Direction, 16),
    irq_config: hardware.BitpackedArray(Edge, 16),
    irq_enable: hardware.BitpackedArray(bool, 16),
    extra: hardware.BitpackedArray(bool, 16),
};

// TODO: old RTC regs are here
pub const Registers = extern struct {
    @"1": @"1",
    @"2": @"2",
    @"3": @"3",
};

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
