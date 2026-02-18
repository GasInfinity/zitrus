pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub fn main(init: horizon.Init.Application.Software) !void {
    const gpa = init.app.base.gpa;
    const app = init.app;

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "All your codebase are belong to us?", .none);

        switch (try initial.start(app.app, app.apt, .app, app.srv, app.gsp)) {
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
    }, gpa);
    defer swkbd.deinit(gpa);

    const CallbackContext = struct {
        pub fn filter(_: @This(), text: [:0]const u16) Applet.Application.SoftwareKeyboard.CallbackResult {
            if (std.mem.eql(u16, text, std.unicode.utf8ToUtf16LeStringLiteral("no"))) {
                return .{ .@"continue" = .utf8("Wrong answer! :)") };
            }

            return .ok;
        }
    };

    switch (try swkbd.startContext(app.app, app.apt, .app, app.srv, app.gsp, CallbackContext{})) {
        else => |e| switch (e) {
            .left, .right => {},
            else => unreachable,
        },
    }

    {
        var initial: Applet.Application.Error = .textUtf8(.success, "Correct! Have a great day :D", .none);

        switch (try initial.start(app.app, app.apt, .app, app.srv, app.gsp)) {
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
