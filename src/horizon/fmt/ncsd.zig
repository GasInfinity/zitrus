pub const magic = "NCSD";
pub const max_partitions = 8;

pub const Partition = extern struct {
    pub const Type = enum(u8) {
        none,
        normal,
        firm,
        agb_save,
        _,
    };

    pub const Crypto = enum(u8) {
        _,
    };

    /// In media units
    offset: u32,
    /// In media units
    size: u32,
};

pub const Header = extern struct {
    pub const Partitions = extern struct {
        type: [max_partitions]Partition.Type,
        crypto: [max_partitions]Partition.Crypto,
        table: [max_partitions]Partition,
    };

    signature: [0x100]u8,
    magic: [magic.len]u8 = magic.*,
    size: u32,
    id: u64,
    partitions: Partitions,
};

pub const Nand = extern struct {
    _unknown0: [0x5E]u8 = @splat(0),
    encrypted_mbr: [0x42]u8,
};

pub const Card = extern struct {
    pub const Device = enum(u8) { nor = 1, none, bt, _ };
    pub const Platform = enum(u8) { ctr = 1, _ };
    pub const Type = enum(u8) { inner, @"1", @"2", extended, _ };

    pub const Flags = extern struct {
        backup_write_wait_time: u8,
        _unused0: [2]u8 = @splat(0),
        device: Device,
        platform: Platform,
        type: Type,
        extra_unit_exponent: u8,
        old_device: Device,
    };

    pub const InfoHeader = extern struct {
        writable_address: u32,
        mask: u32,
        _reserved0: [0xF8]u8 = @splat(0),
        filled_size: u32,
        _reserved1: [0xC]u8 = @splat(0),
        title_version: u16,
        card_revision: u16,
        _reserved2: [0xC]u8 = @splat(0),
        update_title_id: hfmt.title.Id,
        update_version: u16,
        _reserved3: [0xCD6]u8 = @splat(0),
    };

    pub const InitialData = extern struct {
        seed: [0x10]u8,
        key: [0x10]u8,
        mac: [0x10]u8,
        nonce: [0x10]u8,
        _reserved0: [0xC4]u8 = @splat(0),
        ncch: hfmt.ncch.Header,
    };

    extended_header_hash: [0x20]u8,
    additional_header_size: u32,
    sector_zero_offset: u32,
    flags: Flags,
    partition_id: [max_partitions]u64,
    _reserved0: [0x20]u8 = @splat(0),
    _reserved1: [0xE]u8 = @splat(0),
    _unknown0: u8,
    crypto: u8,
};

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const hfmt = horizon.fmt;
