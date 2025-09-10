// NOTE: mango is not finished. It is designed with a vulkan-like api
// TODO: Document everything when finished

// NOTE: as you can see, the shader address must be aligned to 32-bits
const simple_vtx_storage align(@sizeOf(u32)) = @embedFile("simple.zpsh").*;
const simple_vtx = &simple_vtx_storage;

const test_bgr = @embedFile("test.bgr");

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = horizon.heap.page_allocator;
    };
};

pub const std_options: std.Options = .{
    .page_size_min = horizon.heap.page_size_min,
    .page_size_max = horizon.heap.page_size_max,
    .logFn = log,
    .log_level = .debug,
};

pub fn log(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const prefix = std.fmt.bufPrint(&buf, "[{s}] ({s}): ", .{ @tagName(message_level), @tagName(scope) }) catch {
        horizon.outputDebugString("fatal: logged message prefix does not fit into the buffer. message skipped!");
        return;
    };

    const message = std.fmt.bufPrint(buf[prefix.len..], format, args) catch buf[prefix.len..];
    horizon.outputDebugString(buf[0..(prefix.len + message.len)]);
}

pub fn main() !void {
    // var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    // defer _ = gpa_state.deinit();

    const gpa = horizon.heap.page_allocator; // gpa_state.allocator();

    var srv = try ServiceManager.init();
    defer srv.deinit();

    const apt = try Applet.open(srv);
    defer apt.close();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    const hid = try Hid.open(srv);
    defer hid.close();

    var input = try Hid.Input.init(hid);
    defer input.deinit();

    const gsp = try GspGpu.open(srv);
    defer gsp.close();

    const Vertex = extern struct {
        pos: [4]i8,
        uv: [2]u8,
    };

    const arbiter: horizon.AddressArbiter = try .create();
    defer arbiter.close();

    var device: *mango.Device = try .initTodo(gsp, arbiter, gpa);
    defer device.deinit(gpa);

    const transfer_queue = device.getQueue(.transfer);
    const fill_queue = device.getQueue(.fill);
    const submit_queue = device.getQueue(.submit);
    const present_queue = device.getQueue(.present);

    const global_semaphore = try device.createSemaphore(.{
        .initial_value = 0,
    }, gpa);
    defer device.destroySemaphore(global_semaphore, gpa);
    var global_sync_counter: u64 = 0;

    const bottom_presentable_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(320 * 240 * 3 * 2),
    }, gpa);
    defer device.freeMemory(bottom_presentable_image_memory, gpa);

    const top_presentable_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(400 * 240 * 3 * 2 * 2),
    }, gpa);
    defer device.freeMemory(top_presentable_image_memory, gpa);

    const top_swapchain = try device.createSwapchain(.{
        .surface = .top_240x400,
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"2",
        .image_count = 2,
        .image_usage = .{
            .transfer_dst = true,
        },
        .image_memory_info = &.{
            .{ .memory = top_presentable_image_memory, .memory_offset = .size(0) },
            .{ .memory = top_presentable_image_memory, .memory_offset = .size(400 * 240 * 3 * 2) },
            // .{ .memory = top_presentable_image_memory, .memory_offset = .size(400 * 240 * 3 * 2) },
        },
    }, gpa);
    defer device.destroySwapchain(top_swapchain, gpa);

    const top_images: [2]mango.Image = blk: {
        var img: [2]mango.Image = undefined;
        _ = device.getSwapchainImages(top_swapchain, &img);
        break :blk img;
    };

    const bottom_swapchain = try device.createSwapchain(.{
        .surface = .bottom_240x320,
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"1",
        .image_count = 2,
        .image_usage = .{
            .transfer_dst = true,
        },
        .image_memory_info = &.{
            .{ .memory = bottom_presentable_image_memory, .memory_offset = .size(0) },
            .{ .memory = bottom_presentable_image_memory, .memory_offset = .size(320 * 240 * 3) },
            // .{ .memory = bottom_presentable_image_memory, .memory_offset = .size(320 * 240 * 3 * 2) },
        },
    }, gpa);
    defer device.destroySwapchain(bottom_swapchain, gpa);

    const bottom_images: [2]mango.Image = blk: {
        var img: [2]mango.Image = undefined;
        _ = device.getSwapchainImages(bottom_swapchain, &img);
        break :blk img;
    };

    const vtx_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(@sizeOf(Vertex) * 4),
    }, gpa);
    defer device.freeMemory(vtx_buffer_memory, gpa);

    const index_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(4),
    }, gpa);
    defer device.freeMemory(index_buffer_memory, gpa);

    {
        const mapped_vtx = try device.mapMemory(vtx_buffer_memory, 0, .whole);
        defer device.unmapMemory(vtx_buffer_memory);

        const mapped_idx = try device.mapMemory(index_buffer_memory, 0, .whole);
        defer device.unmapMemory(index_buffer_memory);

        const vtx_data: *[4]Vertex = std.mem.bytesAsValue([4]Vertex, mapped_vtx);
        const idx_data: *[4]u8 = std.mem.bytesAsValue([4]u8, mapped_idx);

        vtx_data.* = .{
            .{ .pos = .{ -1, -1, 2, 1 }, .uv = .{ 0, 0 } },
            .{ .pos = .{ 1, -1, 2, 1 }, .uv = .{ 1, 0 } },
            .{ .pos = .{ -1, 1, 4, 1 }, .uv = .{ 0, 1 } },
            .{ .pos = .{ 1, 1, 4, 1 }, .uv = .{ 1, 1 } },
        };
        idx_data.* = .{ 0, 1, 2, 3 };

        try device.flushMappedMemoryRanges(&.{ .{
            .memory = vtx_buffer_memory,
            .offset = .size(0),
            .size = .size(@sizeOf(Vertex) * 4),
        }, .{
            .memory = index_buffer_memory,
            .offset = .size(0),
            .size = .size(4),
        } });
    }

    const index_buffer = try device.createBuffer(.{
        .size = .size(0x4),
        .usage = .{
            .index_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(index_buffer, gpa);
    try device.bindBufferMemory(index_buffer, index_buffer_memory, .size(0));

    const vtx_buffer = try device.createBuffer(.{
        .size = .size(@sizeOf(Vertex) * 4),
        .usage = .{
            .vertex_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(vtx_buffer, gpa);
    try device.bindBufferMemory(vtx_buffer, vtx_buffer_memory, .size(0));

    const color_attachment_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(320 * 240 * 4 + 400 * 240 * 4 * 2),
    }, gpa);
    defer device.freeMemory(color_attachment_image_memory, gpa);

    const top_color_attachment_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_src = true,
            .color_attachment = true,
        },
        .extent = .{
            .width = 240,
            .height = 400,
        },
        .format = .a8b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"2",
    }, gpa);
    defer device.destroyImage(top_color_attachment_image, gpa);
    try device.bindImageMemory(top_color_attachment_image, color_attachment_image_memory, .size(320 * 240 * 4));

    const bottom_color_attachment_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_src = true,
            .color_attachment = true,
        },
        .extent = .{
            .width = 240,
            .height = 320,
        },
        .format = .a8b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(bottom_color_attachment_image, gpa);
    try device.bindImageMemory(bottom_color_attachment_image, color_attachment_image_memory, .size(0));

    const staging_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(64 * 64 * 3),
    }, gpa);
    defer device.freeMemory(staging_buffer_memory, gpa);

    const staging_buffer = try device.createBuffer(.{
        .size = .size(64 * 64 * 3),
        .usage = .{
            .transfer_src = true,
        },
    }, gpa);
    defer device.destroyBuffer(staging_buffer, gpa);
    try device.bindBufferMemory(staging_buffer, staging_buffer_memory, .size(0));

    {
        const mapped_staging = try device.mapMemory(staging_buffer_memory, 0, .whole);
        defer device.unmapMemory(staging_buffer_memory);

        @memcpy(mapped_staging[0..(64 * 64 * 3)], test_bgr);

        try device.flushMappedMemoryRanges(&.{.{
            .memory = staging_buffer_memory,
            .offset = .size(0),
            .size = .size(64 * 64 * 3),
        }});
    }

    const test_sampled_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(64 * 64 * 3),
    }, gpa);
    defer device.freeMemory(test_sampled_image_memory, gpa);

    const test_sampled_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_dst = true,
            .sampled = true,
        },
        .extent = .{
            .width = 64,
            .height = 64,
        },
        .format = .b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(test_sampled_image, gpa);
    try device.bindImageMemory(test_sampled_image, test_sampled_image_memory, .size(0));

    try transfer_queue.copyBufferToImage(.{
        .src_buffer = staging_buffer,
        .src_offset = .size(0),
        .dst_image = test_sampled_image,
        .dst_subresource = .full,
        .signal_semaphore = &.init(global_semaphore, global_sync_counter + 1),
    });

    global_sync_counter += 1;

    const test_sampled_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .b8g8r8_unorm,
        .image = test_sampled_image,
        .subresource_range = .{
            .base_mip_level = .@"0",
            .level_count = .@"1",
            .base_array_layer = .@"0",
            .layer_count = .@"1",
        },
    }, gpa);
    defer device.destroyImageView(test_sampled_image_view, gpa);

    const simple_sampler = try device.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mip_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .lod_bias = 0.0,
        .min_lod = 0,
        .max_lod = 7,
        .border_color = @splat(0),
    }, gpa);
    defer device.destroySampler(simple_sampler, gpa);

    const bottom_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = bottom_color_attachment_image,
        .subresource_range = .{
            .base_mip_level = .@"0",
            .level_count = .@"1",
            .base_array_layer = .@"0",
            .layer_count = .@"1",
        },
    }, gpa);
    defer device.destroyImageView(bottom_color_attachment_image_view, gpa);

    const top_left_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = top_color_attachment_image,
        .subresource_range = .{
            .base_mip_level = .@"0",
            .level_count = .remaining,
            .base_array_layer = .@"0",
            .layer_count = .@"1",
        },
    }, gpa);
    defer device.destroyImageView(top_left_color_attachment_image_view, gpa);

    const top_right_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = top_color_attachment_image,
        .subresource_range = .{
            .base_mip_level = .@"0",
            .level_count = .remaining,
            .base_array_layer = .@"1",
            .layer_count = .@"1",
        },
    }, gpa);

    defer device.destroyImageView(top_right_color_attachment_image_view, gpa);

    const simple_pipeline = try device.createGraphicsPipeline(.{
        .rendering_info = &.{
            .color_attachment_format = .a8b8g8r8_unorm,
            .depth_stencil_attachment_format = .undefined,
        },
        .vertex_input_state = &.init(&.{
            .{
                .stride = @sizeOf(Vertex),
            },
        }, &.{
            .{
                .location = .v0,
                .binding = .@"0",
                .format = .r8g8b8a8_sscaled,
                .offset = 0,
            },
            .{
                .location = .v1,
                .binding = .@"0",
                .format = .r8g8_uscaled,
                .offset = 4,
            },
        }, &.{}),
        .vertex_shader_state = &.init(simple_vtx, "main"),
        .geometry_shader_state = null,
        .input_assembly_state = &.{
            .topology = .triangle_strip,
        },
        .viewport_state = null,
        .rasterization_state = &.{
            .front_face = .ccw,
            .cull_mode = .none,

            .depth_mode = .z_buffer,
            .depth_bias_constant = 0.0,
        },
        .alpha_depth_stencil_state = &.{
            .alpha_test_enable = false,
            .alpha_test_compare_op = .never,
            .alpha_test_reference = 0,

            // (!) Disabling depth tests also disables depth writes like in every other graphics api
            .depth_test_enable = false,
            .depth_write_enable = false,
            .depth_compare_op = .gt,

            .stencil_test_enable = false,
            .back_front = std.mem.zeroes(mango.GraphicsPipelineCreateInfo.AlphaDepthStencilState.StencilOperationState),
        },
        .texture_sampling_state = &.{
            .texture_enable = .{ true, false, false, false },

            .texture_2_coordinates = .@"2",
            .texture_3_coordinates = .@"2",
        },
        .lighting_state = &.{},
        .texture_combiner_state = &.init(&.{.{
            .color_src = @splat(.texture_0),
            .alpha_src = @splat(.primary_color),
            .color_factor = @splat(.src_color),
            .alpha_factor = @splat(.src_alpha),
            .color_op = .replace,
            .alpha_op = .replace,

            .color_scale = .@"1x",
            .alpha_scale = .@"1x",

            .constant = @splat(0),
        }}, &.{}),
        .color_blend_state = &.{
            .logic_op_enable = false,
            .logic_op = .clear,

            .attachment = .{
                .blend_equation = .{
                    .src_color_factor = .one,
                    .dst_color_factor = .zero,
                    .color_op = .add,
                    .src_alpha_factor = .one,
                    .dst_alpha_factor = .zero,
                    .alpha_op = .add,
                },
                .color_write_mask = .rgba,
            },
            .blend_constants = .{ 0, 0, 0, 0 },
        },
        .dynamic_state = .{
            .viewport = true,
            .scissor = true,
        },
    }, gpa);
    defer device.destroyPipeline(simple_pipeline, gpa);

    const command_pool = try device.createCommandPool(.{}, gpa);
    defer device.destroyCommandPool(command_pool, gpa);

    const cmd = blk: {
        var cmd: mango.CommandBuffer = undefined;
        try device.allocateCommandBuffers(.{
            .pool = command_pool,
            .command_buffer_count = 1,
        }, @ptrCast(&cmd));
        break :blk cmd;
    };
    defer device.freeCommandBuffers(command_pool, @ptrCast(&cmd));

    try gsp.sendSetLcdForceBlack(false);
    defer if(!app.flags.must_close) gsp.sendSetLcdForceBlack(true) catch {}; // NOTE: Could fail if we don't have right?

    // XXX: Bad, but we know this is not near graphicaly intensive and we'll always be near 60 FPS.
    const default_delta_time = 1.0 / 60.0;
    var current_time: f32 = 0.0;
    // var current_scale: f32 = 1.0;
    main_loop: while (true) {
        defer current_time += default_delta_time;
        
        const iod = horizon.memory.shared_config.slider_state_3d / 3.0;

        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => break :main_loop,
            else => {},
        };

        while (try app.pollNotification(apt, srv)) |n| switch (n) {
            .jump_home, .jump_home_by_power => {
                try device.waitIdle();

                switch (try app.jumpToHome(apt, srv, gsp, .none)) {
                    .resumed => {},
                    .must_close => break :main_loop,
                    .jump_home => unreachable,
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

        // if(input.current.up) {
        //     current_scale += 1.0 * default_delta_time * 5;
        // } else if(input.current.down) {
        //     current_scale -= 1.0 * default_delta_time * 5;
        // }
        // current_scale = std.math.clamp(current_scale, -1.0, 1.0);

        const bottom_first_image_idx = try device.acquireNextImage(bottom_swapchain, -1);
        const top_first_image_idx = try device.acquireNextImage(top_swapchain, -1);

        try cmd.begin();

        cmd.bindIndexBuffer(index_buffer, 0, .u8);
        cmd.bindVertexBuffersSlice(0, &.{vtx_buffer}, &.{0});
        cmd.bindPipeline(.graphics, simple_pipeline);
        cmd.bindCombinedImageSamplers(0, &.{.{
            .image = test_sampled_image_view,
            .sampler = simple_sampler,
        }});

        // Render to the bottom screen
        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = 240, .height = 320 },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 320 } }));

        {
            cmd.beginRendering(.{
                .color_attachment = bottom_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(std.math.degreesToRadians(90.0), 240.0 / 320.0, 1, 1000));

            const current_scale = @sin(current_time);
            cmd.bindFloatUniforms(.vertex, 4, &zmath.mat.scale(current_scale, @abs(current_scale), 1));
            cmd.drawIndexed(4, 0, 0);
        }

        // Render to the top screen
        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = 240, .height = 400 },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 400 } }));

        {
            cmd.beginRendering(.{
                .color_attachment = top_left_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(std.math.degreesToRadians(90.0), 240.0 / 400.0, 1, 1000));

            const current_scale = 1;//@sin(-current_time);
            cmd.bindFloatUniforms(.vertex, 4, &zmath.mat.scaleTranslate(current_scale, @abs(current_scale), 1, 0.25 * iod, 0, 0));
            cmd.drawIndexed(4, 0, 0);
        }

        if(iod > 0) {
            cmd.beginRendering(.{
                .color_attachment = top_right_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(std.math.degreesToRadians(90.0), 240.0 / 400.0, 1, 1000));

            const current_scale = 1;//@sin(-current_time);
            cmd.bindFloatUniforms(.vertex, 4, &zmath.mat.scaleTranslate(current_scale, @abs(current_scale), 1, -0.25 * iod, 0, 0));
            cmd.drawIndexed(4, 0, 0);
        }

        try cmd.end();

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter),
            .image = bottom_color_attachment_image,
            .color = @splat(0x33),
            .subresource_range = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 1),
        });

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 1),
            .image = top_color_attachment_image,
            .color = @splat(0x22),
            .subresource_range = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 2),
        });

        try submit_queue.submit(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 2),
            .command_buffer = cmd,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 3),
        });

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 3),
            .src_image = bottom_color_attachment_image,
            .dst_image = bottom_images[bottom_first_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 4),
        });

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 4),
            .src_image = top_color_attachment_image,
            .dst_image = top_images[top_first_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 5),
        });

        try present_queue.present(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 4),
            .swapchain = bottom_swapchain,
            .image_index = bottom_first_image_idx,
            .flags = .{},
        });

        try present_queue.present(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 5),
            .swapchain = top_swapchain,
            .image_index = top_first_image_idx,
            .flags = .{
                .ignore_stereoscopic = iod == 0,
            },
        });

        // We're currently using one color attachment so even though we're double-buffered on the swapchain,
        // we only have a single buffer to work on. We must wait until we finished with the color buffer.
        try device.waitSemaphore(.{
            .semaphore = global_semaphore,
            .value = global_sync_counter + 5,
        }, -1);
        global_sync_counter += 5;
    }

    try device.waitIdle();
}

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;

const mango = zitrus.mango;

const pica = zitrus.pica;
const F7_16x4 = pica.F7_16x4;
const cmd3d = pica.cmd3d;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
    _ = zitrus.c;
}
