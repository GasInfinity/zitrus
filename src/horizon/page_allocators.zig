pub const linear_page_allocator = std.mem.Allocator{ .ptr = undefined, .vtable = &.{
    .alloc = linearAlloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = linearFree,
} };

// XXX: This is a very rough approximation of how I think it should work. Needs more testing
pub fn linearAlloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
    _ = ctx;
    _ = ra;

    std.debug.assert(switch (alignment.order(.fromByteUnits(horizon.page_size_min))) {
        .lt, .eq => true,
        else => false,
    });
    const aligned_len = std.mem.alignForward(usize, n, horizon.page_size_min);

    const allocation_result = horizon.controlMemory(horizon.MemoryOperation{
        .fundamental_operation = .commit,
        .area = .all,
        .linear = true,
    }, null, null, aligned_len, .rw);

    if (!allocation_result.code.isSuccess()) {
        return null;
    }

    const addr = allocation_result.value.?;
    // TODO: Aligned allocations
    return @ptrCast(addr);
}

pub fn linearFree(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ra: usize) void {
    _ = ctx;
    _ = ra;
    _ = alignment;

    const aligned_len = std.mem.alignForward(usize, buf.len, horizon.page_size_min);

    _ = horizon.controlMemory(horizon.MemoryOperation{
        .fundamental_operation = .free,
        .area = .all,
        .linear = true,
    }, @ptrCast(buf.ptr), null, aligned_len, .rw);
}

// XXX: This currently works but we can maybe use a buddy allocator?
pub const SharedMemoryAddressPageAllocator = struct {
    pub const Error = error{OutOfAddresses};

    map: std.StaticBitSet((horizon.shared_memory_end - horizon.shared_memory_begin) / horizon.page_size_min) = .initEmpty(),
    last_free_hint: u16 = 0,

    pub fn init() SharedMemoryAddressPageAllocator {
        return SharedMemoryAddressPageAllocator{};
    }

    pub fn allocateAddress(shm_addr_alloc: *SharedMemoryAddressPageAllocator, n: usize) Error![]align(horizon.page_size_min) u8 {
        const aligned_len = std.mem.alignForward(usize, n, horizon.page_size_min);
        const pages_len = aligned_len / horizon.page_size_min;

        const last_free_page_hint = shm_addr_alloc.last_free_hint;

        const found_pages_end = ps: {
            var current_scanned_page = last_free_page_hint;
            var sequential_pages_found: usize = 0;

            while (true) {
                if (!shm_addr_alloc.map.isSet(current_scanned_page)) {
                    sequential_pages_found += 1;

                    if (sequential_pages_found >= pages_len) {
                        break :ps (current_scanned_page + 1); // The range is exclusive
                    }
                }

                current_scanned_page += 1;
                if (current_scanned_page == last_free_page_hint) {
                    // We wrapped around and we still didn't find any free page
                    return Error.OutOfAddresses;
                } else if (current_scanned_page >= shm_addr_alloc.map.capacity()) {
                    current_scanned_page = 0;

                    // Restart scan as we are searching sequential pages
                    sequential_pages_found = 0;
                }
            }

            break :ps current_scanned_page - pages_len;
        };

        shm_addr_alloc.last_free_hint = found_pages_end;
        const found_pages_start = found_pages_end - pages_len;
        shm_addr_alloc.map.setRangeValue(.{ .start = found_pages_start, .end = found_pages_end }, true);

        return @alignCast(@as([*]u8, @ptrFromInt(horizon.shared_memory_begin + found_pages_start * horizon.page_size_min))[0..aligned_len]);
    }

    pub fn freeAddress(shm_addr_alloc: *SharedMemoryAddressPageAllocator, addr: []u8) void {
        const ptr = @intFromPtr(addr.ptr);

        std.debug.assert(std.mem.isAligned(addr.len, horizon.page_size_min));
        std.debug.assert(ptr >= horizon.shared_memory_begin and ptr < horizon.shared_memory_end);

        const page_index = (@intFromPtr(addr.ptr) - horizon.shared_memory_begin) / horizon.page_size_min;
        const pages_len = addr.len / horizon.page_size_min;

        // Sanity check (double free / corrupted bitmap)
        for (0..pages_len) |i| {
            std.debug.assert(shm_addr_alloc.map.isSet(page_index + i));
        }

        shm_addr_alloc.map.setRangeValue(.{ .start = page_index, .end = page_index + pages_len }, false);
    }
};

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
