pub const description = "Make / Dump a (CTR) Layout Image";

const Subcommand = enum {
    dump,
};

@"-": union(Subcommand) {
    dump: Dump,
},

pub fn run(args: Image, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Image = @This();

const Dump = @import("Image/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
