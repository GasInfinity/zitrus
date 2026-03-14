pub const description = "Make / Dump / Link (send and execute) 3DSX files with/into its Executable, SMDH and RomFS";

const Subcommand = enum { make, dump, link };

@"-": union(Subcommand) {
    make: Make,
    dump: Dump,
    link: Link,
},

pub fn run(args: @"3dsx", io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const @"3dsx" = @This();
const Make = @import("3dsx/Make.zig");
const Dump = @import("3dsx/Dump.zig");
const Link = @import("3dsx/Link.zig");

const std = @import("std");
const zitrus = @import("zitrus");
