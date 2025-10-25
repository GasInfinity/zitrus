//! Different `Horizon`-related formats.

pub const title = @import("fmt/title.zig");

pub const ivfc = @import("fmt/ivfc.zig");
pub const smdh = @import("fmt/smdh.zig");
pub const ncch = @import("fmt/ncch.zig");
pub const dvl = @import("fmt/dvl.zig");

comptime {
    _ = title;

    _ = ivfc;
    _ = smdh;
    _ = ncch;
    _ = dvl;
}
