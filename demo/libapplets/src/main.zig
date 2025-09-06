pub const std_options: std.Options = .{
    .page_size_min = horizon.heap.page_size_min,
    .page_size_max = horizon.heap.page_size_max,
    .logFn = log,
    .log_level = .debug,
};

pub fn log(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const prefix = std.fmt.bufPrint(&buf, "[{s}] ({s}): ", .{ @tagName(message_level), @tagName(scope) }) catch {
        horizon.outputDebugString("fatal: logged message prefix does not fit into the buffer. message skipped!");
        return;
    };

    const message = std.fmt.bufPrint(buf[prefix.len..], format, args) catch buf[prefix.len..];
    horizon.outputDebugString(buf[0..(prefix.len + message.len)]);
}

pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    const apt = try Applet.open(srv);
    defer apt.close();

    const gsp = try GspGpu.open(srv);
    defer gsp.close();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    var gfx = try GspGpu.Graphics.init(gsp);
    defer gfx.deinit(gsp);

    var framebuffer = try Framebuffer.init(.{
        .double_buffer = .init(.{
            .top = false,
            .bottom = false,
        }),
        .color_format = .init(.{
            .top = .bgr888,
            .bottom = .bgr888,
        }),
        .phys_linear_allocator = horizon.heap.linear_page_allocator,
    });
    defer framebuffer.deinit();

    @memset(framebuffer.currentFramebuffer(.top), 0xFF);
    @memset(framebuffer.currentFramebuffer(.bottom), 0xFF);

    try framebuffer.flushBuffers(gsp);

    while (true) {
        const interrupts = try gfx.waitInterrupts();

        if (interrupts.contains(.vblank_top)) {
            break;
        }
    }

    try framebuffer.present(&gfx);

    try gsp.sendSetLcdForceBlack(false);
    defer gsp.sendSetLcdForceBlack(true) catch {};

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "All your codebase are belong to us?", .none);

        switch (try initial.start(&app, apt, srv, gsp)) {
            .none,
            .action_performed,
            => {},
            .jump_home, .jump_home_by_power, .software_reset => unreachable,
        }
    }

    var swkbd: Applet.Application.SoftwareKeyboard = try .normal(.{
        .max_length = 128,
        .buttons = &.{ .button(.utf8("Yes"), .submits), .button(.utf8("Obviously"), .submits) },
        .hint = .utf8("Don't say no!"),
        .filter = .{
            .callback = true,
        },
        .features = .{
            .predictive_input = true,
        },
        .password_mode = .none,
        .dictionary = &.{
            .word(.utf8("shrug"), .utf8("¯\\_(ツ)_/¯"), .independent),
        },
    }, horizon.heap.page_allocator);
    defer swkbd.deinit(horizon.heap.page_allocator);

    const CallbackContext = struct {
        pub fn filter(_: @This(), text: [:0]const u16) Applet.Application.SoftwareKeyboard.CallbackResult {
            if (std.mem.eql(u16, text, std.unicode.utf8ToUtf16LeStringLiteral("no"))) {
                return .{ .@"continue" = .utf8("Wrong answer! :)") };
            }

            return .ok;
        }
    };

    switch (try swkbd.startContext(&app, apt, srv, gsp, CallbackContext{})) {
        else => |e| switch (e) {
            .left, .right => {},
            else => unreachable,
        },
    }

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "Correct! Have a great day :D", .none);

        switch (try initial.start(&app, apt, srv, gsp)) {
            .none,
            .action_performed,
            => {},
            .jump_home, .jump_home_by_power, .software_reset => unreachable,
        }
    }
}

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

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
