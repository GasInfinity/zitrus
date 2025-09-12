const builtin = @import("builtin");

comptime {
    if(!builtin.cpu.arch.isArm() or builtin.os.tag != .other) {
        @compileError("mango tests should be run on Horizon!");
    }

    // TODO: Start working on mango behavior tests
}
