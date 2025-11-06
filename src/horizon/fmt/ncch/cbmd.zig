//! Stored in the NCCH ExeFS. Represents banner data (model and sound).
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/CBMD

pub const magic = "CBMD";

pub const Language = enum(u8) {
    en,
    fr,
    de,
    it,
    sp,
    du,
    pt,
    ru,
    jp,
    en_us,
    fr_us,
    sp_us,
    pt_us,
};

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    _unused0: u32 = 0,
    cgfx_offset: u32,
    region_cgfx_offset: [13]u32,
    _unused1: [0x44]u8 = 0,
    cwav_offset: u32,
};
