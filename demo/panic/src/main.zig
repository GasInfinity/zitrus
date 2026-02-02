pub const os = horizon;
pub const debug = horizon.debug;
pub const panic = std.debug.FullPanic(debug.defaultPanic);
pub const std_options: std.Options = horizon.default_std_options;

pub const std_options_debug_io: std.Io = horizon.Io.failing;
comptime { _ = horizon.start; }

pub fn main(_: std.process.Init.Minimal) !void {
    if (true) @panic("Oh no!");

    const unmapped_100: *u32 = @ptrFromInt(0x04);
    unmapped_100.* = 6_7;
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const std = @import("std");
