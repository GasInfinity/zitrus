//! Semaphores in mango are basically timeline semaphores in vulkan, they have a monotonically increasing 64-bit value.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

// TODO: Use atomics when zig supports them
value: zitrus.hardware.cpu.arm11.Monitor(u64),

/// Wake cookie.
wake: std.atomic.Value(i32) = .init(0),

pub fn init(create_info: mango.SemaphoreCreateInfo) Semaphore {
    return .{
        .value = .init(create_info.initial_value),
    };
}

pub fn counterValue(sema: *Semaphore) u64 {
    return sema.value.load();
}

pub fn signal(sema: *Semaphore, value: u64) bool {
    while (true) {
        _ = sema.value.load();
        if (!sema.value.store(value)) break;
    }

    return sema.wake.swap(0, .monotonic) < 0;
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
