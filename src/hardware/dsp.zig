//! Definitions for MMIO `DSP` registers.
//!
//! Used for **D**igital **S**ignal **P**rocessing, a.k.a: sound.
//! Its an independent processor named *TeakLite II* from XpertTeak.
//!
//!
//! Based on the documentation found in GBATEK and 3dbrew:
//! - https://problemkaputt.de/gbatek.htm#3dssoundandmicrophone

pub const Address = enum(u16) {
    _,

    pub fn init(address: u16) Address {
        return @enumFromInt(address);
    }
};

pub const Configuration = packed struct(u16) {
    pub const Region = enum(u2) { data, mmio, code, ahbm };
    pub const Length = enum(u2) { @"1", @"8", @"16", free };

    reset: bool,
    auto_increment_transfer_address: bool,
    read_length: Length,
    read_start: bool,
    irq_read_fifo_full: bool,
    irq_read_fifo_not_empty: bool,
    irq_write_fifo_full: bool,
    irq_write_fifo_empty: bool,
    irq_reply_register: BitpackedArray(bool, 3),
    transfer_region: Region,
};

pub const Status = packed struct(u16) {
    reading: bool,
    writing: bool,
    resetting: bool,
    _unused0: u2,
    read_fifo_full: bool,
    read_fifo_not_empty: bool,
    write_fifo_full: bool,
    write_fifo_empty: bool,
    semaphore_irq: bool,
    reply_register_unwritten: BitpackedArray(bool, 3),
    command_register_unread: BitpackedArray(bool, 3),
};

pub const Semaphore = extern struct {
    send: BitpackedArray(bool, 16),
    _unused0: [2]u8,
    irq_disable: BitpackedArray(bool, 16),
    _unused1: [2]u8,
    send_clear: BitpackedArray(bool, 16),
    _unused2: [2]u8,
    receive: BitpackedArray(bool, 16),
    _unused3: [2]u8,
};

pub const Registers = extern struct {
    fifo: u16,
    _unused0: [2]u8,
    transfer_address: Address,
    _unused1: [2]u8,
    config: Configuration,
    _unused2: [2]u8,
    status: Status,
    _unused3: [2]u8,
    semaphore: Semaphore,
    command0: u16,
    _unused4: [2]u8,
    reply0: u16,
    _unused5: [2]u8,
    command1: u16,
    _unused6: [2]u8,
    reply1: u16,
    _unused7: [2]u8,
    command2: u16,
    _unused8: [2]u8,
    reply2: u16,
    _unused9: [2]u8,
};

const dsp = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const BitpackedArray = hardware.BitpackedArray;
