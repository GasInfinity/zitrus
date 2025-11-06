//! LZ11 decompressor and (TODO) compressor.
//!
//! LZ-like compression format where the maximum match offset is `4096` and length `65808`.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const magic = 0x11;
pub const history_len = 4096;
pub const max_window_len = 2 * history_len + 65808;

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

pub const Match = packed struct(u8) {
    pub const Length = enum(u4) {
        /// Two bytes follow, length is `(extra << 4 | u8[0] >> 4) + 17` and offset `((u8[0] & 0xF) << 8 | u8[1]) + 1`
        extra = 0,
        /// Three bytes follow, the length is then `(extra << 12 | u8[0] << 4 | u8[1] >> 4) + 273` and offset `((u8[1] & 0xF) << 8 | u8[2]) + 1`
        big_extra = 1,
        /// A single byte follows, length is `len + 1` and offset `(extra << 8 | u8[0]) + 1`
        _,
    };

    extra: u4,
    len: Length,

    pub fn take(in: *Reader) Reader.Error!lz.Match {
        const hdr = try in.takeStruct(Match, .little);
        const len, const offset = switch (hdr.len) {
            .extra => blk: {
                const extra = try in.takeArray(2);
                break :blk .{ ((@as(u9, hdr.extra) << 4) | (extra[0] >> 4)) + 17, ((@as(u13, extra[0] & 0xF) << 8) | extra[1]) + 1 };
            },
            .big_extra => blk: {
                const extra = try in.takeArray(3);
                break :blk .{ ((@as(u17, hdr.extra) << 12) | (@as(u17, extra[0]) << 4) | (extra[1] >> 4)) + 273, ((@as(u13, extra[1] & 0xF) << 8) | extra[2]) + 1 };
            },
            else => .{ @as(u5, @intFromEnum(hdr.len)) + 1, ((@as(u13, hdr.extra) << 8) | try in.takeByte()) + 1 },
        };

        return .{ .offset = offset, .len = len };
    }
};

pub fn blockKind(block: u1) lz.Block {
    return switch (block) {
        0 => .literal,
        1 => .match,
    };
}

pub const Decompress = lz.Decompress(lz11);

// TODO: Tests

const testing = std.testing;

const lz11 = @This();

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");

const zitrus = @import("zitrus");
const lz = zitrus.compress.lz;
