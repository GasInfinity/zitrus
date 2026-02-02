const builtin = @import("builtin");

comptime {
    if (!builtin.cpu.arch.isArm() or builtin.os.tag != .@"3ds") {
        @compileError("mango tests should be run on Horizon!");
    }

    // TODO: Start working on mango behavior tests
}
