//! A general purpose thread-safe allocator that commits memory when needed,
//! decommits all of the memory when deinitialized.

const vtable: *const Allocator.VTable = &.{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

pub const Error = Allocator.Error;

const max_usize = std.math.maxInt(usize);
const ushift = std.math.Log2Int(usize);
const bigpage_size = 64 * 1024;
const pages_per_bigpage = bigpage_size / horizon.heap.page_size;
const bigpage_count = max_usize / bigpage_size;

/// Because of storing free list pointers, the minimum size class is 3.
const min_class = std.math.log2(@sizeOf(usize));
const size_class_count = std.math.log2(bigpage_size) - min_class;
/// 0 - 1 bigpage
/// 1 - 2 bigpages
/// 2 - 4 bigpages
/// etc.
const big_size_class_count = std.math.log2(bigpage_count);

const Node = struct { next: ?*Node };

arbiter: AddressArbiter,
// NOTE: Here we *may* benefit from using a Mutex instead of atomic operations as it will most likely always be uncontended and we're running under a mostly cooperative environment.
mutex: AddressArbiter.Mutex = .{},

/// Must be set to the start of the heap, used for decommiting memory
heap_begin: usize = horizon.memory.heap_begin,
heap_end: usize = horizon.memory.heap_begin,

next_addrs: [size_class_count]usize = @splat(0),
/// For each size class, points to the freed pointer.
frees: [size_class_count]?*Node = @splat(null),
/// For each big size class, points to the freed pointer.
big_frees: [size_class_count]?*Node = @splat(null),

pub fn init(arbiter: AddressArbiter, heap_begin: usize) CommitAllocator {
    return .{
        .arbiter = arbiter,
        .heap_begin = heap_begin,
        .heap_end = heap_begin,
    };
}

/// Decommits all the memory used by this allocator
pub fn deinit(cma: *CommitAllocator) void {
    _ = horizon.controlMemory(.{
        .kind = .free,
        .area = .all,
        .linear = false,
    }, @ptrFromInt(cma.heap_begin), null, (cma.heap_end - cma.heap_begin), .rw);
    cma.* = undefined;
}

pub fn allocator(cma: *CommitAllocator) Allocator {
    return .{
        .ptr = cma,
        .vtable = vtable,
    };
}

fn alloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, _: usize) ?[*]u8 {
    switch (alignment.order(.fromByteUnits(bigpage_size))) {
        .eq, .lt => {},
        .gt => return null, // We don't support alignments buffer than 64KB!
    }

    const cma: *CommitAllocator = @ptrCast(@alignCast(ctx));

    cma.mutex.lock(cma.arbiter);
    defer cma.mutex.unlock(cma.arbiter);

    // Make room for the freelist next pointer.
    const actual_len = @max(len, @sizeOf(usize), alignment.toByteUnits());
    const slot_size = std.math.ceilPowerOfTwo(usize, actual_len) catch return null;
    const class = std.math.log2(slot_size) - min_class;

    if (class < size_class_count) {
        return if (cma.frees[class]) |found| blk: {
            log.debug("allocated {} bytes at {*} (small, freelist)", .{ actual_len, found });
            cma.frees[class] = found.next;
            break :blk @ptrCast(found);
        } else switch (cma.next_addrs[class] % bigpage_size) {
            0 => blk: {
                const alloc_addr = cma.allocBigPages(1);
                if (alloc_addr == 0) break :blk null;
                log.debug("allocated {} bytes at {X} (small)", .{ actual_len, alloc_addr });
                cma.next_addrs[class] = alloc_addr + slot_size;
                break :blk @ptrFromInt(alloc_addr);
            },
            else => blk: {
                defer cma.next_addrs[class] += slot_size;
                log.debug("allocated {} bytes at {X} (small, next_addr)", .{ actual_len, cma.next_addrs[class] });
                break :blk @ptrFromInt(cma.next_addrs[class]);
            },
        };
    }

    return switch (cma.allocBigPages(@divExact(std.mem.alignForward(usize, actual_len, bigpage_size), bigpage_size))) {
        0 => null,
        else => |val| @ptrFromInt(val),
    };
}

