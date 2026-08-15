pub const granularity = 4096;
pub const min_alignment: std.mem.Alignment = .fromByteUnits(granularity);
pub const size = zitrus.memory.vram_bank_size;
pub const bit_length = @divExact(size, granularity);

const BitSet = std.StaticBitSet(bit_length);
const Index = std.math.IntFittingRange(0, bit_length);

buffer: *align(4096) [size]u8,
map: BitSet,
last_allocated_hint: Index,

pub fn init(buffer: *align(4096) [size]u8) BankAllocator {
    return .{
        .buffer = buffer, 
        .map = .empty,
        .last_allocated_hint = 0,
    };
}

pub fn ownsPtr(ba: BankAllocator, ptr: [*]const u8) bool {
    return @intFromPtr(ptr) >= @intFromPtr(ba.buffer.ptr) and @intFromPtr(ptr) < (@intFromPtr(ba.buffer.ptr) + size);
}

pub fn alloc(ba: *BankAllocator, n: usize) error{OutOfMemory}![]align(granularity) u8 {
    const aligned_len = min_alignment.forward(n);
    const blocks_len = @divExact(aligned_len, granularity);

    if (blocks_len > bit_length) return error.OutOfMemory;

    const map = &ba.map;
    const last_allocated = ba.last_allocated_hint;

    const found_end = ps: {
        var rescan: bool = false;
        var current_scanned_block = last_allocated;
        var sequential_blocks_found: Index = 0;

        while (true) {
            if (current_scanned_block == bit_length) {
                if (rescan) return error.OutOfMemory; // We already wrapped around and found nothing

                sequential_blocks_found = 0;
                current_scanned_block = 0;
                rescan = true;
            }

            if (!map.isSet(current_scanned_block)) {
                sequential_blocks_found += 1;

                if (sequential_blocks_found >= blocks_len) break :ps current_scanned_block;
            } else sequential_blocks_found = 0;

            current_scanned_block += 1;
        } else unreachable; // Either we find or we're out of memory
    };

    const map_end = @as(usize, found_end) + 1;
    const map_start: usize = map_end - blocks_len;

    ba.last_allocated_hint = @truncate(map_end);
    map.setRangeValue(.{ .start = map_start, .end = map_end }, true);

    const buffer = ba.buffer[(map_start * granularity)..][0..aligned_len];
    if (trace) log.debug("alloc 0x{X:0>8} (index {d}-{d}), {d} pages", .{@intFromPtr(buffer.ptr), map_start, found_end, blocks_len});

    return @alignCast(buffer);
}

pub fn free(bmp: *BankAllocator, buffer: []const u8) void {
    if (buffer.len == 0) return;
    std.debug.assert(bmp.ownsPtr(buffer.ptr));

    const ptr = @intFromPtr(buffer.ptr);
    const aligned_len = min_alignment.forward(buffer.len);
    const block_index = @divExact((ptr - @intFromPtr(bmp.buffer.ptr)), granularity);
    const blocks_len = @divExact(aligned_len, granularity);

    if (trace) log.debug("free 0x{X:0>8} (index {d}-{d}), {d} pages", .{ptr, block_index, block_index + blocks_len - 1, blocks_len});

    // Sanity check (double free / corrupted bitmap)
    for (0..blocks_len) |i| std.debug.assert(bmp.map.isSet(block_index + i));
    bmp.map.setRangeValue(.{ .start = block_index, .end = block_index + blocks_len }, false);
}

test {
    var ba: BankAllocator = .init(@ptrFromInt(0x1000));

    ba.free(try ba.alloc(2048));
    ba.free(try ba.alloc(4096));
    ba.free(try ba.alloc(8192));
    ba.free(try ba.alloc(16384));
    ba.free(try ba.alloc(32768));
    ba.free(try ba.alloc(65536));
    ba.free(try ba.alloc(131072));
    ba.free(try ba.alloc(262144));
    ba.free(try ba.alloc(524280));
    ba.free(try ba.alloc(1048560));
    ba.free(try ba.alloc(2097120));
    ba.free(try ba.alloc(3145728));
}

const trace = true;
const BankAllocator = @This();

const log = std.log.scoped(.bank_allocator);
const std = @import("std");
const zitrus = @import("zitrus");
