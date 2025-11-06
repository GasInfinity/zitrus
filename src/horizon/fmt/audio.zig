//! Encompasses both **C**TR **WAV**es and **C**TR **ST**rea**M**s
//!
//! Based on the documentation found in 3dbrew:
//! * https://www.3dbrew.org/wiki/BCWAV
//! * https://www.3dbrew.org/wiki/BCSTM

pub const Header = extern struct {
    magic: [4]u8,
    endian: hfmt.Endian,
    header_size: u16,
    version: u32,
    size: u32,
    blocks: u16,
    _reserved0: u16 = 0,
};

pub const Reference = extern struct {
    pub const Sized = extern struct {
        reference: Reference,
        size: u32,
    };

    pub const Type = enum(u16) { _ };
    pub const Offset = enum(u32) {
        null = 0xFFFFFFFF,
        _,

        pub inline fn offset(value: u32) Offset {
            return @enumFromInt(value);
        }
    };

    type: Type,
    _padding0: u16 = 0,
    offset: Offset,
};

pub const block = struct {
    pub const Header = extern struct {
        magic: [4]u8,
        size: u32,
    };
};

const zitrus = @import("zitrus");
const hfmt = zitrus.horizon.fmt;
