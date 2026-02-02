pub const description = "Make / Show / Dump 3DS layout files.";

const Subcommand = enum {
    info,
    image,
};

@"-": union(Subcommand) {
    info: Info,
    image: Image,
},

pub fn run(args: Layout, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Layout = @This();
const Info = @import("Layout/Info.zig");
const Image = @import("Layout/Image.zig");

const std = @import("std");
const zitrus = @import("zitrus");
