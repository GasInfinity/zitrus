const top_screen_bitmap = @embedFile("top-screen");
const bottom_screen_bitmap = @embedFile("bottom-screen");

pub fn main() !void {
    var app: horizon.application.Software = try .init(.default, horizon.heap.linear_page_allocator);
    defer app.deinit(horizon.heap.linear_page_allocator);

    var soft: GspGpu.Graphics.Software = try .init(.{
        .top_mode = .@"2d",
        .double_buffer = .initFill(true),
        .color_format = .initFill(.bgr888),
        .initial_contents = .init(.{
            .top = top_screen_bitmap,
            .bottom = bottom_screen_bitmap,
        }),
    }, app.gsp, horizon.heap.linear_page_allocator);
    defer soft.deinit(app.gsp, horizon.heap.linear_page_allocator, app.apt_app.flags.must_close);

    main_loop: while (true) {
        while (try app.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => unreachable,
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        try soft.waitVBlank();
    }
}

const horizon = zitrus.horizon;
const GspGpu = horizon.services.GspGpu;

pub const panic = zitrus.horizon.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
