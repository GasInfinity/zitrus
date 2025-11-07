pub const description = "Make / Show / Dump 3DS layout-related files.";

const Subcommand = enum {
    image,
};

@"-": union(Subcommand) {
    image: Image,
},

pub fn main(args: Layout, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Layout = @This();
const Image = @import("Layout/Image.zig");

const std = @import("std");
const zitrus = @import("zitrus");
