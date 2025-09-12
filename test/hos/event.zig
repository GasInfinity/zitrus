fn expectUnsignaled(ev: Event) !void {
    ev.wait(0) catch |err| switch(err) {
        error.Timeout => return,
        else => return err,
    };

    try testing.expect(false);
}

test "created non signaled" {
    const ev: Event = try .create(.oneshot);
    defer ev.close();
    
    try expectUnsignaled(ev);
}

test "oneshot reset when a thread wakes up" {
    const oneshot: Event = try .create(.oneshot);
    defer oneshot.close();

    oneshot.signal();
    try oneshot.wait(0); // must not fail as the event is already signaled

    try expectUnsignaled(oneshot);
}

test "sticky never reset unless explicitly done" {
    const sticky: Event = try .create(.sticky);
    defer sticky.close();

    sticky.signal();

    for (0..4) |_| {
        try sticky.wait(0); // must not fail for any iteration
    }

    sticky.clear();

    try expectUnsignaled(sticky);
}

test "duplicated shares state" {
    const ev: Event = try .create(.oneshot);
    defer ev.close();

    const dup_ev: Event = try ev.dupe();
    defer dup_ev.close();

    ev.signal();
    try dup_ev.wait(0); 

    dup_ev.signal();
    try ev.wait(0);

    try expectUnsignaled(ev);
    try expectUnsignaled(dup_ev);
}

const testing = std.testing;
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const Event = horizon.Event;
