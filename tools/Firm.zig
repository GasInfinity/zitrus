pub const description = "Make / Show / Dump 3DS firmware files.";

const Subcommand = enum { make, info, dump };

@"-": union(Subcommand) {
    make: Make,
    info: Info,
    dump: Dump,
},

pub fn run(args: Firm, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Firm = @This();
const Make = @import("Firm/Make.zig");
const Info = @import("Firm/Info.zig");
const Dump = @import("Firm/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
