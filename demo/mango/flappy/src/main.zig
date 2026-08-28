const basic_vtx_storage align(@sizeOf(u32)) = @embedFile("basic.psh").*;
const basic_vtx = &basic_vtx_storage;

pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub const Vertex = struct {
    pos: [2]f32,
    col: [4]u8,
};

pub fn main(init: horizon.Init.Application.Mango) !void {
    const io = init.app.base.io;
    const device: mango.Device = init.device;

    var state: State = try .init(device, false);
    defer state.deinit(device);

    var top: [2]Framebuffer = @splat(.empty);
    defer for (&top) |*fb| fb.deinit(device);
    for (&top) |*fb| fb.* = try .init(device, 240, 400, .b8g8r8_unorm, .undefined);
    defer device.waitIdle(); // Wait for any operation in-progress

    var batcher: [2]Batcher = @splat(.empty);
    defer for (&batcher) |*bat| bat.deinit(state.fcram);

    const simple_shader = try device.createShader(.init(.psh, basic_vtx, "main"));
    defer device.destroyShader(simple_shader);

    const vertex_input_layout = try device.createVertexInputLayout(.init(&.{
        .{ .stride = @sizeOf(Vertex) },
    }, &.{
        .{
            .location = .v0,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .location = .v1,
            .binding = .@"0",
            .format = .r8g8b8a8_uscaled,
            .offset = @offsetOf(Vertex, "col"),
        },
    }, &.{}));
    defer device.destroyVertexInputLayout(vertex_input_layout);

    const input = init.app.input;

    var last_elapsed: std.Io.Duration = .zero;
    var dt: f32 = 0;
    var time: f32 = 0;
    var last: std.Io.Timestamp = .now(io, .boot);

    var prng: std.Random.DefaultPrng = .init(@as(u64, @truncate(@as(u96, @bitCast(last.nanoseconds)))));
    var last_current: horizon.services.Hid.Pad.State = std.mem.zeroes(horizon.services.Hid.Pad.State);

    var app: AppState = .{};

    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        time += dt;
        const pad = input.pollPad();
        if (pad.current.start) break :main_loop;

        const changed = pad.current.changed(last_current);
        last_current = pad.current;

        const pressed = changed.same(pad.current);
        app.update(dt, pressed, false, prng.random());

        const cmd = try state.acquireNext(device);
        const ctop = &top[state.current];
        const bat = &batcher[state.current];
        bat.reset();

        try bat.ensureQuads(state.fcram, 256); // More than enough
        app.draw(bat);
        try bat.flush(device);

        try cmd.begin();
        cmd.bindShaders(&.{.vertex}, &.{simple_shader});
        cmd.setVertexInput(vertex_input_layout);
        cmd.setLightingEnable(false);
        cmd.setLogicOpEnable(false);
        cmd.setAlphaTestEnable(false);
        cmd.setDepthTestEnable(false);
        cmd.setStencilTestEnable(false);
        cmd.setCullMode(.none);
        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setColorWriteMask(.rgba);
        cmd.setBlendEquation(.{
            .src_color_factor = .one,
            .dst_color_factor = .zero,
            .color_op = .add,
            .src_alpha_factor = .one,
            .dst_alpha_factor = .zero,
            .alpha_op = .add,
        });
        cmd.setTextureCombinersEffect(.none);
        cmd.setTextureCombiners(5, &.{.{
            .color_src = @splat(.primary_color),
            .alpha_src = @splat(.primary_color),
            .color_factor = @splat(.src_color),
            .alpha_factor = @splat(.src_alpha),
            .color_op = .modulate,
            .alpha_op = .replace,

            .color_scale = .@"1x",
            .alpha_scale = .@"1x",

            .constant = @splat(0),
        }});

        // Render to the top screen
        cmd.setViewport(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 400 } });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 400 } }));

        {
            cmd.beginRendering(.{
                .color_attachment = ctop.color.view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const proj = zmath.mat.orthoRotate90Cw(.left, 0, 0, 400, 240, 0, 1000);
            cmd.bindFloatUniforms(.vertex, 0, &proj);

            cmd.bindVertexBuffers(0, &.{bat.vertices_gpu});
            cmd.bindIndexBuffer(bat.indices_gpu, .u16);
            cmd.drawIndexed(bat.indices.items.len, 0, 0);
        }

        try cmd.end();
        
        const top_idx = try device.acquireNextImage(.top, std.math.maxInt(u64));
        const bottom_idx = try device.acquireNextImage(.bottom, std.math.maxInt(u64));

        try device.present(&.init(state.sema, state.sync), &.{
            .display = .bottom,
            .image_index = bottom_idx,
            .flags = .{},
        });

        try device.clearColorImage(&.init(state.sema, state.sync), &.init(state.sema, state.sync + 1), &.{
            .subresource_range = .full,
            .image = ctop.color.image,
            .color = @splat(0x22),
        });
        state.sync += 1;
        
        try device.submit(&.init(state.sema, state.sync), &.init(state.sema, state.sync + 1), &.{ .command_buffer = state.cmd[state.current] });
        state.sync += 1;

        try device.blitImage(&.init(state.sema, state.sync), &.init(state.sema, state.sync + 1), &.{
            .src_image = ctop.color.image,
            .dst_image = state.top_images[top_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
        });
        state.sync += 1;
        state.syncNext();

        try device.present(&.init(state.sema, state.sync), &.{
            .display = .top,
            .image_index = top_idx,
            .flags = .{},
        });

        const current: std.Io.Timestamp = .now(io, .boot);
        last_elapsed = last.durationTo(current);
        dt = @as(f32, @floatFromInt(last_elapsed.nanoseconds)) / std.time.ns_per_s;
        last = current;
    }
}

fn drawRect(bat: *Batcher, pos: [2]f32, size: [2]f32, color: [4]u8) void {
    const vertices = bat.addQuadAssumeCapacity();
    vertices[0] = .{ .pos = pos, .col = color };
    vertices[1] = .{ .pos = .{pos[0], pos[1]+size[1]}, .col = color };
    vertices[2] = .{ .pos = .{pos[0]+size[0], pos[1]+size[1]}, .col = color };
    vertices[3] = .{ .pos = .{pos[0]+size[0], pos[1]}, .col = color };
}

const full_pipe_width = 40;
const pipe_velocity = 100;
const pipe_gap = 75;
const pipe_width = 26;

const ground_total_height = 30;
const ground_width = 10;

const bird_size = 20;
const bird_collider_size = 12;
const bird_x = 60;

const Pipes = struct {
    x: f32,
    upper_pipe_size: u8,
    color_index: u1,
};

const GameState = union(enum) {
    const Gaming = struct {
        bird_velocity: f32 = 0,
    };

    get_ready,
    gaming: Gaming,
    game_over,
};

const AppState = struct {
    game: GameState = .get_ready,
    pipe_storage: [4]Pipes = undefined,
    pipes: u8 = 0,
    current_ground_x: f32 = 0,
    bird_y: f32 = 240 / 2,

    pub fn update(state: *AppState, delta: f32, pressed: horizon.services.Hid.Pad.State, touch_pressed: bool, random: std.Random) void {
        switch (state.game) {
            .get_ready => {
                if (pressed.a or touch_pressed) {
                    state.game = .{ .gaming = .{} };
                }

                state.bird_y = 240 / 2;
            },
            .gaming => |*g| {
                if (pressed.a or touch_pressed) g.bird_velocity = -100 else g.bird_velocity = @min(100, g.bird_velocity + 150 * delta);

                state.bird_y += g.bird_velocity * delta;

                if (state.bird_y + (bird_size - bird_collider_size) > (240 - ground_total_height)) {
                    state.bird_y = 240 - ground_total_height - (bird_size - bird_collider_size);
                    state.game = .game_over;
                } else if (state.bird_y < 0) {
                    state.bird_y = 0;
                    state.game = .game_over;
                } else {
                    // These values look very "magic" (they are) but they give the best collision experience with the pipes
                    const bird_x1 = bird_x - (bird_size - bird_collider_size);
                    const bird_x2 = bird_x1 + bird_collider_size;
                    const bird_y1 = state.bird_y - (bird_size - bird_collider_size);
                    const bird_y2 = bird_y1 + bird_collider_size;

                    for (state.pipe_storage[0..state.pipes]) |pipe| {
                        const pipe_down_x1: f32 = pipe.x;
                        const pipe_down_x2: f32 = pipe_down_x1 + pipe_width;
                        const pipe_down_y1: f32 = pipe.upper_pipe_size + pipe_gap;
                        const pipe_down_y2: f32 = 240-ground_total_height;

                        const pipe_up_x1: f32 = pipe.x;
                        const pipe_up_x2: f32 = pipe_up_x1 + pipe_width;
                        const pipe_up_y2: f32 = 0 + pipe.upper_pipe_size;
                        const pipe_up_y1: f32 = 0;

                        if (collides(bird_x1, bird_y1, bird_x2, bird_y2, pipe_down_x1, pipe_down_y1, pipe_down_x2, pipe_down_y2) or collides(bird_x1, bird_y1, bird_x2, bird_y2, pipe_up_x1, pipe_up_y1, pipe_up_x2, pipe_up_y2)) {
                            state.game = .game_over;
                            return;
                        }
                    }
                }

                var last_pipe_x: f32 = 0;

                for (state.pipe_storage[0..state.pipes]) |*pipe| {
                    pipe.x -= pipe_velocity * delta;

                    // Pipes go screen_height -> 0
                    if (pipe.x > last_pipe_x) {
                        last_pipe_x = pipe.x;
                    }
                }

                if (state.pipes < state.pipe_storage.len and last_pipe_x < (240 / 2)) {
                    state.pipe_storage[state.pipes] = .{
                        .x = 400,
                        .upper_pipe_size = random.intRangeAtMost(u8, 45, 120),
                        .color_index = random.int(u1),
                    };
                    state.pipes += 1;
                }

                // Remove unreachable pipes
                while (true) {
                    const unreachable_pipe = unr: for (state.pipe_storage[0..state.pipes], 0..) |pipe, i| {
                        if (pipe.x <= -pipe_width) {
                            break :unr i;
                        }
                    } else break;

                    if (unreachable_pipe < state.pipes - 1) {
                        std.mem.swap(Pipes, &state.pipe_storage[unreachable_pipe], &state.pipe_storage[state.pipes - 1]);
                    }

                    state.pipes -= 1;
                }

                state.current_ground_x -= pipe_velocity * delta;

                if (state.current_ground_x <= -ground_width) {
                    state.current_ground_x += ground_width;
                }
            },
            .game_over => {
                if (pressed.a or touch_pressed) {
                    state.game = .get_ready;
                    state.pipes = 0;
                }
            },
        }
    }

    pub fn draw(app: *const AppState, bat: *Batcher) void {
        app.drawGround(bat);
        app.drawPipes(bat);
        app.drawBird(bat);
    }

    fn drawGround(_: *const AppState, bat: *Batcher) void {
        drawRect(bat, .{0, 240-ground_total_height}, .{400, ground_total_height}, @splat(255));
    }

    fn drawPipes(app: *const AppState, bat: *Batcher) void {
        for (app.pipe_storage[0..app.pipes]) |pipe| {
            const x = pipe.x;

            drawRect(bat, .{x,0}, .{pipe_width, pipe.upper_pipe_size}, @splat(255));
            drawRect(bat, .{x,pipe.upper_pipe_size+pipe_gap}, .{pipe_width, 240-pipe.upper_pipe_size-pipe_gap}, @splat(255));
        }
    }

    fn drawBird(app: *const AppState, bat: *Batcher) void {
        const half_size = bird_size / 2.0;
        drawRect(bat, .{bird_x-half_size, app.bird_y-half_size}, @splat(bird_size), .{0,255,0,255});
    }
};

fn collides(x11: f32, y11: f32, x12: f32, y12: f32, x21: f32, y21: f32, x22: f32, y22: f32) bool {
    return !(x12 < x21 or x11 > x22 or y12 < y21 or y11 > y22);
}

const common = @import("common");
const State = common.State;
const Framebuffer = common.Framebuffer;
const Batcher = common.Batcher(Vertex);

const mango = zitrus.mango;
const horizon = zitrus.horizon;
const zmath = zitrus.math;

const zitrus = @import("zitrus");
const std = @import("std");
