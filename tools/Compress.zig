pub const description = "Compress / Decompress 3DS-related formats";

const Subcommand = enum {
    lzrev,
    yaz,
    lz10,
    lz11,
};

@"-": union(Subcommand) {
    lzrev: LzRev,
    yaz: Yaz,
    lz10: Lz10,
    lz11: Lz11,
},

pub fn main(args: Compress, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Compress = @This();
const LzRev = @import("Compress/LzRev.zig");
const Yaz = @import("Compress/Yaz.zig");
const Lz10 = @import("Compress/Lz10.zig");
const Lz11 = @import("Compress/Lz11.zig");

const std = @import("std");
const zitrus = @import("zitrus");
