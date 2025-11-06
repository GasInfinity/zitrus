pub const description = "Make / List / Dump a DARC archive";

const Subcommand = enum {
    ls,
};

@"-": union(Subcommand) {
    ls: List,
},

pub fn main(args: Darc, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Darc = @This();

const List = @import("Darc/List.zig");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
