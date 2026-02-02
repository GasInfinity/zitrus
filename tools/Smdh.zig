pub const description = "Make / Dump SMDH files with its settings and icon files.";

const Subcommand = enum { make, dump };

@"-": union(Subcommand) {
    make: Make,
    dump: Dump,
},

pub fn run(args: Smdh, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Make = @import("Smdh/Make.zig");
const Dump = @import("Smdh/Dump.zig");

const Smdh = @This();

const std = @import("std");
const zitrus = @import("zitrus");
