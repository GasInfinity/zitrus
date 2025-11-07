pub const description = "Make / Dump a (CTR) Layout Image";

const Subcommand = enum {
    dump,
};

@"-": union(Subcommand) {
    dump: Dump,
},

pub fn main(args: Image, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Image = @This();

const Dump = @import("Image/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const layout = zitrus.horizon.fmt.layout;
