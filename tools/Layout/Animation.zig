pub const description = "Make / Dump a (CTR) Layout Animation";

const Subcommand = enum {
    info,
};

@"-": union(Subcommand) {
    info: Info,
},

pub fn main(args: Animation, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Animation = @This();

const Info = @import("Animation/Info.zig");

const std = @import("std");
const zitrus = @import("zitrus");
