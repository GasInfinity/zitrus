// 3 bird images here
const bird_sheet = std.mem.bytesAsSlice(Bgr888, @embedFile("bird"));
const pipes_sheet = std.mem.bytesAsSlice(Bgr888, @embedFile("pipes"));
const ground = std.mem.bytesAsSlice(Bgr888, @embedFile("ground"));

// Firstly "Game Over", then "Flappy Bird" and then "Get Ready!"
const titles_sheet = std.mem.bytesAsSlice(Bgr888, @embedFile("titles"));

const get_ready_image_height = 92;
const flappy_bird_image_height = 89;
const game_over_image_height = 96;
const titles_image_width = 25;

const game_over_image = titles_sheet[0..(titles_image_width * game_over_image_height)];
const flappy_bird_image = titles_sheet[(titles_image_width * (game_over_image_height))..][0..(titles_image_width * flappy_bird_image_height)];
const get_ready_image = titles_sheet[(titles_image_width * (game_over_image_height + flappy_bird_image_height))..][0..(titles_image_width * get_ready_image_height)];

// All the sizes are rotated (a.k.a: width is height and viceversa)
const bird_image_size = 20;
const bird_collider_size = 12;

const pipe_sheet_width = 14;
const pipe_image_height = 26;

const ground_image_width = 10;
const ground_image_height = 12;

const sky_color = Bgr888{ .r = 111, .g = 195, .b = 205 };
const ground_color = Bgr888{ .r = 222, .g = 216, .b = 148 };
const transparent_color = Bgr888{ .r = 255, .g = 0, .b = 255 };

const full_pipe_width = 40;
const pipe_velocity = 100;
const pipe_gap = 45;

const ground_total_width = 30;

const bird_y = 60;

const Pipe = struct {
    y: f32,
    upper_size: u8,
    index: u1,
};

const GamingState = struct {
    bird_velocity: f32 = 0,
};

const GameState = union(enum) {
    get_ready,
    gaming: GamingState,
    game_over,
};

