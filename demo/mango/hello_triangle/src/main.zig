//! Self-contained mango sample showing minimal usage of mango,
//! further samples will be abstracted for brevity.

// NOTE: as you can see, the shader address must be aligned to 32-bits
const position_vtx_storage align(@sizeOf(u32)) = @embedFile("position.psh").*;
const position_vtx = &position_vtx_storage;

pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

const Vertex = extern struct { pos: [2]f32 };
const indices: []const u8 = &.{0,1,2};
const vertices: []const Vertex = &.{
    .{ .pos = .{ -0.5, -0.5 } },
    .{ .pos = .{ 0.5, 0 } },
    .{ .pos = .{ -0.5, 0.5 } },
};

pub fn main(init: horizon.Init.Application.Mango) !void {
    const device: mango.Device = init.device;
    const fcram = device.hostAllocator();

    const sync_semaphore = try device.createSemaphore(.initial_zero);
    defer device.destroySemaphore(sync_semaphore);
    var sync_counter: u64 = 0;

    const presentable_image_memory = try device.allocatePrivate(.a, 400 * 240 * 3 * 2 + 320 * 240 * 3 * 2);
    defer device.freePrivate(presentable_image_memory);
    const presentable_gpu_image_memory = try device.hostToDevice(presentable_image_memory);

    const top_presentable_image_memory_gpu = presentable_gpu_image_memory.slice(0, 400 * 240 * 3 * 2);
    const bottom_presentable_image_memory_gpu = presentable_gpu_image_memory.slice(400 * 240 * 3 * 2, 320 * 240 * 3 * 2);

    try device.configureDisplay(.top, &.{
        .extent = .{ .width = 240, .height = 400 },
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"1",
        .image_count = 2,
        .image_memory = &.{ top_presentable_image_memory_gpu, top_presentable_image_memory_gpu.openSlice(400*240*3) },
    });
    defer {
        device.waitIdle();
        device.resetDisplay(.top);
    }

    try device.configureDisplay(.bottom, &.{
        .extent = .{ .width = 240, .height = 320 },
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"1",
        .image_count = 2,
        .image_memory = &.{ bottom_presentable_image_memory_gpu, bottom_presentable_image_memory_gpu.openSlice(320*240*3) },
    });
    defer {
        device.waitIdle();
        device.resetDisplay(.bottom);
    }

    var top_images: [2]mango.Image = undefined;
    _ = try device.getDisplayImages(.top, &top_images);

    var bottom_images: [2]mango.Image = undefined;
    _ = try device.getDisplayImages(.bottom, &bottom_images);
    
    const buffer = try fcram.alloc(u8, @sizeOf(Vertex) * 3 + 3 * @sizeOf(u8));
    const gpu_buffer = try device.hostToDevice(buffer);
    defer fcram.free(buffer);

    {
        const vtx_data: *[3]Vertex = @alignCast(std.mem.bytesAsValue([3]Vertex, buffer));
        @memcpy(vtx_data, vertices);
        const idx_data: *[3]u8 = std.mem.bytesAsValue([3]u8, buffer[@sizeOf(Vertex) * 3..]);
        @memcpy(idx_data, indices);
        try device.flushCachedMemoryRanges(&.{buffer});
    }

    const color_attachment_buffer = try device.allocatePrivate(.a, 400 * 480 * 4);
    defer device.freePrivate(color_attachment_buffer);
    const color_attachment_gpu_buffer = try device.hostToDevice(color_attachment_buffer);

    const top_color_attachment_image = try device.createImage(.{
        .flags = .{},
        .tiling = .optimal,
        .usage = .{ .color_attachment = true },
        .extent = .{ .width = 480, .height = 400 },
        .format = .a8b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    });
    defer device.destroyImage(top_color_attachment_image);
    try device.bindImageMemory(top_color_attachment_image, color_attachment_gpu_buffer);

    const top_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = top_color_attachment_image,
        .subresource_range = .full,
    });
    defer device.destroyImageView(top_color_attachment_image_view);

    const simple_shader = try device.createShader(.init(.psh, position_vtx, "main"));
    defer device.destroyShader(simple_shader);

    const vertex_input_layout = try device.createVertexInputLayout(.init(&.{
        .{ .stride = @sizeOf(Vertex) },
    }, &.{
        .{
            .location = .v0,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = 0,
        },
    }, &.{}));
    defer device.destroyVertexInputLayout(vertex_input_layout);

    const command_pool = try device.createCommandPool(.no_preheat);
    defer device.destroyCommandPool(command_pool);

    const cmd = blk: {
        var cmd: mango.CommandBuffer = undefined;
        try device.allocateCommandBuffers(.{
            .pool = command_pool,
            .command_buffer_count = 1,
        }, @ptrCast(&cmd));
        break :blk cmd;
    };
    defer device.freeCommandBuffers(command_pool, @ptrCast(&cmd));

    const input = init.app.input;

    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        const bottom_current_image_idx = try device.acquireNextImage(.bottom, std.math.maxInt(u64));
        const top_current_image_idx = try device.acquireNextImage(.top, std.math.maxInt(u64));

        // Same command recording workflow as Vulkan.
        //
        // However, some things change.
        // E.g: We have `bindCombinedImageSamplers`, `bindLightEnvironmentFactors`, `bindLights`, ...
        try cmd.begin();

        cmd.clearColorImage(&.{
            .image = top_color_attachment_image,
            .color = @splat(0x22),
            .subresource_range = .full,
        });
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
            .color_src = @splat(.primary_color),
            .alpha_src = @splat(.primary_color),
            .color_factor = @splat(.src_color),
            .alpha_factor = @splat(.src_alpha),
            .color_op = .replace,
            .alpha_op = .replace,

            .color_scale = .@"1x",
            .alpha_scale = .@"1x",

            .constant = @splat(0),
        }});

        // Render to the top screen
        cmd.setViewport(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 480, .height = 400 } });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 480, .height = 400 } }));

        cmd.bindIndexBuffer(gpu_buffer.slice(@sizeOf(Vertex) * 3, 3), .u8);
        cmd.bindVertexBuffers(0, &.{gpu_buffer});

        {
            cmd.beginRendering(.{
                .color_attachment = top_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            cmd.drawIndexed(3, 0, 0);
        }
        try cmd.end();

        try device.clearColorImage(&.init(sync_semaphore, sync_counter), &.init(sync_semaphore, sync_counter + 1), &.{
            .image = bottom_images[bottom_current_image_idx],
            .color = @splat(0x33),
            .subresource_range = .full,
        });

        try device.clearColorImage(&.init(sync_semaphore, sync_counter + 1), &.init(sync_semaphore, sync_counter + 2), &.{
            .image = top_color_attachment_image,
            .color = @splat(0x22),
            .subresource_range = .full,
        });

        try device.submit(&.init(sync_semaphore, sync_counter + 2), &.init(sync_semaphore, sync_counter + 3), &.{
            .command_buffer = cmd,
        });

        try device.blitImage(&.init(sync_semaphore, sync_counter + 3), &.init(sync_semaphore, sync_counter + 4), &.{
            .src_image = top_color_attachment_image,
            .dst_image = top_images[top_current_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
        });

        try device.present(&.init(sync_semaphore, sync_counter + 3), &.{
            .display = .bottom,
            .image_index = bottom_current_image_idx,
        });

        try device.present(&.init(sync_semaphore, sync_counter + 4), &.{
            .display = .top,
            .image_index = top_current_image_idx,
        });

        sync_counter += 4;
        try device.waitSemaphores(.init(&.{sync_semaphore}, &.{sync_counter}), std.math.maxInt(u64));
    }
}

const mango = zitrus.mango;
const horizon = zitrus.horizon;

const zitrus = @import("zitrus");
const std = @import("std");
