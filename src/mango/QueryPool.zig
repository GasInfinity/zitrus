pub const Handle = enum(u32) {
    null = 0,
    _,
};

type: mango.QueryType,
statistics: mango.QueryStatistics,
/// Size of a single query in `storage`
query_size: u32,
available: std.bit_set.DynamicBitSetUnmanaged,
query_storage: []u8,

pub fn init(gpa: std.mem.Allocator, create_info: mango.QueryPoolCreateInfo) !QueryPool {
    const query_size: u32, const query_alignment: std.mem.Alignment = switch (create_info.type) {
        .timestamp => .{ @sizeOf(u64), .of(u64) },
        .statistics => .{ @sizeOf(u32) * @popCount(@as(u32, @bitCast(create_info.statistics))), .of(u32) },
        .performance_counter => @panic("TODO"),
    };

    const alignment: std.mem.Alignment = .max(.of(u32), query_alignment);
    const query_storage_size = query_size * create_info.count;
    const available_start = std.mem.alignForward(u32, query_storage_size, @alignOf(std.bit_set.DynamicBitSetUnmanaged.MaskInt));
    const available_size = std.mem.alignForward(u32, create_info.count, @bitSizeOf(u32)) / 8;
    const needed_size = available_start + available_size;

    // NOTE: make sure deinit is synced with this
    const all = (gpa.rawAlloc(needed_size, alignment, @returnAddress()) orelse return error.OutOfMemory)[0..needed_size];
    errdefer gpa.rawFree(all, alignment, @returnAddress());

    return .{
        .type = create_info.type,
        .statistics = create_info.statistics,
        .query_size = query_size,
        .available = .{
            .bit_length = create_info.count,
            .masks = @alignCast(@ptrCast(all[available_start..])), 
        },
        .query_storage = all[0..query_storage_size],
    };
}

pub fn deinit(pool: *QueryPool, gpa: std.mem.Allocator) void {
    const query_alignment: std.mem.Alignment = switch (pool.type) {
        .timestamp => .of(u64),
        .statistics => .of(u32),
        .performance_counter => @panic("TODO"),
    };

    const available_start = std.mem.alignForward(u32, pool.query_storage.len, @alignOf(std.bit_set.DynamicBitSetUnmanaged.MaskInt));
    const available_size = std.mem.alignForward(u32, pool.available.bit_length, @bitSizeOf(u32)) / 8;
    const needed_size = available_start + available_size;
    const all = pool.query_storage.ptr[0..needed_size];
    gpa.rawFree(all, .max(.of(u32), query_alignment), @returnAddress());
}

// NOTE: why are timestamps 64 bits instead of 96? because we want this to be compatible 
// with C and C is unfortunately not based.
pub fn writeTimestamp(pool: *QueryPool, query: u32, timestamp: u64) void {
    std.debug.assert(pool.type == .timestamp);
    std.debug.assert(pool.query_size == @sizeOf(u64));
    std.debug.assert(query < @divExact(pool.query_storage.len, @sizeOf(u64)));
    std.debug.assert(!pool.available.isSet(query)); // The query must not be available
    
    const stored = pool.query_storage[query * @sizeOf(u64)..][0..@sizeOf(u64)];
    stored.* = @bitCast(timestamp);
    pool.available.set(query);
}

pub fn reset(pool: *QueryPool, first: u32, count: u32) void {
    std.debug.assert(first + count <= @divExact(pool.query_storage.len, pool.query_size));

    @memset(pool.query_storage[(first * pool.query_size)..][0..(count * pool.query_size)], undefined);
    pool.available.setRangeValue(.{
        .start = first,
        .end = first + count,
    }, false);
}

pub fn getResults(pool: *QueryPool, first: u32, count: u32, data: []u8, stride: u32, flags: mango.QueryResultFlags) mango.GetQueryResultsError!void {
    _ = flags;
    std.debug.assert(first + count <= @divExact(pool.query_storage.len, pool.query_size));
    if (count > 0) std.debug.assert(stride != 0);

    var any_unavailable: bool = false;

    for (0..count) |i| {
        const available = pool.available.isSet(first + i);
        if (available) @memcpy(data[stride * i..][0..pool.query_size], pool.query_storage[(first + i) * pool.query_size..][0..pool.query_size]);
        any_unavailable |= !available;
    }

    return if (any_unavailable) error.NotReady;
}

pub fn toHandle(image: *QueryPool) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *QueryPool {
    return @as(*QueryPool, @ptrFromInt(@intFromEnum(handle)));
}

const QueryPool = @This();

const std = @import("std");

const zitrus = @import("zitrus");
const mango = zitrus.mango;