const AppState = struct {
    game: GameState = .get_ready,
    pipes: [4]Pipe = undefined,
    pipes_end: u8 = 0,
    ground_y: f32 = 0,
    bird_x: f32 = (Screen.top.width() / 2),
    current_bird_sprite: f32 = 0,
    current_bird_sprite_framerate: f32 = (1.0 / 6.0),

    pub fn update(state: *AppState, pressed: Hid.Pad.State, touch_pressed: bool, random: std.Random) void {
        switch (state.game) {
            .get_ready => {
                if (pressed.a or touch_pressed) {
                    state.game = .{ .gaming = .{} };
                }

                state.bird_x = (Screen.top.width() / 2);
            },
            .gaming => |*g| {
                if (pressed.a or touch_pressed) {
                    g.bird_velocity = 100;
                } else {
                    g.bird_velocity -= 150 * (1.0 / 60.0);
                }

                if (g.bird_velocity <= -100) {
                    g.bird_velocity = -100;
                }

                state.bird_x += g.bird_velocity * (1.0 / 60.0);

                if (state.bird_x + (bird_image_size - bird_collider_size) < ground_total_width) {
                    state.bird_x = ground_total_width - (bird_image_size - bird_collider_size);
                    state.game = .game_over;
                } else if (state.bird_x + ((bird_image_size / 2) + (bird_collider_size / 2)) >= Screen.top.width()) {
                    state.bird_x = Screen.top.width() - ((bird_image_size / 2) + (bird_collider_size / 2));
                    state.game = .game_over;
                } else {
                    // These values look very "magic" (they are) but they give the best collision experience with the pipes
                    const bird_x1 = state.bird_x + (bird_image_size - bird_collider_size);
                    const bird_x2 = bird_x1 + (bird_collider_size / 2);
                    const bird_y1 = bird_y + (bird_image_size - bird_collider_size);
                    const bird_y2 = bird_y1 + (bird_collider_size / 2);

                    for (state.pipes[0..state.pipes_end]) |pipe| {
                        const upper_start = (Screen.top.width() - pipe.upper_size);

                        const pipe_down_x1: f32 = ground_total_width;
                        const pipe_down_x2: f32 = @floatFromInt(upper_start - pipe_gap);
                        const pipe_down_y1: f32 = pipe.y;
                        const pipe_down_y2: f32 = pipe_down_y1 + pipe_sheet_width;

                        const pipe_up_x1: f32 = @floatFromInt(upper_start);
                        const pipe_up_x2: f32 = Screen.top.width();
                        const pipe_up_y1: f32 = pipe.y;
                        const pipe_up_y2: f32 = pipe_up_y1 + pipe_sheet_width;

                        if (collides(bird_x1, bird_y1, bird_x2, bird_y2, pipe_down_x1, pipe_down_y1, pipe_down_x2, pipe_down_y2) or collides(bird_x1, bird_y1, bird_x2, bird_y2, pipe_up_x1, pipe_up_y1, pipe_up_x2, pipe_up_y2)) {
                            state.game = .game_over;
                            return;
                        }
                    }
                }

                var last_pipe_y: f32 = 0;

                for (state.pipes[0..state.pipes_end]) |*pipe| {
                    pipe.y -= pipe_velocity * (1.0 / 60.0);

                    // Pipes go screen_height -> 0
                    if (pipe.y > last_pipe_y) {
                        last_pipe_y = pipe.y;
                    }
                }

                if (state.pipes_end < state.pipes.len and last_pipe_y < (Screen.top.height() / 2)) {
                    state.pipes[state.pipes_end] = Pipe{
                        .y = Screen.top.height(),
                        .upper_size = random.intRangeAtMost(u8, 25, 150),
                        .index = random.int(u1),
                    };
                    state.pipes_end += 1;
                }

                // Remove unreachable pipes
                while (true) {
                    const unreachable_pipe = unr: for (state.pipes[0..state.pipes_end], 0..) |pipe, i| {
                        if (pipe.y <= -pipe_image_height) {
                            break :unr i;
                        }
                    } else break;

                    if (unreachable_pipe < state.pipes_end - 1) {
                        std.mem.swap(Pipe, &state.pipes[unreachable_pipe], &state.pipes[state.pipes_end - 1]);
                    }

                    state.pipes_end -= 1;
                }

                state.ground_y -= pipe_velocity * (1.0 / 60.0);

                if (state.ground_y <= -ground_image_height) {
                    state.ground_y += ground_image_height;
                }

                state.current_bird_sprite += state.current_bird_sprite_framerate;

                if (state.current_bird_sprite >= 2.5) {
                    state.current_bird_sprite = 2;
                    state.current_bird_sprite_framerate *= -1;
                } else if (state.current_bird_sprite <= -0.5) {
                    state.current_bird_sprite = 0;
                    state.current_bird_sprite_framerate *= -1;
                }
            },
            .game_over => {
                if (pressed.a or touch_pressed) {
                    state.game = .get_ready;
                    state.pipes_end = 0;
                }
            },
        }
    }

    pub fn draw(state: AppState, ctx: ScreenCtx) void {
        @memset(ctx.framebuffer, sky_color);
        state.drawGround(ctx);
        state.drawPipes(ctx);
        state.drawBird(ctx);

        switch (state.game) {
            .get_ready => {
                ctx.drawSprite(.transparent_bitmap, (Screen.top.width() / 3) + (Screen.top.width() / 2), (Screen.top.height() / 2) - (get_ready_image_height / 2), titles_image_width, get_ready_image, .{ .transparent = transparent_color }, .{});
            },
            .gaming => {},
            .game_over => {
                ctx.drawSprite(.transparent_bitmap, (Screen.top.width() / 3) + (Screen.top.width() / 2), (Screen.top.height() / 2) - (game_over_image_height / 2), titles_image_width, game_over_image, .{ .transparent = transparent_color }, .{});
            },
        }
    }

    fn drawGround(state: AppState, ctx: ScreenCtx) void {
        ctx.drawRectangle(0, 0, 20, Screen.top.height(), ground_color);

        var cy: isize = @intFromFloat(@trunc(state.ground_y));

        while (cy < Screen.top.height()) : (cy += ground_image_height) {
            ctx.drawSprite(.bitmap, 20, cy, ground_image_width, ground, .{}, .{});
        }
    }

    fn drawPipes(state: AppState, ctx: ScreenCtx) void {
        for (state.pipes[0..state.pipes_end]) |pipe| {
            const pipe_image = pipes_sheet[(@as(usize, pipe.index) * (pipe_image_height * pipe_sheet_width))..][0..(pipe_image_height * pipe_sheet_width)];
            const yi: i32 = @intFromFloat(@round(pipe.y));

            const upper_start = (Screen.top.width() - pipe.upper_size);

            for (ground_total_width..(upper_start - pipe_gap)) |x| {
                ctx.drawSprite(.transparent_bitmap, @intCast(x), yi, pipe_sheet_width, pipe_image, .{
                    .transparent = transparent_color,
                }, .{ .width = 1 });
            }

            ctx.drawSprite(.transparent_bitmap, @intCast(upper_start - pipe_gap - pipe_sheet_width + 1), yi, pipe_sheet_width, pipe_image, .{
                .transparent = transparent_color,
            }, .{
                .x = 1,
                .width = pipe_sheet_width - 1,
            });

            for (upper_start..Screen.top.width()) |x| {
                ctx.drawSprite(.transparent_bitmap, @intCast(x), yi, pipe_sheet_width, pipe_image, .{
                    .transparent = transparent_color,
                }, .{
                    .width = 1,
                });
            }

            ctx.drawSprite(.transparent_bitmap, @intCast(upper_start), yi, pipe_sheet_width, pipe_image, .{
                .transparent = transparent_color,
            }, .{
                .x = 1,
                .width = pipe_sheet_width - 1,
                .flip_h = true,
            });
        }
    }

    fn drawBird(state: AppState, ctx: ScreenCtx) void {
        const pxi: i32 = @intFromFloat(@round(state.bird_x));
        const cbsi: usize = @intFromFloat(@trunc(state.current_bird_sprite));
        const bird_image = bird_sheet[((bird_image_size * bird_image_size) * cbsi)..][0..(bird_image_size * bird_image_size)];
        ctx.drawSprite(.transparent_bitmap, pxi, bird_y, bird_image_size, bird_image, .{ .transparent = transparent_color }, .{});
    }
};

