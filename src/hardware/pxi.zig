//! Definitions for MMIO `PXI` registers. **P**rocessorE**X**change**I**nterface (?)
//!
//! Used for communication between the ARM11 and ARM9 cores in the 3DS.
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek.htm#3dsmiscregisters

pub const Pipe = extern struct {
    pub const Synchronization = extern struct {
        pub const Interrupt = packed struct(u8) {
            _unused0: u4,
            /// Sets bit 12 of IF in the ARM9
            send_arm9: bool,
            /// Triggers IRQ 0x50 and 0x51 in the ARM11
            send_arm11: BitpackedArray(bool, 2),
            enable_remote_irq: bool,
        };

        received: u8,
        /// Write-only, reads as 0
        sent: u8,
        _unused0: u8,
        irq: Interrupt,
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

    sync: Synchronization,
    control: Control,
    send: u32,
    receive: u32,
};

pub const Registers = extern struct {
    arm9: Pipe,
    arm11: Pipe,
};

const pxi = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const BitpackedArray = hardware.BitpackedArray;
