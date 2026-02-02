pub const description = "WIP Animation Info RE";

pub const descriptions: plz.Descriptions(@This()) = .{};

pub const short: plz.Short(@This()) = .{};

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Info, io: std.Io, arena: std.mem.Allocator) !u8 {
    if (true) @panic("TODO");
    _ = args;
    _ = arena;
    _ = io;
    return 0;
}

const Info = @This();

const log = std.log.scoped(.clyt);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const etc = zitrus.compress.etc;

const lyt = zitrus.horizon.fmt.layout;
const clan = lyt.clan;
