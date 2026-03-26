test "buffer to buffer" {
    const io = testing.io;

    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var test_data: [4096]u8 = undefined;
    io.random(&test_data);

    var transfer_ctx = try ctx.transfer(test_data.len);
    defer transfer_ctx.cleanup();

    try transfer_ctx.copySource(0, &test_data);
    try transfer_ctx.bufferToBuffer(0, test_data.len);

    const result = try transfer_ctx.result(0, test_data.len);
    defer transfer_ctx.cleanupResult();

    try testing.expectEqualSlices(u8, &test_data, result);
}

const htesting = horizon.testing;
const testing = std.testing;

const common = @import("common.zig");
const TmpContext = common.TmpContext;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const mango = zitrus.mango;
