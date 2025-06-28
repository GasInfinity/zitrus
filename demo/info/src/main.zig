pub fn main() !void {
    var srv = try ServiceManager.init("srv:");
    defer srv.deinit();

    var apt = try Applet.init(srv);
    defer apt.deinit(srv);

    var hid = try Hid.init(srv);
    defer hid.deinit();

    var gsp = try GspGpu.init(srv);
    defer gsp.deinit();

    var cfg = try Config.init(srv);
    defer cfg.deinit();

    var framebuffer = try Framebuffer.init(.{
        .double_buffer = .init(.{
            .top = false,
            .bottom = false,
        }),
        .color_format = .init(.{
            .top = .bgr8,
            .bottom = .bgr8,
        }),
        .phys_linear_allocator = horizon.heap.linear_page_allocator,
    });
    defer framebuffer.deinit();

    const top = ScreenCtx.initBuffer(framebuffer.currentFramebuffer(.top), Screen.top.width());
    @memset(top.framebuffer, std.mem.zeroes(Bgr8));

    const bottom = ScreenCtx.initBuffer(framebuffer.currentFramebuffer(.bottom), Screen.bottom.width());
    @memset(bottom.framebuffer, std.mem.zeroes(Bgr8));

    const model = try cfg.sendGetSystemModel();
    var fmt_buffer: [512]u8 = undefined;
    drawString(top, 0, 0, try std.fmt.bufPrint(&fmt_buffer, "Model: {s} ({s})", .{ @tagName(model), model.description() }), .{});
    drawString(top, font_width + 1, 0, try std.fmt.bufPrint(&fmt_buffer, "Region: {s}", .{@tagName(try cfg.sendGetRegion())}), .{});

    var utf8_buf: [128]u8 = undefined;
    const name = try cfg.getConfigU(.user_name);
    const name_written = try std.unicode.utf16LeToUtf8(&utf8_buf, &name.name);
    drawString(top, 2 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Name: {s}", .{utf8_buf[0..name_written]}), .{});

    const language = try cfg.getConfigU(.language);
    drawString(top, 3 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Language: {s}", .{@tagName(language)}), .{});

    const birthday = try cfg.getConfigU(.birthday);
    drawString(top, 4 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Birthday: {}/{}", .{ birthday.day, birthday.month }), .{});

    const country_info = try cfg.getConfigU(.country_info);
    drawString(top, 5 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Country: {}/{}", .{ country_info.province_code, country_info.country_code }), .{});

    try framebuffer.flushBuffers(&gsp);
    try framebuffer.present(&gsp);

    // TODO: This is currently not that great...
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.contains(.vblank_top)) {
            break;
        }
    }

    try gsp.sendSetLcdForceBlack(false);
    defer if (gsp.has_right) gsp.sendSetLcdForceBlack(true) catch {};

    var running = true;
    while (running) {
        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => running = false,
            else => {},
        };

        while (try apt.pollEvent(srv, &gsp)) |e| switch (e) {
            else => {},
        };

        const input = hid.readPadInput();

        if (input.current.start) {
            break;
        }

        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.contains(.vblank_top)) {
                break;
            }
        }

        running = running and !apt.flags.should_close;
    }
}

const StringDrawingOptions = struct { wrap: bool = false };

fn drawString(ctx: ScreenCtx, x: isize, y: isize, string: []const u8, options: StringDrawingOptions) void {
    const ctx_height = @divExact(ctx.framebuffer.len, ctx.width);
    var cx: isize = x;
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

const white_color = Bgr8{ .r = 255, .g = 255, .b = 255 };
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
const ScreenCtx = zoftblit.Context(Bgr8);

const gpu = zitrus.gpu;
const Screen = gpu.Screen;
const Bgr8 = gpu.ColorFormat.Bgr8;

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Config = horizon.services.Config;
const Framebuffer = zitrus.gpu.Framebuffer;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
