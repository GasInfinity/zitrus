const top_screen_bitmap = @embedFile("top-screen");
const bottom_screen_bitmap = @embedFile("bottom-screen");

pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    var apt = try Applet.init(srv);
    defer apt.deinit();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    var hid = try Hid.init(srv);
    defer hid.deinit();

    var gsp = try GspGpu.init(srv);
    defer gsp.deinit();

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

    const top_fb = framebuffer.currentFramebuffer(.top);
    const bottom_fb = framebuffer.currentFramebuffer(.bottom);
    @memcpy(top_fb, top_screen_bitmap);
    @memcpy(bottom_fb, bottom_screen_bitmap);

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

    main_loop: while (true) {
        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => break :main_loop,
            else => {},
        };

        while (try app.pollNotification(apt, srv)) |n| switch (n) {
            .jump_home, .jump_home_by_power => {
                j_h: switch (try app.jumpToHome(apt, srv, &gsp, .none)) {
                    .resumed => {},
                    .jump_home => continue :j_h (try app.jumpToHome(apt, srv, &gsp, .none)),
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

        const input = hid.readPadInput();

        if (input.current.start) {
            break :main_loop;
        }

        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.contains(.vblank_top)) {
                break;
            }
        }
    }
}

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Framebuffer = zitrus.pica.Framebuffer;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
