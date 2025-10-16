pub const description = "Compress / Decompress 3DS-related formats";

const Subcommand = enum {
    lzrev,
};

@"-": union(Subcommand) {
    lzrev: LzRev,
},

pub fn main(args: ExeFs, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}


const ExeFs = @This();
const LzRev = @import("Compress/LzRev.zig");

const std = @import("std");
const zitrus = @import("zitrus");
