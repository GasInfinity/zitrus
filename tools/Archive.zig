pub const description = "Make / List / Dump different archive formats.";

const Subcommand = enum { darc, sarc };

@"-": union(Subcommand) {
    darc: Darc,
    sarc: Sarc,
},

pub fn main(args: Archive, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Archive = @This();
const Darc = @import("Archive/Darc.zig");
const Sarc = @import("Archive/Sarc.zig");

const std = @import("std");
const zitrus = @import("zitrus");
