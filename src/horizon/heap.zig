pub const page_size = 4096;
pub const page_size_min = page_size;
pub const page_size_max = page_size;

pub const CommitAllocator = @import("heap/CommitAllocator.zig");

/// Cannot be implemented without depending on global state, initialize a `CommitAllocator` and use it, this is an `Allocator.failing`
///
/// If you truly need a `page_allocator` use `linear_page_allocator`
pub const page_allocator: Allocator = .failing;

/// The pages will be linear in FCRAM.
pub const linear_page_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &LinearPageAllocator.vtable,
};

/// Allocates shared memory pages from a global bump allocator.
///
/// It is *very* unlikely that you'll hit the upper bound (64MB);
/// if you do, manage your own shared memory pages.
pub fn allocShared(size: usize) [*]align(page_size) u8 {
    const g = struct {
        var current: std.atomic.Value(u32) = .init(horizon.memory.shared_memory_begin);
    };

    const pages = std.mem.alignForward(usize, size, page_size);
    const address = g.current.fetchAdd(pages, .monotonic);
    return @ptrFromInt(address);
}

comptime {
    _ = CommitAllocator;
    _ = LinearPageAllocator;
}

const LinearPageAllocator = @import("heap/LinearPageAllocator.zig");

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