fn resize(
    ctx: *anyopaque,
    buf: []u8,
    alignment: mem.Alignment,
    new_len: usize,
    return_address: usize,
) bool {
    // We don't have to lock as we don't touch state.
    _ = ctx;
    _ = return_address;

    // We don't want to move anything from one size class to another, but we
    // can recover bytes in between powers of two.

    const buf_align = alignment.toByteUnits();

    const old_actual_len = @max(buf.len, @sizeOf(usize), buf_align);
    const new_actual_len = @max(new_len, @sizeOf(usize), buf_align);

    const old_small_slot_size = std.math.ceilPowerOfTwoAssert(usize, old_actual_len);
    const old_small_class = std.math.log2(old_small_slot_size) - min_class;

    if (old_small_class < size_class_count) {
        const new_small_slot_size = std.math.ceilPowerOfTwo(usize, new_actual_len) catch return false;
        return old_small_slot_size == new_small_slot_size;
    } else {
        const old_bigpages_needed = @divExact(std.mem.alignForward(usize, old_actual_len, bigpage_size), bigpage_size);
        const old_big_slot_pages = std.math.ceilPowerOfTwoAssert(usize, old_bigpages_needed);
        const new_bigpages_needed = @divExact(std.mem.alignForward(usize, new_actual_len, bigpage_size), bigpage_size);
        const new_big_slot_pages = std.math.ceilPowerOfTwo(usize, new_bigpages_needed) catch return false;
        return old_big_slot_pages == new_big_slot_pages;
    }
}

fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

fn free(
    ctx: *anyopaque,
    buf: []u8,
    alignment: mem.Alignment,
    return_address: usize,
) void {
    _ = return_address;
    const cma: *CommitAllocator = @ptrCast(@alignCast(ctx));

    cma.mutex.lock(cma.arbiter);
    defer cma.mutex.unlock(cma.arbiter);

    const buf_align = alignment.toByteUnits();
    const actual_len = @max(buf.len, @sizeOf(usize), buf_align);
    const slot_size = std.math.ceilPowerOfTwoAssert(usize, actual_len);
    const class = std.math.log2(slot_size) - min_class;

    if (class < size_class_count) {
        log.debug("freed {} bytes (small, freelist)", .{buf.len});
        const freed = @as(*Node, @ptrCast(@alignCast(buf.ptr)));
        freed.next = cma.frees[class];
        cma.frees[class] = freed;
    } else {
        log.debug("freed {} bytes (big, freelist)", .{buf.len});
        cma.freeBigPages(@alignCast(buf.ptr), @divExact(std.mem.alignForward(usize, actual_len, bigpage_size), bigpage_size));
    }
}

/// Assumes `cma.mutex` is held.
fn allocBigPages(cma: *CommitAllocator, n: usize) usize {
    const pow2_pages = std.math.ceilPowerOfTwoAssert(usize, n);
    const slot_size_bytes = pow2_pages * bigpage_size;
    const class = std.math.log2(pow2_pages);

    return if (cma.big_frees[class]) |found| blk: {
        log.debug("allocated {} bytes at {*} (big, freelist)", .{ slot_size_bytes, cma.big_frees[class] });
        cma.big_frees[class] = found.next;
        break :blk @intFromPtr(found);
    } else switch (horizon.controlMemory(.{
        .kind = .commit,
        .area = .all,
        .linear = false,
    }, @ptrFromInt(cma.heap_end), null, slot_size_bytes, .rw).cases()) {
        .success => |r| blk: {
            log.debug("commited and allocated {} bytes at {X} (big)", .{ slot_size_bytes, cma.heap_end });
            cma.heap_end += slot_size_bytes;
            break :blk @intFromPtr(r.value);
        },
        .failure => 0,
    };
}

/// Assumes `cma.mutex` is held.
fn freeBigPages(cma: *CommitAllocator, address: [*]align(horizon.heap.page_size) u8, n: usize) void {
    const pow2_pages = std.math.ceilPowerOfTwoAssert(usize, n);
    const big_class = std.math.log2(pow2_pages);

    log.info("freed {} bytes at {*} (big)", .{ pow2_pages * bigpage_size, address });
    const node: *Node = @ptrCast(address);
    node.next = cma.big_frees[big_class];
    cma.big_frees[big_class] = node;
}

const CommitAllocator = @This();

const log = std.log.scoped(.commit_allocator);
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = mem.Alignment;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const AddressArbiter = horizon.AddressArbiter;
