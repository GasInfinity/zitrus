pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    const apt = try Applet.open(srv);
    defer apt.close();

    const hid = try Hid.open(srv);
    defer hid.close();

    const gsp = try GspGpu.open(srv);
    defer gsp.close();

    const cfg = try Config.open(srv);
    defer cfg.close();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    var input = try Hid.Input.init(hid);
    defer input.deinit();

    var gfx = try GspGpu.Graphics.init(gsp);
    defer gfx.deinit(gsp);

    var top_framebuffer = try Framebuffer.init(.{ .screen = .top, .double_buffer = true }, horizon.heap.linear_page_allocator);
    defer top_framebuffer.deinit(horizon.heap.linear_page_allocator);

    var bottom_framebuffer = try Framebuffer.init(.{ .screen = .bottom }, horizon.heap.linear_page_allocator);
    defer bottom_framebuffer.deinit(horizon.heap.linear_page_allocator);

    {
        const top = ScreenCtx.initBuffer(top_framebuffer.currentFramebuffer(.left), Screen.top.width());
        @memset(top.framebuffer, std.mem.zeroes(Bgr888));

        const bottom = ScreenCtx.initBuffer(bottom_framebuffer.currentFramebuffer(.left), Screen.bottom.width());
        @memset(bottom.framebuffer, std.mem.zeroes(Bgr888));
    }

    const model = try cfg.sendGetSystemModel();

    var utf8_buf: [128]u8 = undefined;
    const name = try cfg.getConfigUser(.user_name);
    const name_written = try std.unicode.utf16LeToUtf8(&utf8_buf, &name.name);
    const language = try cfg.getConfigUser(.language);
    const birthday = try cfg.getConfigUser(.birthday);
    const country_info = try cfg.getConfigUser(.country_info);

    try top_framebuffer.flushBuffer(gsp);
    try bottom_framebuffer.flushBuffer(gsp);

    // TODO: This is currently not that great...
    while (true) {
        const interrupts = try gfx.waitInterrupts();

        if (interrupts.contains(.vblank_top)) {
            break;
        }
    }

    try top_framebuffer.swapBuffer(&gfx, .none);
    try bottom_framebuffer.present(&gfx, .none);

    try gsp.sendSetLcdForceBlack(false);
    defer gsp.sendSetLcdForceBlack(true) catch {};

    var last_elapsed: f32 = 0.0;
    main_loop: while (true) {
        const start = horizon.getSystemTick();

        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => break :main_loop,
            else => {},
        };

        while (try app.pollNotification(apt, srv)) |n| switch (n) {
            .jump_home, .jump_home_by_power => {
                j_h: switch (try app.jumpToHome(apt, srv, gsp, .none)) {
                    .resumed => {},
                    .jump_home => continue :j_h (try app.jumpToHome(apt, srv, gsp, .none)),
                    .must_close => break :main_loop,
                }
            },
            .sleeping => {
                while (try app.waitNotification(apt, srv) != .sleep_wakeup) {}
                try gsp.sendSetLcdForceBlack(false);
            },
            .must_close, .must_close_by_shutdown => break :main_loop,
            .jump_home_rejected => {},
            else => {},
        };

        const pad = input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        const top = ScreenCtx.initBuffer(top_framebuffer.currentFramebuffer(.left), Screen.top.width());
        @memset(top.framebuffer, std.mem.zeroes(Bgr888));

        var fmt_buffer: [512]u8 = undefined;
        drawString(top, 0, 0, try std.fmt.bufPrint(&fmt_buffer, "Model: {s} ({s})", .{ @tagName(model), model.description() }), .{});
        drawString(top, font_width + 1, 0, try std.fmt.bufPrint(&fmt_buffer, "Region: {s}", .{@tagName(try cfg.sendGetRegion())}), .{});

        drawString(top, 2 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Name: {s}", .{utf8_buf[0..name_written]}), .{});
        drawString(top, 3 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Language: {s}", .{@tagName(language)}), .{});
        drawString(top, 4 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Birthday: {}/{}", .{ birthday.day, birthday.month }), .{});
        drawString(top, 5 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Country: {}/{}", .{ country_info.province_code, country_info.country_code }), .{});
        drawString(top, 6 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Last elapsed: {}", .{last_elapsed}), .{});

        try top_framebuffer.flushBuffer(gsp);
        try bottom_framebuffer.flushBuffer(gsp);

        while (true) {
            const interrupts = try gfx.waitInterrupts();

            if (interrupts.contains(.vblank_top)) {
                break;
            }
        }
        try top_framebuffer.swapBuffer(&gfx, .none);
        try bottom_framebuffer.present(&gfx, .none);

        const elapsed_ticks: f32 = @floatFromInt(horizon.getSystemTick() - start);
        last_elapsed = (elapsed_ticks / 268111856.0);
    }
}

const StringDrawingOptions = struct { wrap: bool = false };

fn drawString(ctx: ScreenCtx, x: isize, y: isize, string: []const u8, options: StringDrawingOptions) void {
    const ctx_height = @divExact(ctx.framebuffer.len, ctx.width);
    const ctx_width_i: isize = @intCast(ctx.width);
    var cx: isize = (ctx_width_i - font_width) - x;
    var cy: isize = y;

    var i: usize = 0;
    while (i < string.len and cx >= 0) : (i += 1) {
        if (string[i] == '\n') {
            cx -= font_width + 1;
            cy = y;
            continue;
        }

        drawCharacter(ctx, cx, cy, string[i]);
        cy += font_height + 1;

        if (cy >= (ctx_height - font_width)) {
            if (!options.wrap) {
                break;
            }

            cx -= font_width + 1;
            cy = y;
        }
    }
}

// Same positions as in the ASCII table, but missing lowercase characters
// Simple 6x8 font cooked in 1h
const bitmap_font = @embedFile("6x8-font");

// Sprites are rotated!
const font_height = 6;
const font_width = 8;
const bit_font = bit: {
    @setEvalBranchQuota(bitmap_font.len * 2);
    var buffer: [@divExact(bitmap_font.len, 8)]u8 = @splat(0);

    var offset = 0;
    for (&buffer) |*v| {
        for (0..@bitSizeOf(u8)) |i| {
            v.* |= ((if (bitmap_font[offset] == 255) 1 else 0) << i);
            offset += 1;
        }
    }

    break :bit buffer;
};

const white_color = Bgr888{ .r = 255, .g = 255, .b = 255 };
fn drawCharacter(ctx: ScreenCtx, x: isize, y: isize, character: u8) void {
    const offset: ?usize = of: switch (character) {
        0...32, 127 => null,
        33...96 => |c| (c - 33),
        97...122 => |c| continue :of std.ascii.toUpper(c),
        123...126 => |c| (c - 59),

        // No extended character set
        else => null,
    };

    if (offset) |off| {
        ctx.drawSprite(.bit, x, y, u8, &bit_font, .{ .on = white_color }, .{
            .y = font_height * off,
            .height = font_height,
        });
    }
}

const zoftblit = @import("zoftblit.zig");
const ScreenCtx = zoftblit.Context(Bgr888);

const pica = zitrus.pica;
const Screen = pica.Screen;
const Bgr888 = pica.ColorFormat.Bgr888;

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Config = horizon.services.Config;
const Framebuffer = GspGpu.Graphics.Framebuffer;

const mango = zitrus.mango;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
