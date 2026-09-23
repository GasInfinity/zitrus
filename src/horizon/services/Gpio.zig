//! GPIO services
//!
//! Based on 3dbrew:
//! - https://www.3dbrew.org/wiki/GPIO_Services

pub const Service = enum {
    /// Has access to pins `headphones_inserted` and `ctr_depop/new_hid`
    cdc,
    /// Has access to pins `wifi_mode`, `mcu` and `wifi_enable`
    mcu,
    /// Has access to pins `debug_pad`, `gyroscope`, `new_hid_stop` and `headphones_button`
    hid,
    /// Has access to pins `wifi_mode` and `wifi_enable`
    nwm,
    /// Has access to pins `ctr_depop/new_hid`, `ir`, `new_hid_stop`, `ir_tx` and `ir_rx`
    ir,
    /// Has access to pins `nfc_0`, `nfc_1` and `nfc_2`
    nfc,
    /// Has access to pins `qtm`
    qtm,

    pub fn name(service: Service) [:0]const u8 {
        return switch (service) {
            .cdc => "gpio:CDC",
            .mcu => "gpio:MCU",
            .hid => "gpio:HID",
            .nwm => "gpio:NWM",
            .ir => "gpio:IR",
            .nfc => "gpio:NFC",
            .qtm => "gpio:QTM",
        };
    }
};

pub const Pin = zitrus.hardware.gpio.Pin;

session: horizon.Session.Client,

pub const open = horizon.services.Methods(@This()).openServiceMulti;
pub const openWithResult = horizon.services.Methods(@This()).openServiceMultiWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const GetDirection = ipc.Command(Id, .get_direction, Pin.Mask, Pin.DirectionMask);
    pub const SetDirection = ipc.Command(Id, .set_direction, struct {
        value: Pin.DirectionMask,
        mask: Pin.Mask,

        pub fn init(value: Pin.DirectionMask, mask: Pin.Mask) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const GetInterruptConfiguration = ipc.Command(Id, .get_interrupt_configuration, Pin.Mask, Pin.EdgeMask);
    pub const SetInterruptConfiguration = ipc.Command(Id, .set_interrupt_configuration, struct {
        value: Pin.EdgeMask,
        mask: Pin.Mask,

        pub fn init(value: Pin.EdgeMask, mask: Pin.Mask) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const IsInterruptEnabled = ipc.Command(Id, .is_interrupt_enabled, Pin.Mask, Pin.Mask);
    pub const SetInterruptEnabled = ipc.Command(Id, .set_interrupt_enabled, struct {
        value: Pin.Mask,
        mask: Pin.Mask,

        pub fn init(value: Pin.Mask, mask: Pin.Mask) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const GetData = ipc.Command(Id, .get_data, Pin.Mask, Pin.Mask);
    pub const SetData = ipc.Command(Id, .set_data, struct {
        value: Pin.Mask,
        mask: Pin.Mask,

        pub fn init(value: Pin.Mask, mask: Pin.Mask) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const BindInterrupt = ipc.Command(Id, .bind_interrupt, struct {
        mask: Pin.Mask,
        priority: i32,
        int: horizon.Interruptable,

        pub fn init(mask: Pin.Mask, priority: i32, int: horizon.Interruptable) @This() {
            return .{ .mask = mask, .priority = priority, .int = int };
        }
    }, void);
    pub const UnbindInterrupt = ipc.Command(Id, .unbind_interrupt, struct {
        mask: Pin.Mask,
        int: horizon.Interruptable,

        pub fn init(mask: Pin.Mask, int: horizon.Interruptable) @This() {
            return .{ .mask = mask, .int = int };
        }
    }, void);

    pub const Id = enum(u16) {
        get_direction = 0x0001,
        set_direction,
        get_interrupt_configuration,
        set_interrupt_configuration,
        is_interrupt_enabled,
        set_interrupt_enabled,
        get_data,
        set_data,
        bind_interrupt,
        unbind_interrupt,
    };
};

const Gpio = @This();

const hw = zitrus.hardware.gpio;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;
