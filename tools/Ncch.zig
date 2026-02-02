pub const description = "Make / Dump NCCH (CXI/CFA) files";

const Subcommand = enum {
    dump,
    make,
};

@"-": union(Subcommand) {
    dump: Dump,
    make: Make,
},

pub fn run(args: Ncch, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |s| s.run(io, arena),
    };
}

const Dump = @import("Ncch/Dump.zig");
const Make = @import("Ncch/Make.zig");

const Ncch = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;
