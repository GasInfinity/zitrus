// https://www.3dbrew.org/wiki/NCCH
pub const magic = "NCCH";

// TODO: Docs, Docs and Docs
pub const Header = extern struct {
    pub const Flags = packed struct(u64) {};

    signature: [0x100]u8,
    magic: [4]u8 = magic.*,
    content_size: u32,
    partition_id: u64,
    maker_code: u16,
    version: u16,
    hash: [4]u8,
    program_id: u64,
    _reserved0: [0x10]u8 = @splat(0),
    logo_region_hash: [0x20]u8,
    product_code: [0x10]u8,
    extended_header_hash: [0x20]u8,
    extended_header_size: u32,
    _reserved1: [4]u8 = 0,
    flags: Flags,
    plain_region_offset: u32,
    plain_region_size: u32,
    logo_region_offset: u32,
    logo_region_size: u32,
    exefs_offset: u32,
    exefs_size: u32,
    exefs_hash_region_size: u32,
    _reserved2: [4]u8,
    romfs_offset: u32,
    romfs_size: u32,
    romfs_hash_region_size: u32,
    _reserved3: [4]u8,
    exefs_superblock_hash: [0x20]u8,
    romfs_superblock_hash: [0x20]u8,
};
