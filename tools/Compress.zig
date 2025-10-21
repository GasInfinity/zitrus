pub const description = "Compress / Decompress 3DS-related formats";

const Subcommand = enum {
    lzrev,
};

@"-": union(Subcommand) {
    lzrev: LzRev,
},

pub fn main(args: Compress, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Compress = @This();
const LzRev = @import("Compress/LzRev.zig");

const std = @import("std");
const zitrus = @import("zitrus");
