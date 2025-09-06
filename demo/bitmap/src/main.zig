const top_screen_bitmap = @embedFile("top-screen");
const bottom_screen_bitmap = @embedFile("bottom-screen");

pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    const apt = try Applet.open(srv);
    defer apt.close();

    const hid = try Hid.open(srv);
    defer hid.close();

    const gsp = try GspGpu.open(srv);
    defer gsp.close();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    var input = try Hid.Input.init(hid);
    defer input.deinit();

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

    const top_fb = framebuffer.currentFramebuffer(.top);
    const bottom_fb = framebuffer.currentFramebuffer(.bottom);
    @memcpy(top_fb, top_screen_bitmap);
    @memcpy(bottom_fb, bottom_screen_bitmap);

    try framebuffer.flushBuffers(gsp);

    // You must do this if you use the raw Graphics abstraction!
    while (true) {
        const interrupts = try gfx.waitInterrupts();

        if (interrupts.contains(.vblank_top)) {
            break;
        }
    }

    try framebuffer.present(&gfx);

    try gsp.sendSetLcdForceBlack(false);
    defer gsp.sendSetLcdForceBlack(true) catch {};

    main_loop: while (true) {
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

        while (true) {
            const interrupts = try gfx.waitInterrupts();

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
const Framebuffer = GspGpu.Graphics.Framebuffer;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
