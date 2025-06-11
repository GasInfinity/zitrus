pub const pica = @import("pica.zig");

pub const smdh = @import("smdh.zig");
pub const ncch = @import("ncch.zig");
pub const @"3dsx" = @import("3dsx.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
