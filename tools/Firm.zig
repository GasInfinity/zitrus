pub const description = "Dump / Make / Show 3DS firmware files.";

const Subcommand = enum { info };

@"-": union(Subcommand) {
    info: Info,
},

pub fn main(args: Firm, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const Firm = @This();
const Info = @import("Firm/Info.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const firm = zitrus.fmt.firm;
