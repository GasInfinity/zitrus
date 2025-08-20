// XXX: This is not that great, the hardware can do MUCH more (coherent memory and persistently mapped buffers, hi?).
// We could store one physical address only and map it but the kernel doesnt support that :(((

pub const Handle = enum(u64) {
    null = 0,
    _,
};

pub const MemoryHeap = enum(u2) {
    fcram,
    vram_a,
    vram_b,
};

pub const Data = packed struct(u64) {
    valid: bool = true,
    virtual_page_shifted: u20,
    physical_page_shifted: u20,
    size_page_shifted: u20,
    heap: MemoryHeap,
    _: u1 = 0,

    pub fn init(virtual: [*]u8, physical: PhysicalAddress, memory_size: usize, heap: MemoryHeap) Data {
        std.debug.assert(std.mem.isAligned(@intFromPtr(virtual), 4096));
        std.debug.assert(std.mem.isAligned(@intFromEnum(physical), 4096));
        std.debug.assert(std.mem.isAligned(memory_size, 4096));

        return .{
            .virtual_page_shifted = @intCast(@intFromPtr(virtual) >> 12),
            .physical_page_shifted = @intCast(@intFromEnum(physical) >> 12),
            .size_page_shifted = @intCast(memory_size >> 12),
            .heap = heap,
        };
    }

    pub fn size(data: Data) usize {
        return @as(u32, data.size_page_shifted) << 12;
    }
};

pub const BoundMemoryInfo = packed struct(u64) {
    pub const empty: BoundMemoryInfo = .{ .virtual_page_shifted = 0, .physical_page_shifted = 0, .byte_offset = 0 };

    virtual_page_shifted: u20,
    physical_page_shifted: u20,
    byte_offset: u12,
    _: u12 = 0,

    pub fn init(device_memory: DeviceMemory, offset: u32) BoundMemoryInfo {
        const page_offset: u20 = @intCast(offset >> 12);
        const byte_offset: u12 = @intCast(offset & 0xFFF);

        return .{
            .virtual_page_shifted = device_memory.data.virtual_page_shifted + page_offset,
            .physical_page_shifted = device_memory.data.physical_page_shifted + page_offset,
            .byte_offset = byte_offset,
        };
    }

    pub fn boundVirtualAddress(info: BoundMemoryInfo) [*]u8 {
        return @ptrFromInt((@as(u32, info.virtual_page_shifted) << 12) + info.byte_offset);
    }

    pub fn boundPhysicalAddress(info: BoundMemoryInfo) zitrus.PhysicalAddress {
        return .fromAddress((@as(u32, info.physical_page_shifted) << 12) + info.byte_offset);
    }

    pub fn isUnbound(info: BoundMemoryInfo) bool {
        return info.virtual_page_shifted == info.physical_page_shifted and info.virtual_page_shifted == 0;
    }
};

data: Data,

pub fn virtualAddress(memory: DeviceMemory) [*]u8 {
    return @ptrFromInt((@as(u32, memory.data.virtual_page_shifted) << 12));
}

pub fn physicalAddress(memory: DeviceMemory) zitrus.PhysicalAddress {
    return .fromAddress((@as(u32, memory.data.physical_page_shifted) << 12));
}

pub fn size(memory: DeviceMemory) u32 {
    return memory.data.size();
}

pub fn toHandle(memory: DeviceMemory) Handle {
    return @enumFromInt(@as(u64, @bitCast(memory.data)));
}

pub fn fromHandle(handle: Handle) DeviceMemory {
    // TODO: With runtime safety the handle is a real pointer with some metadata
    return .{
        .data = @bitCast(@intFromEnum(handle)),
    };
}

const DeviceMemory = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
