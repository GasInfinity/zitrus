//! Simple behavior checks to test:
//! 1 - The syscalls are correct
//! 2 - The kernel behaves as it should

const builtin = @import("builtin");

comptime {
    if (!builtin.cpu.arch.isArm() or builtin.os.tag != .@"3ds") {
        @compileError("hos tests must be run on Horizon!");
    }

    _ = @import("hos/event.zig");
    _ = @import("hos/timer.zig");
    _ = @import("hos/thread.zig");
    _ = @import("hos/mutex.zig");
    _ = @import("hos/semaphore.zig");
    _ = @import("hos/arbiter.zig");
}

const zitrus = @import("zitrus");
