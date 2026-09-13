//! Yaz0 decompressor and (TODO) compressor.
//!
//! LZ-like compression format where the maximum match offset is `4096` and length `273`.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const magic = "Yaz0";
pub const history_len = 4096;
pub const max_window_len = 2 * history_len + Match.max_len;

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
    pub const min_offset = 1;
    pub const max_len = 273;
    pub const max_size = 3;
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

    /// Asserts `writer` capacity is at least `max_size`
    pub fn write(writer: *Writer, match: lz.Match) Writer.Error!void {
        const encoded_offset = match.offset - 1;
        if (match.len > 18) {
            const encoded: Match = .{
                .len = .extra,
                .offset_hi = @intCast(encoded_offset >> 8),
                .offset_lo = @intCast(encoded_offset & 0xFF),
            };

            try writer.writeStruct(encoded, .little);
            try writer.writeByte(@intCast(match.len - 18));
        } else {
            const encoded: Match = .{
                .len = @enumFromInt(match.len - 2),
                .offset_hi = @intCast(encoded_offset >> 8),
                .offset_lo = @intCast(encoded_offset & 0xFF),
            };

            try writer.writeStruct(encoded, .little);
        }
    }
};

pub fn blockKind(block: u1) lz.Block {
    return switch (block) {
        0 => .match,
        1 => .literal,
    };
}

pub fn blockEncoding(block: lz.Block) u1 {
    return switch (block) {
        .match => 0,
        .literal => 1,
    };
}

pub const Compress = lz.Compress(yaz);
pub const Decompress = lz.Decompress(yaz);

comptime {
    _ = Compress;
    _ = Decompress;
}

// TODO: Fuzzing in 0.17 as it is broken in 0.16

const testing = std.testing;

const yaz = @This();

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");

const zitrus = @import("zitrus");
const lz = zitrus.compress.lz;
