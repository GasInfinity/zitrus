pub const description = "Make / Dump a (CTR) Layout Animation";

const Subcommand = enum {
    info,
};

@"-": union(Subcommand) {
    info: Info,
},

pub fn run(args: Animation, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Animation = @This();

const Info = @import("Animation/Info.zig");

const std = @import("std");
const zitrus = @import("zitrus");
