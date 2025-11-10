pub const description = "WIP Animation Info RE";

pub const descriptions = .{
};

pub const switches = .{
};

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Info, arena: std.mem.Allocator) !u8 {
    if(true) @panic("TODO");
    _ = args;
    _ = arena;
    return 0;
}

const Info = @This();

const log = std.log.scoped(.clyt);

const std = @import("std");
const zitrus = @import("zitrus");
const etc = zitrus.compress.etc;

const lyt = zitrus.horizon.fmt.layout;
const clan = lyt.clan;
