test "only color smoke test (full-screen white quad)" {
    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var render_ctx = try ctx.render(64, 64, .a8b8g8r8_unorm, .undefined);
    defer render_ctx.cleanup();
    
    try render_ctx.beginDefaultState();
    render_ctx.drawQuad();
    try render_ctx.endSubmit();

    const actual: []const [4]u8 = @ptrCast(try render_ctx.result(false));
    defer render_ctx.cleanupResult();

    try testing.expect(std.mem.allEqual(u8, @ptrCast(actual), 0xFF));
}

test "only depth smoke test (full-screen near quad)" {
    if (true) return error.SkipZigTest; // XXX: always crashes on azahar, passes on hardware

    var ctx: TmpContext = try .init();
    defer ctx.cleanup();

    var render_ctx = try ctx.render(64, 64, .undefined, .d16_unorm);
    defer render_ctx.cleanup();
    
    try render_ctx.beginDefaultState();
    // depth write already enabled in beginDefaultState
    render_ctx.cmd.setDepthTestEnable(true);
    render_ctx.drawQuad();
    try render_ctx.endSubmit();

    const actual = try render_ctx.result(true);
    defer render_ctx.cleanupResult();

    try testing.expect(std.mem.allEqual(u8, actual, 0x00));
}

const htesting = horizon.testing;
const testing = std.testing;

const common = @import("common.zig");
const TmpContext = common.TmpContext;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const mango = zitrus.mango;
