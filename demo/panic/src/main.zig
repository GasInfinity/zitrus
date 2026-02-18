pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub fn main() !void {
    @panic("Oh no!");
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const std = @import("std");
