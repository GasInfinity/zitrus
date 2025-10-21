//! A CommandBuffer's pool intended to be used within a single thread (not thread-safe!)
//!
//! Also handles buffer management of native gpu buffers (NOTE: Secondary CommandBuffers could go to VRAM if we know the user won't reset them individually)
//!
//! Command buffers are pooled with doubly linked lists for both allocated and freed.
//! Native buffers are pooled with a free-list slab allocator.
//!
//! When trimming, freed command buffers are truly freed to the parent `allocator`, after that
//! available and freed native buffers are deallocated to the parent `native_allocator`.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

// NOTE: With native buffers we're talking about `u32`s, not `u8`s!
const native_min_size = 4 * 1024;
const native_max_size = 128 * 1024;

const native_min_class = std.math.log2(native_min_size);
const native_max_class = std.math.log2(native_max_size);
const native_size_classes = (native_max_class - native_min_class);

pub const Node = struct {
    /// Initializes a new node with an undefined `CommandBuffer`
    pub const init_undefined: Node = .{
        .node = .{},
        .cmd_buffer = undefined,
    };

    node: std.DoublyLinkedList.Node,
    cmd_buffer: CommandBuffer,
};

gpa: std.mem.Allocator,
native_gpa: std.mem.Allocator,

allocated_command_buffers: std.DoublyLinkedList,
free_command_buffers: std.DoublyLinkedList,

free_native_buffers: [native_size_classes]usize,

pub fn init(create_info: mango.CommandPoolCreateInfo, gpa: std.mem.Allocator) !CommandPool {
    var pool: CommandPool = .{
        .gpa = gpa,
        // TODO: This will be backend-independent (in the 3ds), yay!
        .native_gpa = horizon.heap.linear_page_allocator,
        .allocated_command_buffers = .{},
        .free_command_buffers = .{},

        .free_native_buffers = @splat(0),
    };
    errdefer pool.deinit(gpa);

    if (create_info.initial_command_buffers > 0) {
        for (0..create_info.initial_command_buffers) |_| {
            pool.recycle(try pool.create());
        }
    }

    return pool;
}

pub fn deinit(pool: *CommandPool, gpa: std.mem.Allocator) void {
    std.debug.assert(pool.gpa.vtable == gpa.vtable); // At least ensure the same VTable is used as we cannot compare the pointers

    {
        var maybe_current_allocated = pool.allocated_command_buffers.first;
        while (maybe_current_allocated) |current| {
            maybe_current_allocated = current.next;

            const pool_node: *Node = @alignCast(@fieldParentPtr("node", current));

            pool.native_gpa.free(pool_node.cmd_buffer.deinit());
            pool.gpa.destroy(pool_node);
        }

        pool.allocated_command_buffers = .{};
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
    var maybe_current = pool.allocated_command_buffers.first;
    while (maybe_current) |current| {
        maybe_current = current.next;

        const b_cmd_buffer: *CommandBuffer = @alignCast(@fieldParentPtr("node", current));
        b_cmd_buffer.reset(.none);
    }
}

pub fn trim(pool: *CommandPool) void {
    var maybe_current = pool.free_command_buffers.first;
    while (maybe_current) |current| {
        maybe_current = current.next;

        const pool_node: *Node = @alignCast(@fieldParentPtr("node", current));

        pool.gpa.destroy(pool_node); // NOTE: Freed command buffers don't have a native buffer.
    }

    for (0..native_size_classes) |class| {
        var ptr = pool.free_native_buffers[class];

        while (ptr != 0) {
            const buffer: [*]align(8) u32 = @ptrFromInt(ptr);
            ptr = buffer[0];

            const slice = buffer[0..(@as(usize, 1) << @intCast(class + native_min_class))];
            pool.native_gpa.free(slice);
        }
    }

    pool.free_command_buffers = .{
        .first = null,
        .last = null,
    };
}

/// Asserts that size_hint is not 0.
pub fn allocateNative(pool: *CommandPool, size_hint: ?usize) ![]align(8) u32 {
    const needed_class_size: usize = @intCast(@max(native_min_size, std.math.ceilPowerOfTwoPromote(usize, size_hint orelse native_min_size)));

    var needed_class = nativeClassIndex(needed_class_size);

    while (needed_class < native_size_classes) : (needed_class += 1) {
        const ptr = pool.free_native_buffers[needed_class];

        if (ptr != 0) {
            const buffer: [*]align(8) u32 = @ptrFromInt(ptr);

            pool.free_native_buffers[needed_class] = buffer[0];
            return buffer[0..(@as(usize, 1) << @intCast(needed_class + native_min_class))];
        }
    }

    return try pool.native_gpa.alignedAlloc(u32, .@"8", needed_class_size);
}

pub fn remapNative(pool: *CommandPool, buffer: []align(8) u32, used: usize, new_len: usize) ![]align(8) u32 {
    if (buffer.len == 0) return try pool.allocateNative(null);

    const next_class_len: usize = @intCast(std.math.ceilPowerOfTwoPromote(usize, new_len));

    if (pool.gpa.remap(buffer, next_class_len)) |remapped| {
        return remapped;
    }

    const new_buffer = try pool.allocateNative(next_class_len);
    defer pool.recycleNative(buffer);

    @memcpy(new_buffer[0..used], buffer[0..used]);
    return new_buffer;
}

pub fn recycleNative(pool: *CommandPool, buffer: []align(8) u32) void {
    if (buffer.len == 0) return;

    const buffer_class = nativeClassIndex(buffer.len);

    if (buffer_class >= native_size_classes) {
        pool.native_gpa.free(buffer);
        return;
    }

    buffer[0] = pool.free_native_buffers[buffer_class];
    pool.free_native_buffers[buffer_class] = @intFromPtr(buffer.ptr);
}

fn nativeClassIndex(size: usize) usize {
    return (std.math.log2(size) - native_min_class);
}

fn create(pool: *CommandPool) !*CommandBuffer {
    const allocated_node = pool.free_command_buffers.popFirst() orelse blk: {
        const gpa = pool.gpa;
        const pool_node = try gpa.create(Node);
        pool_node.* = .init_undefined;

        break :blk &pool_node.node;
    };

    const pool_node: *Node = @alignCast(@fieldParentPtr("node", allocated_node));
    errdefer pool.free_command_buffers.append(allocated_node); // Ensure we won't leak memory!

    pool_node.cmd_buffer = .initBuffer(pool, try pool.allocateNative(null));
    errdefer @compileError("If we return an error, this pool will have wrong state!");

    pool.allocated_command_buffers.append(allocated_node);
    return &pool_node.cmd_buffer;
}

fn recycle(pool: *CommandPool, cmd_buffer: *CommandBuffer) void {
    const pool_node: *Node = @alignCast(@fieldParentPtr("cmd_buffer", cmd_buffer));

    pool.recycleNative(cmd_buffer.deinit());
    pool.allocated_command_buffers.remove(&pool_node.node);
    pool.free_command_buffers.append(&pool_node.node);
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
