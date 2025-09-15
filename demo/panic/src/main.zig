// export threadlocal var test_tls: usize = 20;
// export threadlocal var test_tls_bss: usize = undefined;
// export var test_a: usize = 2200;

pub fn main() !void {
    // test_tls = 20;
    // test_a = 500;
    // asm volatile("" :: [t] "r" (&test_tls), [b] "r" (&test_tls_bss), [e] "r" (&test_a) : .{ .memory = true });
    @panic("Oops, something went wrong... At least we can report it ;D");
}

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
