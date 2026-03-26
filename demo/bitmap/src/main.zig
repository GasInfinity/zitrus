pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

const top_screen_bitmap = @embedFile("top-screen");
const bottom_screen_bitmap = @embedFile("bottom-screen");

pub const init_options: horizon.Init.Application.Software.Options = .{
    .initial_contents = .init(.{
        .top = top_screen_bitmap,
        .bottom = bottom_screen_bitmap,
    }),
};

pub fn main(init: horizon.Init.Application.Software) !void {
    const input = init.app.input;
    const soft = init.soft;

    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => unreachable,
            .quit => break :main_loop,
        };

        const pad = input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        try soft.waitVBlank();
    }
}

const horizon = zitrus.horizon;
const zitrus = @import("zitrus");
const std = @import("std");
