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

// FIXME: This must use another interface as its not really allocating real memory and cannot be written!
pub var non_thread_safe_shared_memory_address_allocator: SharedMemoryAddressAllocator = .init(@ptrFromInt(horizon.memory.shared_memory_begin));

comptime {
    _ = CommitAllocator;
    _ = LinearPageAllocator;
}

const SharedMemoryAddressAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(page_size), (horizon.memory.shared_memory_end - horizon.memory.shared_memory_begin));
const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(page_size), zitrus.memory.vram_bank_size);

const LinearPageAllocator = @import("heap/LinearPageAllocator.zig");

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zalloc = @import("zalloc");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
