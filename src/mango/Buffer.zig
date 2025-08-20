pub const Handle = enum(u32) {
    null = 0,
    _,
};

memory_info: DeviceMemory.BoundMemoryInfo,
size: usize,
usage: mango.BufferCreateInfo.Usage,

pub fn toHandle(buffer: *Buffer) Handle {
    return @enumFromInt(@intFromPtr(buffer));
}

pub fn fromHandleMutable(handle: Handle) *Buffer {
    return @as(*Buffer, @ptrFromInt(@intFromEnum(handle)));
}

pub fn fromHandle(handle: Handle) Buffer {
    return fromHandleMutable(handle).*;
}

const Buffer = @This();
const backend = @import("backend.zig");
const DeviceMemory = backend.DeviceMemory;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
