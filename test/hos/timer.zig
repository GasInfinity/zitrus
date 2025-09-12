fn expectUnsignaled(tim: Timer) !void {
    tim.wait(0) catch |err| switch(err) {
        error.Timeout => return,
        else => return err,
    };

    try testing.expect(false);
}

test "created non signaled" {
    const tim: Timer = try .create(.oneshot);
    defer tim.close();
    
    try expectUnsignaled(tim);
}

test "duplicated shares state" {
    const tim: Timer = try .create(.oneshot);
    defer tim.close();

    const dup_tim: Timer = try tim.dupe();
    defer dup_tim.close();

    tim.set(0, 0);
    try dup_tim.wait(0); 

    dup_tim.set(0, 0);
    try tim.wait(0);

    try expectUnsignaled(tim);
    try expectUnsignaled(dup_tim);
}

test "oneshot reset when a thread wakes up" {
    const oneshot: Timer = try .create(.oneshot);
    defer oneshot.close();

    oneshot.set(0, 0);
    try oneshot.wait(0); // must not fail as the event is already signaled

    try expectUnsignaled(oneshot);
}

test "sticky never reset unless explicitly done" {
    const sticky: Timer = try .create(.sticky);
    defer sticky.close();

    sticky.set(0, 0);

    for (0..4) |_| {
        try sticky.wait(0); // must not fail for any iteration
    }

    sticky.clear();

    try expectUnsignaled(sticky);
}

const testing = std.testing;
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const Timer = horizon.Timer;
