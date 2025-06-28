pub const page_size = 4096;
pub const page_size_min = page_size;
pub const page_size_max = page_size;

/// The pages won't neccesarily be linear in FCRAM, use linear_page_allocator if you need that guarantee.
pub const page_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &PageAllocator.vtable,
};

/// The pages will be linear in FCRAM.
pub const linear_page_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &LinearPageAllocator.vtable,
};

// XXX: This must use another interface as its not really allocating real memory
pub const shared_memory_address_allocator = thread_safe_shared_memory_address_allocator.allocator();

var non_thread_safe_shared_memory_address_allocator: SharedMemoryAddressAllocator = .init(@ptrFromInt(horizon.memory.shared_memory_begin));
var thread_safe_shared_memory_address_allocator: std.heap.ThreadSafeAllocator = .{ .child_allocator = non_thread_safe_shared_memory_address_allocator.allocator() };

const SharedMemoryAddressAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(page_size), (horizon.memory.shared_memory_end - horizon.memory.shared_memory_begin));
const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(page_size), zitrus.memory.vram_bank_size);

const PageAllocator = @import("heap/PageAllocator.zig");
const LinearPageAllocator = @import("heap/LinearPageAllocator.zig");

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zalloc = @import("zalloc");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
