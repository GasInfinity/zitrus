//! GPIO services
//!
//! Based on 3dbrew:
//! - https://www.3dbrew.org/wiki/GPIO_Services

pub const Service = enum {
    cdc,
    mcu,
    hid,
    nwm,
    ir,
    nfc,
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

pub const Interrupt = packed struct(u32) {
    _unused0: u1 = 0,
    touch_pressed: bool = false,
    shell_opened: bool = false,
    headphones_inserted: bool = false,
    twl_depop: bool = false,
    _unused1: u1 = 0,
    c_stick: bool = false,
    ir: bool = false,
    gyroscope: bool = false,
    c_stick_stop: bool = false,
    ir_tx: bool = false,
    ir_rx: bool = false,
    nfc_0: bool = false,
    nfc_1: bool = false,
    headphones_half_inserted: bool = false,
    mcu: bool = false,
    nfc_2: bool = false,
    qtm: bool = false,
    _unused3: u14 = 0,
};

session: horizon.Session.Client,

pub const open = horizon.services.Methods(@This()).openServiceMulti;
pub const openWithResult = horizon.services.Methods(@This()).openServiceMultiWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const GetRegPart1 = ipc.Command(Id, .get_reg_part1, u32, u32);
    pub const SetRegPart1 = ipc.Command(Id, .set_reg_part1, struct {
        value: u32,
        mask: u32,

        pub fn init(value: u32, mask: u32) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const GetRegPart2 = ipc.Command(Id, .get_reg_part2, u32, u32);
    pub const SetRegPart2 = ipc.Command(Id, .set_reg_part2, struct {
        value: u32,
        mask: u32,

        pub fn init(value: u32, mask: u32) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const GetInterruptMask = ipc.Command(Id, .get_interrupt_mask, u32, u32);
    pub const SetInterruptMask = ipc.Command(Id, .set_interrupt_mask, struct {
        value: u32,
        mask: u32,

        pub fn init(value: u32, mask: u32) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const GetData= ipc.Command(Id, .get_data, u32, u32);
    pub const SetData = ipc.Command(Id, .set_data, struct {
        value: u32,
        mask: u32,

        pub fn init(value: u32, mask: u32) @This() {
            return .{ .value = value, .mask = mask };
        }
    }, void);
    pub const BindInterrupt = ipc.Command(Id, .bind_interrupt, struct {
        mask: Interrupt,
        priority: i32,
        int: horizon.Interruptable,

        pub fn init(mask: Interrupt, priority: i32, int: horizon.Interruptable) @This() {
            return .{ .mask = mask, .priority = priority, .int = int };
        }
    }, void);
    pub const UnbindInterrupt = ipc.Command(Id, .unbind_interrupt, struct {
        mask: Interrupt,
        int: horizon.Interruptable,

        pub fn init(mask: Interrupt, int: horizon.Interruptable) @This() {
            return .{ .mask = mask, .int = int };
        }
    }, void);

    pub const Id = enum(u16) {
        get_reg_part1 = 0x0001,
        set_reg_part1,
        get_reg_part2,
        set_reg_part2,
        get_interrupt_mask,
        set_interrupt_mask,
        get_data,
        set_data,
        bind_interrupt,
        unbind_interrupt,
    };
};

const I2s = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;
