//! Semaphores in mango are basically timeline semaphores in vulkan, they have a monotonically increasing 64-bit value.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

/// DO NOT ACCESS THIS FIELD LIKE THIS!!! ACCESSES MUST BE ATOMIC, USE value()!
raw_value: u64,

/// Wake cookie.
wake: i32,

pub fn init(create_info: mango.SemaphoreCreateInfo) Semaphore {
    return .{
        .raw_value = create_info.initial_value,
        .wake = -1,
    };
}

pub fn counterValue(sema: *Semaphore) u64 {
    return zitrus.atomicLoad64(u64, &sema.raw_value);
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
