//! Different `Horizon`-related formats.

pub const media_unit = 0x200;

pub const Endian = extern struct {
    pub const little: Endian = .{ .bom = .{ 0xFF, 0xFE } };
    pub const big: Endian = .{ .bom = .{ 0xFE, 0xFF } };

    bom: [2]u8,
};

/// Provided to allow using UTF-8 strings in some contexts where it could be allowed (by encoding it to UTF-16)
pub const AnyUtf = union(enum(u1)) {
    as_utf8: []const u8,
    as_utf16: []const u16,

    pub fn utf8(value: []const u8) AnyUtf {
        return .{ .as_utf8 = value };
    }

    pub fn utf16(value: []const u16) AnyUtf {
        return .{ .as_utf16 = value };
    }

    /// Calculates UTF-16 length of the name.
    ///
    /// Asserts the name is a valid utf8 or utf16 string.
    pub fn length(any: AnyUtf) usize {
        return switch (any) {
            .as_utf8 => |as_utf8| std.unicode.calcUtf16LeLen(as_utf8) catch unreachable,
            .as_utf16 => |as_utf16| as_utf16.len,
        };
    }

    /// Asserts the name is a valid utf8 or utf16 string and that the encoded string fits in the output.
    pub fn encode(any: AnyUtf, buf: []u16) usize {
        return switch (any) {
            .as_utf8 => |as_utf8| std.unicode.utf8ToUtf16Le(buf, as_utf8) catch unreachable,
            .as_utf16 => |as_utf16| blk: {
                @memcpy(buf[0..as_utf16.len], as_utf16);
                break :blk as_utf16.len;
            },
        };
    }
};

pub const title = @import("fmt/title.zig");

pub const ivfc = @import("fmt/ivfc.zig");
/// Deprecated: use `ncch.smdh` instead.
pub const smdh = ncch.smdh;
pub const ncsd = @import("fmt/ncsd.zig");
pub const ncch = @import("fmt/ncch.zig");
pub const dvl = @import("fmt/dvl.zig");

pub const archive = @import("fmt/archive.zig");
pub const layout = @import("fmt/layout.zig");
pub const audio = @import("fmt/audio.zig");
pub const cro0 = @import("fmt/cro0.zig");

comptime {
    _ = title;

    _ = ivfc;
    _ = smdh;
    _ = ncch;
    _ = dvl;

    _ = archive;
    _ = layout;
    _ = audio;
    _ = cro0;
}

const std = @import("std");
