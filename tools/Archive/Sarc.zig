pub const description = "Make / Info / Dump a SARC archive";

const Subcommand = enum {
    info,
    dump,
};

@"-": union(Subcommand) {
    info: Info,
    dump: Dump,
},

pub fn run(args: Sarc, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Sarc = @This();

const Info = @import("Sarc/Info.zig");
const Dump = @import("Sarc/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
