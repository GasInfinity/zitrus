pub const description = "Make/Dump PICA200-native textures";

const Subcommand = enum { make, dump };

@"-": union(enum) {
    make: Make,
    dump: Dump,
},

pub fn run(args: Disassemble, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |fmt| fmt.run(io, arena),
    };
}

const Disassemble = @This();

const Make = @import("Texture/Make.zig");
const Dump = @import("Texture/Dump.zig");

const std = @import("std");
