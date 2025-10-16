pub const description = "Dump / Make / Show an ExeFS";

const Subcommand = enum {
    info,
    // make,
    dump,
};

pub const Make = struct {
    pub const description = "Make an ExeFS based on input files.";

    pub const descriptions = .{
        .output = "The output exefs file",
    };

    pub const switches = .{
        .output = 'o',
    };

    output: []const u8,

    @"--": struct {
        @"...": []const []const u8,
    },
};

@"-": union(Subcommand) {
    info: Info,
    // make: Make,
    dump: Dump,
},

pub fn main(args: ExeFs, arena: std.mem.Allocator) !u8 {
    return switch (args.@"-") {
        inline else => |sub| sub.main(arena),
    };
}


const ExeFs = @This();
const Info = @import("ExeFs/Info.zig");
const Dump = @import("ExeFs/Dump.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const exefs = zitrus.horizon.fmt.ncch.exefs;
