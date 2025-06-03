pub fn main() !void {
    @panic("Oops, something went wrong... At least we can report it ;D");
}

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
