pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

// TODO: Aligned allocations with a bigger alignment than a page
pub fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = ret_addr;

    if (alignment.order(.fromByteUnits(horizon.heap.page_size)) == .gt) {
        return null;
    }

    const aligned_len = std.mem.alignForward(usize, len, horizon.heap.page_size);
    const allocation_result = horizon.controlMemory(horizon.MemoryOperation{
        .fundamental_operation = .commit,
        .area = .all,
        .linear = true,
    }, null, null, aligned_len, .rw);

    if (!allocation_result.code.isSuccess()) {
        return null;
    }

    return @ptrCast(allocation_result.value.?);
}

pub fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = ret_addr;
    std.debug.assert(alignment.toByteUnits() <= horizon.heap.page_size);

    const aligned_len = std.mem.alignForward(usize, memory.len, horizon.heap.page_size);

    if (aligned_len >= new_len) {
        return true;
    }

    return false;
}

pub fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
}

pub fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    _ = ctx;
    _ = ra;

    std.debug.assert(alignment.toByteUnits() <= horizon.heap.page_size);
    const aligned_len = std.mem.alignForward(usize, memory.len, horizon.heap.page_size);

    _ = horizon.controlMemory(horizon.MemoryOperation{
        .fundamental_operation = .free,
        .area = .all,
        .linear = true,
    }, @ptrCast(memory.ptr), null, aligned_len, .rw);
}

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = mem.Alignment;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
