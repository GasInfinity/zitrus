fn expectLocked(mut: Mutex) !void {
    const ExpectLockedData = struct {
        mut: Mutex,
        result: anyerror!void,

        pub fn main(ctx: ?*anyopaque) callconv(.c) noreturn {
            const data: *@This() = @ptrCast(@alignCast(ctx.?));
            data.result = data.mut.wait(0);
            horizon.exitThread();
        }
    };

    var expect_locked_data: ExpectLockedData = .{
        .mut = mut,
        .result = {},
    };

    var thrd_stack: [256]u8 align(8) = undefined;
    const thrd: Thread = try .create(ExpectLockedData.main, &expect_locked_data, (&thrd_stack).ptr + (thrd_stack.len - 1), .priority(0x30), .default);
    defer thrd.close();

    try thrd.wait(-1);

    expect_locked_data.result catch |err| switch(err) {
        error.Timeout => return,
        else => return err,
    };

    try testing.expect(false);
}

test "respects initial locked state" {
    const mut_lock: Mutex = try .create(true);
    defer mut_lock.close();

    // WARNING: Mutexes MUST be in a non-locked state before being released or the kernel will crash!
    defer mut_lock.release();

    try expectLocked(mut_lock);
}

test "wait locks the mutex" {
    const mut: Mutex = try .create(false);
    defer mut.close();

    try mut.wait(0);
    defer mut.release();

    try expectLocked(mut);
}

const testing = std.testing;
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const Thread = horizon.Thread;
const Mutex = horizon.Mutex;
