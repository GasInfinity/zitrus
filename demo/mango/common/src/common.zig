pub const State = struct {
    swapchain_memory: mango.DeviceMemory,
    top: mango.Swapchain,
    bottom: mango.Swapchain,
    top_images: [2]mango.Image,
    bottom_images: [2]mango.Image,

    color_buffer_memory: mango.DeviceMemory,
    color_buffers: [2]mango.Image,
    color_buffer_views: [2]mango.ImageView,

    sema: mango.Semaphore,
    pool: mango.CommandPool,
    cmd: [2]mango.CommandBuffer,
    sync_points: [2]u64,
    sync: u64,
    current: u1,

    pub fn init(dev: mango.Device) !State {
        const swapchain_memory = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(400 * 240 * 3 * 2 + 320 * 240 * 3 * 2),
        }, null);
        errdefer dev.freeMemory(swapchain_memory, null);
        
        {
            // fill the bottom so it's always a solid color
            const mapped = try dev.mapMemory(swapchain_memory, .size(0), .whole);
            defer dev.unmapMemory(swapchain_memory);

            @memset(mapped[400 * 240 * 3 * 2..], 0x22);

            try dev.flushMappedMemoryRanges(&.{
                .{
                    .memory = swapchain_memory,
                    .offset = .size(400*240*3*2),
                    .size = .whole,
                }
            });
        }

        const top = try dev.createSwapchain(.{
            .surface = .top_240x400,
            .present_mode = .fifo,
            .image_usage = .{
                .transfer_dst = true,
            },
            .image_format = .b8g8r8_unorm,
            .image_array_layers = .@"1",
            .image_count = 2,
            .image_memory_info = &.{
                .{ .memory = swapchain_memory, .memory_offset = .size(0) },
                .{ .memory = swapchain_memory, .memory_offset = .size(400 * 240 * 3) },
            },
        }, null);
        errdefer dev.destroySwapchain(top, null);

        const bottom = try dev.createSwapchain(.{
            .surface = .bottom_240x320,
            .present_mode = .fifo,
            .image_usage = .{
                .transfer_dst = true,
            },
            .image_format = .b8g8r8_unorm,
            .image_array_layers = .@"1",
            .image_count = 2,
            .image_memory_info = &.{
                .{ .memory = swapchain_memory, .memory_offset = .size(400 * 240 * 3 * 2) },
                .{ .memory = swapchain_memory, .memory_offset = .size(400 * 240 * 3 * 2 + 320 * 240 * 3) },
            },
        }, null);
        errdefer dev.destroySwapchain(bottom, null);

        var top_images: [2]mango.Image = undefined;
        _ = try dev.getSwapchainImages(top, &top_images);

        var bottom_images: [2]mango.Image = undefined;
        _ = try dev.getSwapchainImages(bottom, &bottom_images);

        const color_buffer_memory = try dev.allocateMemory(.{
            .memory_type = .vram_a,
            .allocation_size = .size(400 * 240 * 4 * 2),
        }, null);
        errdefer dev.freeMemory(color_buffer_memory, null);

        var color_buffers: [2]mango.Image = @splat(.null);
        errdefer for (&color_buffers) |buf| if (buf != .null) dev.destroyImage(buf, null);

        var color_buffer_views: [2]mango.ImageView = @splat(.null);
        errdefer for (&color_buffer_views) |view| if (view != .null) dev.destroyImageView(view, null);

        for (&color_buffers, &color_buffer_views, 0..) |*buf, *view, i| {
            buf.* = try dev.createImage(.{
                .flags = .{},
                .type = .@"2d",
                .tiling = .optimal,
                .usage = .{
                    .transfer_src = true,
                    .color_attachment = true,
                },
                .extent = .{ .width = 240, .height = 400 },
                .format = .a8b8g8r8_unorm,
                .mip_levels = .@"1",
                .array_layers = .@"1", 
            }, null);
            try dev.bindImageMemory(buf.*, color_buffer_memory, .size(i * 400 * 240 * 4));

            view.* = try dev.createImageView(.{
                .type = .@"2d",
                .format = .a8b8g8r8_unorm,
                .image = buf.*,
                .subresource_range = .full,
            }, null);
        }

        const sema = try dev.createSemaphore(.initial_zero, null);
        errdefer dev.destroySemaphore(sema, null);

        const pool = try dev.createCommandPool(.no_preheat, null);
        errdefer dev.destroyCommandPool(pool, null);

        var cmd: [2]mango.CommandBuffer = undefined;
        try dev.allocateCommandBuffers(.{
            .pool = pool,
            .command_buffer_count = 2, 
        }, &cmd);
        errdefer dev.freeCommandBuffers(pool, &cmd);

        return .{
            .swapchain_memory = swapchain_memory,
            .top = top,
            .bottom = bottom,
            .top_images = top_images,
            .bottom_images = bottom_images,

            .color_buffer_memory = color_buffer_memory,
            .color_buffers = color_buffers,
            .color_buffer_views = color_buffer_views,

            .sema = sema,
            .pool = pool,
            .cmd = cmd,
            .sync_points = @splat(0),
            .sync = 0,
            .current = 0,
        };
    }

    pub fn deinit(state: *State, dev: mango.Device) void {
        defer state.* = undefined;

        dev.freeCommandBuffers(state.pool, &state.cmd);
        dev.destroyCommandPool(state.pool, null);
        dev.destroySemaphore(state.sema, null);
        for (&state.color_buffer_views) |buf| dev.destroyImageView(buf, null);
        for (&state.color_buffers) |buf| dev.destroyImage(buf, null);
        dev.freeMemory(state.color_buffer_memory, null);

        dev.waitIdle();
        dev.destroySwapchain(state.top, null);
        dev.destroySwapchain(state.bottom, null);
        dev.freeMemory(state.swapchain_memory, null);
    }

    pub fn acquireNextTarget(state: *State, dev: mango.Device) !struct { mango.CommandBuffer, mango.ImageView } {
        state.current +%= 1;
        try dev.waitSemaphores(.init(&.{state.sema}, &.{state.sync_points[state.current]}), std.math.maxInt(u64));
        return .{ state.cmd[state.current], state.color_buffer_views[state.current] };
    }

    pub fn submitBlit(state: *State, dev: mango.Device, clear_color: [4]u8) !void { 
        const top_idx = try dev.acquireNextImage(state.top, std.math.maxInt(u64));
        const bottom_idx = try dev.acquireNextImage(state.bottom, std.math.maxInt(u64));

        const submit = dev.getQueue(.submit);
        const transfer = dev.getQueue(.transfer);
        const fill = dev.getQueue(.fill);
        const present = dev.getQueue(.present);

        // NOTE: we initially zero-filled the memory so it will always be black
        try present.present(.{
            .wait_semaphore = null,
            .swapchain = state.bottom,
            .image_index = bottom_idx,
            .flags = .{},
        });

        try fill.clearColorImage(.{
            .wait_semaphore = &.init(state.sema, state.sync),
            .subresource_range = .full,
            .image = state.color_buffers[state.current],
            .color = clear_color,
            .signal_semaphore = &.init(state.sema, state.sync + 1),
        });

        try submit.submit(.{
            .wait_semaphore = &.init(state.sema, state.sync + 1),
            .command_buffer = state.cmd[state.current],
            .signal_semaphore = &.init(state.sema, state.sync + 2),
        });

        try transfer.blitImage(.{
            .wait_semaphore = &.init(state.sema, state.sync + 2),
            .src_image = state.color_buffers[state.current],
            .dst_image = state.top_images[top_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(state.sema, state.sync + 3),
        });

        try present.present(.{
            .wait_semaphore = &.init(state.sema, state.sync + 3),
            .swapchain = state.top,
            .image_index = top_idx,
            .flags = .{},
        });

        state.sync += 3;
        state.sync_points[state.current] = state.sync;
    }
};

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const horizon = zitrus.horizon;
