test "(no timeout) returns instantly succeeding" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    arbiter.wait(i32, &value, 0); // deadlock == failure
}

test "(timeout: 0) returns instantly with timeout" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expectError(error.Timeout, arbiter.waitTimeout(i32, &value, 0, .fromNanoseconds(0)));
}

test "(timeout: none) returns instantly with timeout" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expectError(error.Timeout, arbiter.waitTimeout(i32, &value, 0, .none));
}

const signal = struct {
    // XXX: not ideal (the sleep)
    fn one(ctx: ?*anyopaque) callconv(.c) noreturn {
        const value: *std.atomic.Value(i32) = @ptrCast(@alignCast(ctx.?));
        while (value.load(.monotonic) != -1) {
            horizon.sleepThread(20000);
        }

        horizon.testing.arbiter.signal(i32, &value.raw, 1);
        horizon.exitThread();
    }

    fn all(ctx: ?*anyopaque) callconv(.c) noreturn {
        const value: *std.atomic.Value(i32) = @ptrCast(@alignCast(ctx.?));
        while (value.load(.monotonic) != -1) {
            horizon.sleepThread(20000);
        }
        horizon.testing.arbiter.signal(i32, &value.raw, null);
        horizon.exitThread();
    }
};

test "(no timeout) succeeds after signal" {
    const arbiter = horizon.testing.arbiter;

    const thread_stack = try horizon.testing.allocator.alignedAlloc(u8, .@"8", 8192);
    defer horizon.testing.allocator.free(thread_stack);

    var value: i32 = 0;

    const thd: horizon.Thread = try .create(&signal.one, &value, thread_stack.ptr + thread_stack.len, .lowest, .any);
    defer thd.close();

    arbiter.arbitrate(&value, .{ .decrement_and_wait_if_less_than = 1 }) catch unreachable; // deadlock == failure
    try thd.wait(.none);
}

test "(timeout: none) succeeds after signal" {
    const arbiter = horizon.testing.arbiter;

    const thread_stack = try horizon.testing.allocator.alignedAlloc(u8, .@"8", 8192);
    defer horizon.testing.allocator.free(thread_stack);

    var value: i32 = 0;

    const thd: horizon.Thread = try .create(&signal.one, &value, thread_stack.ptr + thread_stack.len, .lowest, .any);
    defer thd.close();

    try arbiter.arbitrate(&value, .{ .decrement_and_wait_if_less_than_timeout = .{ .value = 1, .timeout = .none } });
    try thd.wait(.none);
}

test "(timeout: any) returns timeout without deadlocking" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expectError(error.Timeout, arbiter.waitTimeout(i32, &value, 1, .fromNanoseconds(1000)));
}

test "AddressArbiter.Mutex smoke test" {
    const arbiter = horizon.testing.arbiter;

    var mutex: AddressArbiter.Mutex = .init;

    try std.testing.expect(mutex.tryLock());
    mutex.unlock(arbiter);

    mutex.lock(arbiter);
    mutex.unlock(arbiter);
}

const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
const AddressArbiter = horizon.AddressArbiter;
