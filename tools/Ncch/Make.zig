pub const description = "Make a NCCH CXI/CFA (TODO)";

const Format = enum {
    cxi,
    // cfa,
};

@"-": union(Format) {
    cxi: Cxi,
},

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

comptime {
    _ = Settings;
}

const Make = @This();

const Cxi = @import("Make/Cxi.zig");

const Settings = @import("Settings.zig");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;
const code = zitrus.fmt.code;
