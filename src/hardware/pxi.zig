//! Definitions for MMIO `PXI` registers. **P**rocessorE**X**change**I**nterface (?)
//!
//! Used for communication between the ARM11 and ARM9 cores in the 3DS.
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsmiscregisters

pub const sync = struct {
    pub const Arm11 = extern struct {
        pub const Interrupt = packed struct(u8) {
            _unused0: u6 = 0,
            send_irq: bool,
            enable_remote_irq: bool,
        };

        received: u8,
        /// Write-only, reads as 0
        send: u8,
        _unused0: u8,
        irq: Interrupt,
    };

    pub const Arm9 = extern struct {
        pub const Interrupt = packed struct(u8) {
            _unused0: u5 = 0,
            /// Triggers IRQ 0x50 and 0x51 in the ARM11
            /// Sets bit 12 of IF in the ARM9
            send_irq: BitpackedArray(bool, 2),
            enable_remote_irq: bool,
        };

        received: u8,
        /// Write-only, reads as 0
        send: u8,
        _unused0: u8,
        irq: Interrupt,
    };
};

pub const Control = packed struct(u16) {
    send_empty: bool,
    send_full: bool,
    send_empty_irq_enable: bool,
    send_flush: bool,
    _unused0: u4,
    receive_empty: bool,
    receive_full: bool,
    receive_not_empty_irq_enable: bool,
    _unused1: u3,
    @"error": bool,
    enable: bool,
};

pub const @"9" = extern struct {
    sync: sync.Arm9,
    control: Control,
    _unused0: [2]u8,
    send: u32,
    receive: u32,
};

pub const @"11" = extern struct {
    sync: sync.Arm11,
    control: Control,
    _unused0: [2]u8,
    send: u32,
    receive: u32,
};

const pxi = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const BitpackedArray = hardware.BitpackedArray;
