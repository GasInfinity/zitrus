//! Semaphores in mango are basically timeline semaphores in vulkan, they have a monotonically increasing 64-bit value.

// XXX: Same as with the presentation engine, I CANNOT use this until I have -fno-single-threaded 😭
// XXX: Blocker, 64-bit atomics are not supported in zig, as it doesn't implement the feature detection for it.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

value: std.atomic.Value(u64),
wake: u32,

pub fn init(create_info: mango.SemaphoreCreateInfo) Semaphore {
    return .{
        .value = .{ .raw = create_info.initial_value },
        .wake = 0,
    };
}

pub fn signal(sema: *Semaphore, value: u64) void {
    _ = sema;
    _ = value;
}

pub fn wait(sema: *Semaphore, value: u64, timeout: i64) void {
    _ = sema;
    _ = value;
    _ = timeout;
}

pub fn toHandle(image: *Semaphore) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *Semaphore {
    return @as(*Semaphore, @ptrFromInt(@intFromEnum(handle)));
}

const Semaphore = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
