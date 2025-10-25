pub const description = "Make / Show / Dump 3DS firmware files.";

const Subcommand = enum { make, info, dump };

@"-": union(Subcommand) {
    make: Make,
    info: Info,
    dump: Dump,
},

pub fn main(args: Firm, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Firm = @This();
const Make = @import("Firm/Make.zig");
const Info = @import("Firm/Info.zig");
const Dump = @import("Firm/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const firm = zitrus.fmt.firm;
