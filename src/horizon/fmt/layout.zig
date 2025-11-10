pub const clim = @import("layout/clim.zig");
pub const clyt = @import("layout/clyt.zig");
pub const clan  = @import("layout/clan.zig");

pub const Header = extern struct {
    magic: [4]u8,
    endian: hfmt.Endian,
    header_size: u16 = @sizeOf(Header),
    version: u32,
    file_size: u32,
    blocks: u32,

    pub const CheckError = error{ NotHeader, InvalidHeaderSize };
    pub fn check(hdr: Header, magic: *const [4]u8) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotHeader;
        if (hdr.header_size < @sizeOf(Header)) return error.InvalidHeaderSize;
    }
};

/// Blocks specific to each format live in their respective namespace, not here!
pub const block = extern struct {
    /// Should be read always as little endian
    pub const Kind = enum(u32) {
        layout = @bitCast(@as([4]u8, "lyt1".*)),
        textures = @bitCast(@as([4]u8, "txl1".*)),
        fonts = @bitCast(@as([4]u8, "fnl1".*)),
        materials = @bitCast(@as([4]u8, "mat1".*)),
        pane = @bitCast(@as([4]u8, "pan1".*)),
        // pane_children_start = @bitCast(@as([4]u8, "pas1".*)),
        // pane_children_end = @bitCast(@as([4]u8, "pae1".*)),
        picture = @bitCast(@as([4]u8, "pic1".*)),
        // window = @bitCast(@as([4]u8, "wnd1".*)),
        // bounding = @bitCast(@as([4]u8, "bnd1".*)),
        // text = @bitCast(@as([4]u8, "txt1".*)),
        group = @bitCast(@as([4]u8, "grp1".*)),
        // group_children_start = @bitCast(@as([4]u8, "grs1".*)),
        // group_children_end = @bitCast(@as([4]u8, "gre1".*)),
        // user_data = @bitCast(@as([4]u8, "usd1".*)),
        image = @bitCast(@as([4]u8, "imag".*)),
        // pattern = @bitCast(@as([4]u8, "pat1".*)),
        // pattern_instruction = @bitCast(@as([4]u8, "pai1".*)),
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
