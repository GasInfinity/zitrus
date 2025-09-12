const builtin = @import("builtin");

comptime {
    if(!builtin.cpu.arch.isArm() or builtin.os.tag != .other) {
        @compileError("hos tests must be run on Horizon!");
    }

    _ = @import("hos/event.zig");
    _ = @import("hos/timer.zig");
    _ = @import("hos/thread.zig");
    _ = @import("hos/mutex.zig");
    _ = @import("hos/semaphore.zig");
}

const zitrus = @import("zitrus");
