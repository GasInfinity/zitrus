test "created and executed successfully" {
    const Data = struct { 
        a: u32,
        b: u32,
        result: ?u32,

        pub fn main(ctx: ?*anyopaque) callconv(.c) noreturn {
            const data: *@This() = @ptrCast(@alignCast(ctx.?));
            data.result = data.a + data.b;
            horizon.exitThread();
        }
    };

    var data: Data = .{
        .a = 90,
        .b = 140,
        .result = null,
    };

    var thread_stack: [1024]u8 align(8) = undefined;
    const thread: Thread = try .create(Data.main, &data, (&thread_stack).ptr + thread_stack.len, .priority(0x30), .default);
    defer thread.close();

    try thread.wait(5 * std.time.ns_per_s);
    try testing.expect(data.result == (90 + 140));
}

// XXX: This test assumes the default core for the process is the appcore
test "is cooperative" {
    const Data = struct {
        pub fn main(_: ?*anyopaque) callconv(.c) noreturn {
            horizon.exitThread();
        }
    };

    var thread_stack: [1024]u8 align(8) = undefined;
    const thread: Thread = try .create(Data.main, null, (&thread_stack).ptr + thread_stack.len, .highest_user, .default);
    defer thread.close();

    // NOTE: If we're truly cooperative, this MUST not timeout.
    try thread.wait(0);
}

const testing = std.testing;
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const Thread = horizon.Thread;
