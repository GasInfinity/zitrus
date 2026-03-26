const filled_u16_pattern: u16 = 0xDEAD;
const filled_u24_pattern: u24 = 0xDEADBF;
const filled_u24_pattern_bytes: [3]u8 = .{0xBF, 0xAD, 0xDE};
const filled_u32_pattern: u32 = 0xDEADBEEF;

test "fill buffer u16" {
    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var fill_ctx = try ctx.fill(4096);
    defer fill_ctx.cleanup();

    try fill_ctx.fillBuffer(0, 4096, .u16, filled_u16_pattern);
    
    const result: []const u16 = @alignCast(@ptrCast(try fill_ctx.result(0, 4096)));
    defer fill_ctx.cleanupResult();

    try testing.expectEqualSlices(u16, &@as([4096 / @sizeOf(u16)]u16, @splat(filled_u16_pattern)), result);
}

test "fill buffer u24" {
    // 4096 / 3 is not a whole integer
    const size = 4096 * 3;

    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var fill_ctx = try ctx.fill(size);
    defer fill_ctx.cleanup();

    try fill_ctx.fillBuffer(0, size, .u24, filled_u24_pattern);
    
    // NOTE: we need to compare [3]u8 as an u24 is stored in separate words within an array.
    const result: []const [3]u8 = @alignCast(@ptrCast(try fill_ctx.result(0, size)));
    defer fill_ctx.cleanupResult();

    try testing.expectEqualSlices([3]u8, &@as([4096][3]u8, @splat(filled_u24_pattern_bytes)), result);
}

test "fill buffer u32" {
    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var fill_ctx = try ctx.fill(4096);
    defer fill_ctx.cleanup();

    try fill_ctx.fillBuffer(0, 4096, .u32, filled_u32_pattern);
    
    const result: []const u32 = @alignCast(@ptrCast(try fill_ctx.result(0, 4096)));
    defer fill_ctx.cleanupResult();

    try testing.expectEqualSlices(u32, &@as([4096 / @sizeOf(u32)]u32, @splat(filled_u32_pattern)), result);
}

const htesting = horizon.testing;
const testing = std.testing;

const common = @import("common.zig");
const TmpContext = common.TmpContext;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const mango = zitrus.mango;
