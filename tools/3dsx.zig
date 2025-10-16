pub const description = "Make / Dump 3DSX files with/into its Executable, SMDH and RomFS";

const Subcommand = enum { make, dump };

@"-": union(Subcommand) {
    make: Make,
    dump: Dump,
},

pub fn main(args: @"3dsx", arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}

const @"3dsx" = @This();
const Make = @import("3dsx/Make.zig");
const Dump = @import("3dsx/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const smdh = zitrus.horizon.fmt.smdh;