pub fn main() !void {
    var app: horizon.application.Software = try .init(.default, horizon.heap.linear_page_allocator);
    defer app.deinit(horizon.heap.linear_page_allocator);

    var soft: GspGpu.Graphics.Software = try .init(.{
        .top_mode = .@"2d",
        .double_buffer = .init(.{
            .top = true,
            .bottom = false,
        }),
        .color_format = .initFill(.bgr888),
        .initial_contents = .initFill(null),
    }, app.gsp, horizon.heap.linear_page_allocator);
    defer soft.deinit(app.gsp, horizon.heap.linear_page_allocator, app.apt_app.flags.must_close);

    {
        const bottom_fb = std.mem.bytesAsSlice(Bgr888, soft.currentFramebuffer(.bottom, .left));
        @memset(bottom_fb, ground_color);

        const bottom = ScreenCtx.init(bottom_fb, Screen.bottom.width());
        bottom.drawSprite(.transparent_bitmap, 2 * (Screen.bottom.width() / 3), (Screen.bottom.height() / 2) - (flappy_bird_image_height / 2), titles_image_width, flappy_bird_image, .{ .transparent = transparent_color }, .{});
    }

    soft.flushBuffers();
    soft.swapBuffers(.none);
    try soft.waitVBlank();

    var app_state: AppState = .{};

    var rand = std.Random.DefaultPrng.init(@bitCast(horizon.getSystemTick()));
    const random = rand.random();

    var last_current: Hid.Pad.State = std.mem.zeroes(Hid.Pad.State);
    var last_pressed: bool = false;

    main_loop: while (true) {
        while (try app.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();
        const changed = pad.current.changed(last_current);
        last_current = pad.current;

        const pressed = changed.same(pad.current);

        if (pad.current.start) {
            break :main_loop;
        }

        const touch = app.input.pollTouch();
        const touch_changed = touch.pressed ^ last_pressed;
        const touch_pressed = touch.pressed and touch_changed;

        last_pressed = touch.pressed;
        const top = ScreenCtx.initBuffer(soft.currentFramebuffer(.top, .left), Screen.top.width());

        app_state.update(pressed, touch_pressed, random);
        app_state.draw(top);

        soft.flushBuffers();
        soft.swapBuffers(.none);
        try soft.waitVBlank();
    }
}

fn collides(x11: f32, y11: f32, x12: f32, y12: f32, x21: f32, y21: f32, x22: f32, y22: f32) bool {
    return !(x12 < x21 or x11 > x22 or y12 < y21 or y11 > y22);
}

const zoftblit = @import("zoftblit.zig");
const ScreenCtx = zoftblit.Context(Bgr888);

const pica = zitrus.pica;
const Screen = pica.Screen;
const Bgr888 = pica.ColorFormat.Bgr888;

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Framebuffer = GspGpu.Graphics.Framebuffer;

pub const panic = zitrus.horizon.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
