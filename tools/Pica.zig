pub const description = "Assemble / Dissassemble zitrus PICA200 shader assembly";

const Subcommand = enum { @"asm", disasm };

@"-": union(Subcommand) {
    @"asm": Assemble,
    disasm: Disassemble,
},

pub fn run(args: Pica, io: std.Io, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.run(io, arena),
    };
}

const Pica = @This();

const Assemble = @import("Pica/Assemble.zig");
const Disassemble = @import("Pica/Disassemble.zig");

const std = @import("std");
