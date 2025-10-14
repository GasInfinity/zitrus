pub const description = "Dump / Make NCCH (CXI/CFA) files";

const Subcommand = enum {
    dump,
};

@"-": union(Subcommand) {
    dump: Dump,
},

pub fn main(args: Ncch, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |s| s.main(arena),
    };
}

const Dump = @import("Ncch/Dump.zig");

const Ncch = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;
