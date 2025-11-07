pub const clim = @import("layout/clim.zig");
pub const clyt = @import("layout/clyt.zig");

pub const Header = extern struct {
    magic: [4]u8,
    endian: hfmt.Endian,
    size: u16 = @sizeOf(Header),
    version: u32,
    file_size: u32,
    blocks: u32,

    pub const CheckError = error{ NotHeader, InvalidHeaderSize };
    pub fn check(hdr: Header, magic: *const [4]u8) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotHeader;
        if (hdr.size < @sizeOf(Header)) return error.InvalidHeaderSize;
    }
};

pub const block = extern struct {
    /// Should be read always as little endian
    pub const Kind = enum(u32) {
        meta = @bitCast(@as([4]u8, "imag".*)),
        _,
    };

    pub const Header = extern struct {
        kind: Kind,
        size: u32,
    };
};

comptime {
    _ = clim;
    _ = clyt;
}

const std = @import("std");
const zitrus = @import("zitrus");

const hfmt = zitrus.horizon.fmt;
