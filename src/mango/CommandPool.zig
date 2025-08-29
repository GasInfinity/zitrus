//! A CommandBuffer's pool intended to be used within a single thread (not thread-safe!)
//!
//! Also handles buffer management of native gpu buffers (NOTE: Secondary CommandBuffers could go to VRAM if we know the user won't reset them individually)

pub const Handle = enum(u32) {
    null = 0,
    _,
};

allocator: std.mem.Allocator,
allocated_buffers: std.DoublyLinkedList,
free_buffers: std.DoublyLinkedList,

pub fn init(create_info: mango.CommandPoolCreateInfo, allocator: std.mem.Allocator) CommandPool {
    _ = create_info;
    return .{
        .allocator = allocator,
        .allocated_buffers = .{},
        .free_buffers = .{},
    };
}

pub fn deinit(pool: *CommandPool, allocator: std.mem.Allocator) void {
    _ = allocator;
    {
        var maybe_current_allocated = pool.allocated_buffers.first;
        while (maybe_current_allocated) |current| {
            maybe_current_allocated = current.next;

            const command_buffer: *CommandBuffer = @alignCast(@fieldParentPtr("node", current));
            command_buffer.deinit();

            pool.allocator.destroy(command_buffer);
        }

        pool.allocated_buffers.first = null;
        pool.allocated_buffers.last = null;
    }

    pool.trim();
    pool.* = undefined;
}

pub fn allocate(pool: *CommandPool, buffers: []mango.CommandBuffer) !void {
    var allocated_buffers: u32 = 0;
    errdefer pool.free(buffers[0..allocated_buffers]);

    for (buffers) |*buffer| {
        const b_cmd: *CommandBuffer = try pool.create();
        buffer.* = b_cmd.toHandle();
        allocated_buffers += 1;
    }
}

pub fn free(pool: *CommandPool, buffers: []const mango.CommandBuffer) void {
    for (buffers) |buffer| {
        const b_cmd: *CommandBuffer = .fromHandleMutable(buffer);
        pool.recycle(b_cmd);
    }
}

pub fn reset(pool: *CommandPool) void {
    var maybe_current = pool.allocated_buffers.first;
    while (maybe_current) |current| {
        maybe_current = current.next;

        const b_cmd_buffer: *CommandBuffer = @alignCast(@fieldParentPtr("node", current));
        b_cmd_buffer.reset();
    }
}

pub fn trim(pool: *CommandPool) void {
    var maybe_current = pool.free_buffers.first;
    while (maybe_current) |current| {
        maybe_current = current.next;

        const b_cmd_buffer: *CommandBuffer = @alignCast(@fieldParentPtr("node", current));
        b_cmd_buffer.deinit();

        pool.allocator.destroy(b_cmd_buffer);
    }

    pool.free_buffers.first = null;
    pool.free_buffers.last = null;
}

pub fn allocateNative(pool: *CommandPool, size: u32) ![]align(8) u32 {
    _ = pool;
    return switch (horizon.controlMemory(.{
        .fundamental_operation = .commit,
        .area = .all,
        .linear = true,
    }, null, null, size * @sizeOf(u32), .rw)) {
        .success => |s| std.mem.bytesAsSlice(u32, s.value[0..(size * @sizeOf(u32))]),
        .failure => return error.OutOfMemory,
    };
}

pub fn freeNative(pool: *CommandPool, buffer: []align(8) u32) void {
    _ = pool;
    _ = horizon.controlMemory(.{
        .fundamental_operation = .free,
        .area = .all,
        .linear = true,
    }, @ptrCast(buffer.ptr), null, buffer.len * @sizeOf(u32), .rw);
}

fn create(pool: *CommandPool) !*CommandBuffer {
    const new_cmd_buffer = pool.free_buffers.popFirst() orelse blk: {
        const gpa = pool.allocator;
        const b_cmd_buffer = try gpa.create(CommandBuffer);
        const native_buffer = try pool.allocateNative(horizon.heap.page_size / @sizeOf(u32));

        b_cmd_buffer.* = .init(pool, native_buffer);
        break :blk &b_cmd_buffer.node;
    };
    pool.allocated_buffers.append(new_cmd_buffer);
    return @alignCast(@fieldParentPtr("node", new_cmd_buffer));
}

fn recycle(pool: *CommandPool, b_cmd_buffer: *CommandBuffer) void {
    b_cmd_buffer.reset();

    pool.allocated_buffers.remove(&b_cmd_buffer.node);
    pool.free_buffers.append(&b_cmd_buffer.node);
}

pub fn toHandle(image: *CommandPool) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *CommandPool {
    return @as(*CommandPool, @ptrFromInt(@intFromEnum(handle)));
}

const CommandPool = @This();

const backend = @import("backend.zig");
const CommandBuffer = backend.CommandBuffer;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const horizon = zitrus.horizon;
