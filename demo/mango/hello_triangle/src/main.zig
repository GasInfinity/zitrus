// NOTE: as you can see, the shader address must be aligned to 32-bits
const position_vtx_storage align(@sizeOf(u32)) = @embedFile("position.zpsh").*;
const position_vtx = &position_vtx_storage;

// XXX: Needed for the page_allocator
pub const std_options: std.Options = .{
    .page_size_min = horizon.heap.page_size_min,
    .page_size_max = horizon.heap.page_size_max,
};

pub fn main() !void {
    // XXX: Zig does not support using the DebugAllocator yet...
    // Instead of using the linear heap, use the normal heap.
    const gpa = horizon.heap.page_allocator;

    // Initialize average Application state.
    //
    // Includes (not exhaustive): connecting to the service manager, registering
    // the application, ..., creating a `mango.Device` (what we'll use)
    var app: horizon.application.Accelerated = try .init(.default, gpa);
    defer app.deinit(gpa);

    // Get the application device, it is destroyed automatically
    // when the application is deinitialized as it owns it.
    //
    // See `mango.createHorizonBackedDevice`
    //
    // Similar workflow as in Vulkan.
    const device: mango.Device = app.device;

    // Get the (TODO: allocated, all queues are allocated right now) queues at creation time. We allocate all queues at device creation time.
    const transfer_queue = device.getQueue(.transfer);
    const fill_queue = device.getQueue(.fill);
    const submit_queue = device.getQueue(.submit);
    const present_queue = device.getQueue(.present);

    // Allocate the semaphore we will use to synchronize with the GPU
    // and between GPU operations.
    //
    // If you've used Vulkan, this is basically a Timeline Semaphore (https://docs.vulkan.org/samples/latest/samples/extensions/timeline_semaphore/README.html)
    const sync_semaphore = try device.createSemaphore(.{
        .initial_value = 0,
    }, gpa);
    defer device.destroySemaphore(sync_semaphore, gpa);
    var sync_counter: u64 = 0;

    const Vertex = extern struct {
        pos: [2]i8,
    };

    // Allocate the memory we will use for swapchains.
    //
    // WARNING: Memory allocation has the same behaviour as in Vulkan, you *MUST* manage your memory.
    // That means allocating with `allocateMemory` can be expected to be SLOW and/or allocate more memory
    // than asked (e.g: allocate full pages for each allocation).
    // This is an example, if [performance/good allocation strategies] are needed... Manage your memory!
    //
    // Currently 3 Memory Types are implemented, there's no API for querying info and it is unknown
    // whether some will exist (need some thought), the memory types are:
    //  - FCRAM -> 0, HOST_VISIBLE | HOST_CACHED (128MB/256MB, in practice you'll have a lot less memory to work with)
    //  - VRAM Bank A -> 1, DEVICE_LOCAL [| HOST_VISIBLE in some situations] (3MB, full ownership)
    //  - VRAM Bank B -> 2, DEVICE_LOCAL [| HOST_VISIBLE in some situations] (3MB, full ownership)
    //
    // Unlike Vulkan, you manage the memory of your swapchain.
    // This has some implications: Screen content is UNDEFINED when the swapchain is destroyed,
    // that means that if you want hot-swap swapchains (e.g: you're making an emulator and want
    // to change the swapchain format dynamically), you should fill the LCD with a solid color.
    //
    // XXX: Should we fill the LCD ourselves?
    const bottom_presentable_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(320 * 240 * 3 * 2),
    }, gpa);
    defer device.freeMemory(bottom_presentable_image_memory, gpa);

    const top_presentable_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(400 * 240 * 3 * 2),
    }, gpa);
    defer device.freeMemory(top_presentable_image_memory, gpa);

    // Create the swapchains.
    // They are presented to the screen directly and unlike Vulkan, you're not able to render to swapchain images directly
    // as they are `linear`ly tiled. Rendering to them is done by blitting an offscreen `optimal`ly tiled image to it.
    //
    // They support up to 3 buffers (tripple buffering)
    //
    // Only 2 present modes are supported currently, same behaviour as the Vulkan ones (https://registry.khronos.org/vulkan/specs/latest/man/html/VkPresentModeKHR.html):
    //  - fifo
    //  - mailbox
    //
    // Unlike Vulkan, surfaces are fixed (currently, XXX: Explore different display modes and separate it to Display objects)
    //
    // 3 surfaces exist:
    //  - top_240x400 -> supports stereo, set array_layers == 2 (TODO: Truly support stereo rendering, create images with multiple layers)
    //  - top_240x800
    //  - bottom_240x320
    //
    const top_swapchain = try device.createSwapchain(.{
        .surface = .top_240x400,
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"1",
        .image_count = 2,
        .image_usage = .{
            .transfer_dst = true,
        },
        .image_memory_info = &.{
            .{ .memory = top_presentable_image_memory, .memory_offset = .size(0) },
            .{ .memory = top_presentable_image_memory, .memory_offset = .size(400 * 240 * 3) },
        },
    }, gpa);
    defer device.destroySwapchain(top_swapchain, gpa);

    // Even though we'll only render in this example to the top screen,
    // we should remember that surface contents are UNDEFINED before
    // the first swapchain present and/or after swapchain destruction.
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
        },
    }, gpa);
    defer device.destroySwapchain(bottom_swapchain, gpa);

    // Same as with Vulkan, you must get the swapchain images.
    //
    // It is asserted that an image with index `i` will be bound to image_memory_info[i].memory + offset.
    const top_images: [2]mango.Image = blk: {
        var img: [2]mango.Image = undefined;
        _ = device.getSwapchainImages(top_swapchain, &img);
        break :blk img;
    };

    const bottom_images: [2]mango.Image = blk: {
        var img: [2]mango.Image = undefined;
        _ = device.getSwapchainImages(bottom_swapchain, &img);
        break :blk img;
    };

    // Create Vertex and Index Buffers
    //
    // Same as in Vulkan. We'll allocate them on the FCRAM as we'll need to map them.
    //
    // You can use Vertex and Index buffers stored in FCRAM but they won't be as performant
    // as them being in VRAM.
    const vtx_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(@sizeOf(Vertex) * 3),
    }, gpa);
    defer device.freeMemory(vtx_buffer_memory, gpa);

    const index_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(3),
    }, gpa);
    defer device.freeMemory(index_buffer_memory, gpa);

    // Map, write and flush the vertex and index memory.
    //
    // Same as in Vulkan.
    {
        const mapped_vtx = try device.mapMemory(vtx_buffer_memory, 0, .whole);
        defer device.unmapMemory(vtx_buffer_memory);

        const mapped_idx = try device.mapMemory(index_buffer_memory, 0, .whole);
        defer device.unmapMemory(index_buffer_memory);

        const vtx_data: *[3]Vertex = std.mem.bytesAsValue([3]Vertex, mapped_vtx);
        const idx_data: *[3]u8 = std.mem.bytesAsValue([3]u8, mapped_idx);

        vtx_data.* = .{
            .{ .pos = .{ -1, -1 } },
            .{ .pos = .{ 1, 0 } },
            .{ .pos = .{ -1, 1 } },
        };

        idx_data.* = .{ 0, 1, 2 };

        try device.flushMappedMemoryRanges(&.{ .{
            .memory = vtx_buffer_memory,
            .offset = .size(0),
            .size = .size(@sizeOf(Vertex) * 3),
        }, .{
            .memory = index_buffer_memory,
            .offset = .size(0),
            .size = .size(3),
        } });
    }

    // Create the buffer objects
    //
    // Same as in Vulkan.
    const index_buffer = try device.createBuffer(.{
        .size = .size(0x3),
        .usage = .{
            .index_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(index_buffer, gpa);
    try device.bindBufferMemory(index_buffer, index_buffer_memory, .size(0));

    const vtx_buffer = try device.createBuffer(.{
        .size = .size(@sizeOf(Vertex) * 3),
        .usage = .{
            .vertex_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(vtx_buffer, gpa);
    try device.bindBufferMemory(vtx_buffer, vtx_buffer_memory, .size(0));

    // Create the color attachment that will be used for the TOP screen as we'll render to only one screen for simplicity.
    //
    // Same workflow as in Vulkan.
    const color_attachment_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(400 * 240 * 4),
    }, gpa);
    defer device.freeMemory(color_attachment_image_memory, gpa);

    // TODO: Docs. Color attachments must be `optimal`ly tiled!
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
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(top_color_attachment_image, gpa);
    try device.bindImageMemory(top_color_attachment_image, color_attachment_image_memory, .size(0));

    // Create the image view used for rendering.
    //
    // Same workflow as in vulkan.
    const top_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = top_color_attachment_image,
        .subresource_range = .full,
    }, gpa);
    defer device.destroyImageView(top_color_attachment_image_view, gpa);

    // Create the pipeline, this is an example.
    //
    // A lot of this state can be dynamic. TODO: Docs
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
                .format = .r8g8_sscaled,
                .offset = 0,
            },
        }, &.{}),
        // This must be a 'ZPSH' shader binary assembled by zitrus.
        .vertex_shader_state = &.init(position_vtx, "main"),
        .geometry_shader_state = null,
        .input_assembly_state = &.{
            .topology = .triangle_list,
        },
        // This is dynamic state, that's why it can be null.
        .viewport_state = null,
        .rasterization_state = &.{
            .front_face = .ccw,
            .cull_mode = .none,

            // (Mango specific) You can set the depth mode of the depth buffer to a w_buffer or z_buffer.
            .depth_mode = .z_buffer,
            .depth_bias_constant = 0.0,
        },
        .alpha_depth_stencil_state = &.{
            // (Mango specific) Alpha Test is added as a fixed function stage.
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
        // (Mango specific) Texture configuration is added as a fixed function stage.
        //
        // The behaviour is undefined if you try to use a texture unit wihout enabling it.
        .texture_sampling_state = &.{
            .texture_enable = .{ true, false, false, false },

            .texture_2_coordinates = .@"2",
            .texture_3_coordinates = .@"2",
        },
        // (Mango specific) Fragment lighting is added as a fixed function stage. TODO: Implement this
        .lighting_state = &.{},
        // (Mango specific) Fragment color combiner is added as a fixed function stage.
        .texture_combiner_state = &.init(&.{.{
            .color_src = @splat(.primary_color),
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
                // (Mango specific) The blend equation must be explicitly set. No blend_enable toggle.
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

    // Create the `CommandPool` for allocating `CommandBuffer`'s.
    //
    // Same as in Vulkan.
    // Currently they behave as if the 'Reset Command Buffer' flag was set (you can reset command buffers individually).
    const command_pool = try device.createCommandPool(.{}, gpa);
    defer device.destroyCommandPool(command_pool, gpa);

    // Allocate a single `CommandBuffer`. Can be individually reset, see above.
    const cmd = blk: {
        var cmd: mango.CommandBuffer = undefined;
        try device.allocateCommandBuffers(.{
            .pool = command_pool,
            .command_buffer_count = 1,
        }, @ptrCast(&cmd));
        break :blk cmd;
    };
    defer device.freeCommandBuffers(command_pool, @ptrCast(&cmd));

    // Stop filling the LCD with a solid color.
    //
    // Screen contents are undefined until we present the first frame, for simplicity we'll ignore that.
    try app.gsp.sendSetLcdForceBlack(false);
    defer if (!app.apt_app.flags.must_close) app.gsp.sendSetLcdForceBlack(true) catch {}; // NOTE: Could fail if we don't have right?

    main_loop: while (true) {
        while (try app.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        const bottom_current_image_idx = try device.acquireNextImage(bottom_swapchain, -1);
        const top_current_image_idx = try device.acquireNextImage(top_swapchain, -1);

        // Same command recording workflow as Vulkan.
        //
        // However, some things change. TODO: Docs
        try cmd.begin();

        cmd.bindIndexBuffer(index_buffer, 0, .u8);
        cmd.bindVertexBuffersSlice(0, &.{vtx_buffer}, &.{0});
        cmd.bindPipeline(.graphics, simple_pipeline);

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
                .color_attachment = top_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            cmd.drawIndexed(3, 0, 0);
        }
        try cmd.end();

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter),
            .image = bottom_images[bottom_current_image_idx],
            .color = @splat(0xFF),
            .subresource_range = .full,
            .signal_semaphore = &.init(sync_semaphore, sync_counter + 1),
        });

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter + 1),
            .image = top_color_attachment_image,
            .color = @splat(0x22),
            .subresource_range = .full,
            .signal_semaphore = &.init(sync_semaphore, sync_counter + 2),
        });

        try submit_queue.submit(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter + 2),
            .command_buffer = cmd,
            .signal_semaphore = &.init(sync_semaphore, sync_counter + 3),
        });

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter + 3),
            .src_image = top_color_attachment_image,
            .dst_image = top_images[top_current_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(sync_semaphore, sync_counter + 4),
        });

        try present_queue.present(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter + 3),
            .swapchain = bottom_swapchain,
            .image_index = bottom_current_image_idx,
            .flags = .{},
        });

        try present_queue.present(.{
            .wait_semaphore = &.init(sync_semaphore, sync_counter + 4),
            .swapchain = top_swapchain,
            .image_index = top_current_image_idx,
            .flags = .{},
        });

        // We're currently using one color attachment so even though we're double-buffered on the swapchain,
        // we only have a single buffer to work on. We must wait until we finished with the color buffer.
        sync_counter += 4;
        try device.waitSemaphore(.{
            .semaphore = sync_semaphore,
            .value = sync_counter,
        }, -1);
    }

    try device.waitIdle();
}

const mango = zitrus.mango;

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;

pub const panic = zitrus.horizon.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
