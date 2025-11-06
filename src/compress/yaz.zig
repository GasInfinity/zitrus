//! Yaz0 decompressor and (TODO) compressor.
//!
//! LZ-like compression format where the maximum match offset is `4096` and length `273`.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const magic = "Yaz0";
pub const history_len = 4096;
pub const max_window_len = 2 * history_len + 273;

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    /// Stored as big endian
    uncompressed_len: u32,
    _reserved0: [8]u8 = @splat(0),

    pub const CheckError = error{NotYaz};
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotYaz;
    }

    pub fn take(in: *Reader) Reader.Error!Header {
        return try in.takeStruct(Header, .big);
    }
};

pub const Match = packed struct(u16) {
    pub const Length = enum(u4) { extra = 0, _ };

    /// The real value is `(offset_hi << 8) | offset_lo + 1`
    offset_hi: u4,
    /// If `extra` a byte follows and is `extra + 18`
    /// else is `len + 2`
    len: Length,
    /// The real value is `(offset_hi << 8) | offset_lo + 1`
    offset_lo: u8,

    pub fn take(in: *Reader) Reader.Error!lz.Match {
        const hdr = try in.takeStruct(Match, .little);
        const offset = (@as(u13, hdr.offset_hi) << 8 | hdr.offset_lo) + 1;
        const len = switch (hdr.len) {
            .extra => @as(u9, try in.takeByte()) + 18,
            else => @as(u8, @intFromEnum(hdr.len)) + 2,
        };

        return .{ .offset = offset, .len = len };
    }
};

pub fn blockKind(block: u1) lz.Block {
    return switch (block) {
        0 => .match,
        1 => .literal,
    };
}

pub const Decompress = lz.Decompress(yaz);

// TODO: Tests

const testing = std.testing;

const yaz = @This();

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");

const zitrus = @import("zitrus");
const lz = zitrus.compress.lz;
