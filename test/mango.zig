//! Simple behavior checks to test:
//! 1 - mango does what it *should*
//! 2 - The GPU behaves as expected

const builtin = @import("builtin");

comptime {
    if (!builtin.cpu.arch.isArm() or builtin.os.tag != .@"3ds") {
        @compileError("mango tests should be run on Horizon!");
    }

    _ = @import("mango/transfer_queue.zig");
    _ = @import("mango/fill_queue.zig");
    _ = @import("mango/render.zig");
}
