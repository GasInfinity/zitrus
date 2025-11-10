pub const description = "Make / List / Dump a DARC archive";

const Subcommand = enum {
    make,
    ls,
    dump,
};

@"-": union(Subcommand) {
    make: Make,
    ls: List,
    dump: Dump,
},

pub fn main(args: Darc, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Darc = @This();

const Make = @import("Darc/Make.zig");
const List = @import("Darc/List.zig");
const Dump = @import("Darc/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
