pub const description = "Disassemble PICA200 shader ISA into zitrus PICA200 shader assembly.";

pub const Format = enum {
    raw,
    dvl,
    zpsh,
};

@"-": union(Format) {
    raw: Raw,
    dvl: Dvl,
    zpsh: Zpsh,
},

pub fn main(args: Disassemble, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |fmt| fmt.main(arena),
    };
}

const Disassemble = @This();

const Raw = @import("Disassemble/Raw.zig");
const Zpsh = @import("Disassemble/Zpsh.zig");
const Dvl = @import("Disassemble/Dvl.zig");

const std = @import("std");
