pub const firm = @import("fmt/firm.zig");

pub const code = @import("fmt/code.zig");
pub const @"3dsx" = @import("fmt/3dsx.zig");

pub const z3ds = @import("fmt/z3ds.zig");
pub const zpsh = @import("fmt/zpsh.zig");
pub const zptx = @import("fmt/zptx.zig");

pub fn fixedArrayFromSlice(comptime T: type, comptime n: usize, slice: []const T) [n]T {
    std.debug.assert(slice.len <= n);
    var buf: [n]T = undefined;
    @memcpy(buf[0..slice.len], slice);
    @memset(buf[slice.len..], std.mem.zeroes(T));
    return buf;
}

comptime {
    _ = firm;

    _ = code;
    _ = @"3dsx";
    _ = z3ds;
    _ = zpsh;
    _ = zptx;
}

const std = @import("std");
