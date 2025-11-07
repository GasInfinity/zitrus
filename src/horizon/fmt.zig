//! Different `Horizon`-related formats.

pub const media_unit = 0x200;

pub const Endian = enum(u16) {
    little = 0xFEFF,
    big = 0xFFFE,
    _,

    pub fn zig(endian: Endian) std.builtin.Endian {
        return switch (endian) {
            .little => .little,
            .big => .big,
            _ => unreachable,
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
