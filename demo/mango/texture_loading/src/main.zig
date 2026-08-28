// NOTE: as you can see, the shader address must be aligned to 32-bits
const position_vtx_storage align(@sizeOf(u32)) = @embedFile("position_uv.psh").*;
const position_vtx = &position_vtx_storage;

pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

const Model = extern struct {
    const Vertex = extern struct {
        pos: [2]f32,
        uv: [2]f32,
    };

    vertices: [4]Vertex,
    indices: [6]u8,
};

const model_data: Model = .{
    .vertices = .{
        .{ .pos = .{ -0.5, -0.5 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ 0.5, -0.5 }, .uv = .{ 1, 0 }  },
        .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }  },
        .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }  },
    },
    .indices = .{ 0, 1, 2, 2, 1, 3 },
};

pub fn main(init: horizon.Init.Application.Mango) !void {
    const io = init.app.base.io;
    const device: mango.Device = init.device;

    var state: State = try .init(device, false);
    defer state.deinit(device);

    try horizon.Io.global.initStorage(init.app.srv, .fs, 0);
    defer horizon.Io.global.deinitFilesystem();

    try horizon.Io.global.mountSelfRomFs("romfs");

    var top: [2]Framebuffer = @splat(.empty);
    defer for (&top) |fb| fb.deinit(device);
    for (&top) |*fb| fb.* = try .init(device, 240, 400, .b8g8r8_unorm, .undefined);
    defer device.waitIdle(); // Wait for any operation in-progress

    const model = try state.fcram.dupe(Model, (&model_data)[0..1]);
    defer state.fcram.free(model);

    const model_gpu = try device.hostToDevice(@ptrCast(model));
    try device.flushCachedMemoryRanges(&.{@ptrCast(model)});

    const simple_shader = try device.createShader(.init(.psh, position_vtx, "main"));
    defer device.destroyShader(simple_shader);

    const vertex_input_layout = try device.createVertexInputLayout(.init(&.{
        .{ .stride = @sizeOf(Model.Vertex) },
    }, &.{
        .{
            .location = .v0,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Model.Vertex, "pos"),
        },
        .{
            .location = .v1,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Model.Vertex, "uv"),
        },
    }, &.{}));
    defer device.destroyVertexInputLayout(vertex_input_layout);

    const texture_buffer = try device.allocatePrivate(.a, 64 * 64 * 3);
    defer device.freePrivate(texture_buffer);
    const texture_gpu_buffer = try device.hostToDevice(texture_buffer);

    const texture = try device.createImage(.{
        .flags = .{},
        .tiling = .optimal,
        .usage = .{ .sampled = true },
        .extent = .{ .width = 64, .height = 64 },
        .format = .b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    });
    defer device.destroyImage(texture);
    try device.bindImageMemory(texture, texture_gpu_buffer);

    const texture_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .b8g8r8_unorm,
        .image = texture,
        .subresource_range = .full,
    });
    defer device.destroyImageView(texture_view);

    const linear_sampler = try device.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mip_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .lod_bias = 0.0,
        .min_lod = 0,
        .max_lod = 0,
        .border_color = @splat(0),
    });
    defer device.destroySampler(linear_sampler);
    {
        // TODO: Load an encoded image instead of raw bytes
        const texture_file = try std.Io.Dir.cwd().openFile(io, "romfs:/test.bgr", .{});
        defer texture_file.close(io);

        const staging = try state.fcram.alloc(u8, 64*64*3);
        defer state.fcram.free(staging);
        const staging_gpu = try device.hostToDevice(staging);

        if(try texture_file.readPositionalAll(io, staging, 0) != staging.len) return error.ImageTooShort;

        try device.flushCachedMemoryRanges(&.{staging});
        try device.copyBufferToImage(&.init(state.sema, state.sync), &.init(state.sema, state.sync + 1), &.{
            .src_buffer = staging_gpu,
            .dst_image = texture,
            .dst_subresource = .full,
        });

        // We're waiting here because we're freeing the staging memory afterwards, instead of doing this you could let the allocation live until the next frame
        // to reclaim it.
        state.sync += 1;
        try device.waitSemaphores(.init(&.{state.sema}, &.{state.sync}), std.math.maxInt(u64));
    }

    const input = init.app.input;

    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = input.pollPad();
        if (pad.current.start) break :main_loop;

        const cmd = try state.acquireNext(device);
        const color_attachment_img = top[state.current].color.image;
        const color_attachment = top[state.current].color.view;

        // Same command recording workflow as Vulkan.
        //
        // However, some things change.
        // E.g: We have `bindCombinedImageSamplers`, `bindLightEnvironmentFactors`, `bindLights`, ...
        try cmd.begin();
        // Set the initial state, the validation (in safe modes) will guide you
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
            .color_src = .{.primary_color, .texture_0, .primary_color},
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

        cmd.bindIndexBuffer(model_gpu.slice(@offsetOf(Model, "indices"), 6), .u8);
        cmd.bindVertexBuffers(0, &.{model_gpu});
        cmd.bindCombinedImageSamplers(0, &.{
            .{
                .image = texture_view,
                .sampler = linear_sampler,
            }
        });

        {
            cmd.beginRendering(.{
                .color_attachment = color_attachment,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            cmd.drawIndexed(model[0].indices.len, 0, 0);
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
            .image = color_attachment_img,
            .color = @splat(0x22),
        });

        try device.submit(&.init(state.sema, state.sync + 1), &.init(state.sema, state.sync + 2), &.{
            .command_buffer = state.cmd[state.current],
        });

        try device.blitImage(&.init(state.sema, state.sync + 2), &.init(state.sema, state.sync + 3), &.{
            .src_image = color_attachment_img,
            .dst_image = state.top_images[top_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
        });

        try device.present(&.init(state.sema, state.sync + 3), &.{
            .display = .top,
            .image_index = top_idx,
            .flags = .{},
        });

        state.sync += 3;
        state.syncNext();
    }
}

const common = @import("common");
const State = common.State;
const Framebuffer = common.Framebuffer;

const mango = zitrus.mango;
const horizon = zitrus.horizon;

const zitrus = @import("zitrus");
const std = @import("std");
