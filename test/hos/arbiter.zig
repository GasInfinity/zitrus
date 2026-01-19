test "(no timeout) returns instantly succeeding" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    arbiter.arbitrate(&value, .{ .wait_if_less_than = 0 }) catch unreachable; // deadlock == failure
}

test "(timeout: 0) returns instantly with timeout" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expect(arbiter.arbitrate(&value, .{ .wait_if_less_than_timeout = .{ .value = 0, .timeout = .fromNanoseconds(0) } }) == error.Timeout);
}

test "(timeout: none) returns instantly with timeout" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expect(arbiter.arbitrate(&value, .{ .wait_if_less_than_timeout = .{ .value = 0, .timeout = .none } }) == error.Timeout);
}

const signal = struct {
    // XXX: not ideal (the sleep)
    fn one(ctx: ?*anyopaque) callconv(.c) noreturn {
        const value: *std.atomic.Value(i32) = @ptrCast(@alignCast(ctx.?));
        while (value.load(.monotonic) != -1) {
            horizon.sleepThread(20000);
        }
        horizon.testing.arbiter.arbitrate(&value.raw, .{ .signal = 1 }) catch unreachable;
        horizon.exitThread();
    }

    fn all(ctx: ?*anyopaque) callconv(.c) noreturn {
        const value: *std.atomic.Value(i32) = @ptrCast(@alignCast(ctx.?));
        while (value.load(.monotonic) != -1) {
            horizon.sleepThread(20000);
        }
        horizon.testing.arbiter.arbitrate(&value.raw, .{ .signal = -1 }) catch unreachable;
        horizon.exitThread();
    }
};

test "(no timeout) succeeds after signal" {
    const arbiter = horizon.testing.arbiter;

    var stack: [256]u8 = undefined;
    var value: i32 = 0;

    const thd: horizon.Thread = try .create(&signal.one, &value, (&stack).ptr + stack.len, .lowest, .any);
    defer thd.close();

    arbiter.arbitrate(&value, .{ .decrement_and_wait_if_less_than = 1 }) catch unreachable; // deadlock == failure
    try thd.wait(.none);
}

test "(timeout: none) succeeds after signal" {
    const arbiter = horizon.testing.arbiter;

    var stack: [256]u8 = undefined;
    var value: i32 = 0;

    const thd: horizon.Thread = try .create(&signal.one, &value, (&stack).ptr + stack.len, .lowest, .any);
    defer thd.close();

    try std.testing.expect(arbiter.arbitrate(&value, .{ .decrement_and_wait_if_less_than_timeout = .{ .value = 1, .timeout = .none } }) != error.Timeout);
    try thd.wait(.none);
}

test "(timeout: any) returns timeout without deadlocking" {
    const arbiter = horizon.testing.arbiter;

    var value: i32 = 0;

    try std.testing.expect(arbiter.arbitrate(&value, .{ .wait_if_less_than_timeout = .{ .value = 1, .timeout = .fromNanoseconds(1000) } }) == error.Timeout);
}

const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
