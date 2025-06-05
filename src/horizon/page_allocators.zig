pub const linear_page_allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = linearAlloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = linearFree,
    },
};

// XXX: This currently works but we can maybe use a buddy allocator?
pub const SharedMemoryAddressAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(4096), (horizon.memory.shared_memory_end - horizon.memory.shared_memory_begin));

pub fn sharedMemoryAddressAllocator() SharedMemoryAddressAllocator {
    return .init(@ptrFromInt(horizon.memory.shared_memory_begin));
}

pub const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(4096), zitrus.memory.vram_bank_size);

pub fn vramBankAllocator(bank: memory.VRamBank) VRamBankAllocator {
    return VRamBankAllocator.init(@ptrFromInt(horizon.memory.vram_memory_begin + (@intFromEnum(bank) * memory.vram_bank_size)));
}

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

const std = @import("std");
const zalloc = @import("zalloc");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const memory = zitrus.memory;
