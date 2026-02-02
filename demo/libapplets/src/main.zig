pub const os = horizon;
pub const debug = horizon.debug;
pub const panic = std.debug.FullPanic(debug.defaultPanic);
pub const std_options: std.Options = horizon.default_std_options;

pub const std_options_debug_io: std.Io = horizon.Io.failing;
comptime { _ = horizon.start; }

pub fn main() !void {
    var app: horizon.application.Software = try .init(.default, horizon.heap.linear_page_allocator);
    defer app.deinit(horizon.heap.linear_page_allocator);

    var soft: GspGpu.Graphics.Software = try .init(.{
        .top_mode = .@"2d",
        .double_buffer = .initFill(true),
        .color_format = .initFill(.bgr888),
        .initial_contents = .initFill(null),
    }, app.gsp, horizon.heap.linear_page_allocator);
    defer soft.deinit(app.gsp, horizon.heap.linear_page_allocator, app.apt_app.flags.must_close);

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "All your codebase are belong to us?", .none);

        switch (try initial.start(&app.apt_app, app.apt, .app, app.srv, app.gsp)) {
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

    switch (try swkbd.startContext(&app.apt_app, app.apt, .app, app.srv, app.gsp, CallbackContext{})) {
        else => |e| switch (e) {
            .left, .right => {},
            else => unreachable,
        },
    }

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "Correct! Have a great day :D", .none);

        switch (try initial.start(&app.apt_app, app.apt, .app, app.srv, app.gsp)) {
            .none,
            .action_performed,
            => {},
            .jump_home, .jump_home_by_power, .software_reset => unreachable,
        }
    }
}

const pica = zitrus.hardware.pica;
const Screen = pica.Screen;
const Bgr888 = pica.ColorFormat.Bgr888;

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Config = horizon.services.Config;
const Framebuffer = GspGpu.Graphics.Framebuffer;

const zitrus = @import("zitrus");
const std = @import("std");
