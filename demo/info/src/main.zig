pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub fn main(init: horizon.Init.Application.Software) !void {
    const app = init.app;
    // const gpa = app.base.gpa;
    const io = app.base.io;
    const soft = init.soft;

    // XXX: Better but still not great, networking and fs should also be separate (in initialization, not usage)
    try horizon.Io.global.initStorage(app.srv, .fs, 0);

    const test_file = try std.Io.Dir.cwd().openFile(io, "romfs:/test.txt", .{
        .mode = .read_only,
    });
    defer test_file.close(io);

    var buf: [1024]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&buf);

    var test_reader = test_file.reader(io, &.{});
    _ = try test_reader.interface.streamRemaining(&fixed);

    const cfg = try Config.open(.user, app.srv);
    defer cfg.close();

    const model = try cfg.sendGetSystemModel();

    var utf8_buf: [128]u8 = undefined;
    const name = try cfg.getConfigUser(.user_name);
    const name_written = try std.unicode.utf16LeToUtf8(&utf8_buf, &name.name);
    const language = try cfg.getConfigUser(.language);
    const birthday = try cfg.getConfigUser(.birthday);
    const country_info = try cfg.getConfigUser(.country_info);
    const region = try cfg.sendGetRegion();

    var last_elapsed: u96 = 0.0;
    main_loop: while (true) {
        const start = horizon.time.getSystemNanoseconds();

        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        const top = ScreenCtx.initBuffer(soft.current(.top, .left), Screen.top.width());
        @memset(top.framebuffer, std.mem.zeroes(Bgr888));
        @memset(soft.current(.bottom, .left), 0x00);

        var fmt_buffer: [512]u8 = undefined;
        drawString(top, 0, 0, try std.fmt.bufPrint(&fmt_buffer, "Model: {s} ({s})", .{ @tagName(model), model.description() }), .{});
        drawString(top, font_width + 1, 0, try std.fmt.bufPrint(&fmt_buffer, "Region: {s}", .{@tagName(region)}), .{});

        drawString(top, 2 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Name: {s}", .{utf8_buf[0..name_written]}), .{});
        drawString(top, 3 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Language: {s}", .{@tagName(language)}), .{});
        drawString(top, 4 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Birthday: {}/{}", .{ birthday.day, birthday.month }), .{});
        drawString(top, 5 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Country: {}/{}", .{ country_info.province_code, country_info.country_code }), .{});
        drawString(top, 6 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Last elapsed: {}", .{last_elapsed}), .{});
        drawString(top, 7 * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "Base: {} | Total: {!}", .{ std.process.getBaseAddress(), std.process.totalSystemMemory() }), .{});

        var current_line: isize = 8;

        var arg_it = environment.program_meta.argumentListIterator();

        while (arg_it.next()) |arg| {
            drawString(top, current_line * (font_width + 1), 0, arg, .{});
            current_line += 1;
        }

        current_line += 1;
        drawString(top, current_line * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "3DSX?: {}", .{environment.program_meta.is3dsx()}), .{});
        current_line += 1;
        drawString(top, current_line * (font_width + 1), 0, try std.fmt.bufPrint(&fmt_buffer, "RomFS 'test.txt': {s}", .{fixed.buffered()}), .{});

        soft.flush();
        soft.swap(.none);
        try soft.waitVBlank();

        const elapsed: u96 = horizon.time.getSystemNanoseconds() - start;
        last_elapsed = elapsed;
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

const pica = zitrus.hardware.pica;
const Screen = pica.Screen;
const Bgr888 = pica.ColorFormat.Bgr888;

const horizon = zitrus.horizon;
const environment = zitrus.horizon.environment;
const GspGpu = horizon.services.GspGpu;

const SocketUser = horizon.services.SocketUser;
const Filesystem = horizon.services.Filesystem;
const Config = horizon.services.Config;

const mango = zitrus.mango;

const zitrus = @import("zitrus");
const std = @import("std");
