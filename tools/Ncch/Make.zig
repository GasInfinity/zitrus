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

const Make = @This();

const Cxi = @import("Make/Cxi.zig");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
