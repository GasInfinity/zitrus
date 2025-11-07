//! LZ10 decompressor and (TODO) compressor.
//!
//! LZ-like compression format where the maximum match offset is `4096` and length `18`.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const magic = 0x10;
pub const history_len = 4096;
pub const max_window_len = 2 * history_len + 18;

pub const Header = packed struct(u32) {
    magic: u8 = magic,
    uncompressed_len: u24,

    pub const CheckError = error{NotLz10};
    pub fn check(hdr: Header) CheckError!void {
        if (hdr.magic != magic) return error.NotLz10;
    }

    pub fn take(in: *Reader) Reader.Error!Header {
        return try in.takeStruct(Header, .little);
    }
};

pub const Match = packed struct(u16) {
    /// The real value is `(offset_hi << 8) | offset_lo + 1`
    offset_hi: u4,
    /// The real value is `len + 3`
    len: u4,
    /// The real value is `(offset_hi << 8) | offset_lo + 1`
    offset_lo: u8,

    pub fn take(in: *Reader) Reader.Error!lz.Match {
        const hdr = try in.takeStruct(Match, .little);
        const offset = (@as(u13, hdr.offset_hi) << 8 | hdr.offset_lo) + 1;
        const len = @as(u5, hdr.len) + 3;

        return .{ .offset = offset, .len = len };
    }
};

pub fn blockKind(block: u1) lz.Block {
    return switch (block) {
        0 => .literal,
        1 => .match,
    };
}

pub const Decompress = lz.Decompress(lz10);

// TODO: Tests

const testing = std.testing;

const lz10 = @This();

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");

const zitrus = @import("zitrus");
const lz = zitrus.compress.lz;
