pub const description = "Make / List / Dump an ExeFS";

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

pub fn main(args: ExeFs, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const ExeFs = @This();
const Make = @import("ExeFs/Make.zig");
const List = @import("ExeFs/List.zig");
const Dump = @import("ExeFs/Dump.zig");

const std = @import("std");
