pub const Handle = enum(u32) {
    null = 0,
    _,
};

memory_info: DeviceMemory.BoundMemoryInfo,
size: usize,
usage: mango.BufferCreateInfo.Usage,

pub fn init(create_info: mango.BufferCreateInfo) Buffer {
    return .{
        .memory_info = .empty,
        .size = @intFromEnum(create_info.size),
        .usage = create_info.usage,
    };
}

pub fn sizeByAmount(buffer: Buffer, size: mango.DeviceSize, offset: mango.DeviceSize) usize {
    return switch (size) {
        .whole => blk: {
            std.debug.assert(@intFromEnum(offset) <= buffer.size);
            break :blk (buffer.size - @intFromEnum(offset));
        },
        _ => blk: {
            std.debug.assert(@intFromEnum(offset) + @intFromEnum(size) <= buffer.size);
            break :blk @intFromEnum(size);
        },
    };
}

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
