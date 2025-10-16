pub const description = "Dump / Make / Show a RomFS";

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

pub fn main(args: RomFs, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const RomFs = @This();
const Make = @import("RomFs/Make.zig");
const List = @import("RomFs/List.zig");
const Dump = @import("RomFs/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const romfs = zitrus.horizon.fmt.ncch.romfs;
