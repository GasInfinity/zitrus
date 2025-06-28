pub fn main() !void {
    var srv = try ServiceManager.init("srv:");
    defer srv.deinit();

    var apt = try Applet.init(srv);
    defer apt.deinit(srv);

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
            .top = .bgr8,
            .bottom = .bgr8,
        }),
        .phys_linear_allocator = horizon.heap.linear_page_allocator,
    });
    defer framebuffer.deinit();

    const top = framebuffer.currentFramebuffer(.top);
    const bottom = framebuffer.currentFramebuffer(.bottom);

    // TODO: Continue this when the assembler is finished
    try gsp.submitGxCommand(.initMemoryFill(.{ .buffers = .{
        .{
            .slice = top,
            .value = .{ .@"32" = 0xFFFFFFFF },
        },
        .{
            .slice = bottom,
            .value = .{ .@"32" = 0xFFFFFFFF },
        },
    } }, false, false));
    _ = try gsp.waitInterrupts();

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

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Framebuffer = zitrus.gpu.Framebuffer;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
