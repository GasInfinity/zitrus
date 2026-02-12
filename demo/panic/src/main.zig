pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;
pub const std_options: std.Options = horizon.default_std_options;
pub const std_options_debug_io: std.Io = horizon.Io.io(undefined); // FIXME: pluh, we may need global state...

pub fn main() !void {
    @panic("Oh no!");
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const std = @import("std");
