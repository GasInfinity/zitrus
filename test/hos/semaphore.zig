test "respects initial count" {
    const sema: Semaphore = try .create(0, 1);
    defer sema.close();

    try testing.expect(sema.release(1) == 0);
}

const testing = std.testing;
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const Thread = horizon.Thread;
const Semaphore = horizon.Semaphore;
