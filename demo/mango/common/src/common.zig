pub const State = struct {
    fcram: std.mem.Allocator,

    swapchain_memory: []u8,
    top_images: [2]mango.Image,
    bottom_images: [2]mango.Image,

    color_buffer_memory: []const u8,
    color_buffers: [2]mango.Image,
    color_buffer_views: [2]mango.ImageView,

    sema: mango.Semaphore,
    pool: mango.CommandPool,
    cmd: [2]mango.CommandBuffer,
    sync_points: [2]u64,
    sync: u64,
    current: u1,

    pub fn init(dev: mango.Device) !State {
        const fcram = dev.hostAllocator();

        const swapchain_memory = try fcram.alloc(u8, 400 * 240 * 3 * 2 + 320 * 240 * 3 * 2);
        errdefer fcram.free(swapchain_memory);
        const swapchain_memory_gpu = try dev.hostToDevice(swapchain_memory);
        
        {
            @memset(swapchain_memory[400*240*3*2..], 0x22);
            try dev.flushCachedMemoryRanges(&.{swapchain_memory[400*240*3*2..]});
        }

        try dev.configureDisplay(.top, &.{
            .extent = .{ .width = 240, .height = 400 },
            .present_mode = .fifo,
            .image_format = .b8g8r8_unorm,
            .image_array_layers = .@"1",
            .image_count = 2,
            .image_memory = &.{ swapchain_memory_gpu, swapchain_memory_gpu.openSlice(400*240*3) },
        });

        try dev.configureDisplay(.bottom, &.{
            .extent = .{ .width = 240, .height = 320 },
            .present_mode = .fifo,
            .image_format = .b8g8r8_unorm,
            .image_array_layers = .@"1",
            .image_count = 2,
            .image_memory = &.{ swapchain_memory_gpu.openSlice(400*240*3*2), swapchain_memory_gpu.openSlice(400*240*3*2+320*240*3) },
        });

        var top_images: [2]mango.Image = undefined;
        _ = try dev.getDisplayImages(.top, &top_images);

        var bottom_images: [2]mango.Image = undefined;
        _ = try dev.getDisplayImages(.bottom, &bottom_images);

        const color_buffer_memory = try dev.allocatePrivate(.a, 400 * 240 * 4 * 2);
        errdefer dev.freePrivate(color_buffer_memory);
        const color_buffer_memory_gpu = try dev.hostToDevice(color_buffer_memory);

        var color_buffers: [2]mango.Image = @splat(.null);
        errdefer for (&color_buffers) |buf| if (buf != .null) dev.destroyImage(buf);

        var color_buffer_views: [2]mango.ImageView = @splat(.null);
        errdefer for (&color_buffer_views) |view| if (view != .null) dev.destroyImageView(view);

        for (&color_buffers, &color_buffer_views, 0..) |*buf, *view, i| {
            buf.* = try dev.createImage(.{
                .flags = .{},
                .tiling = .optimal,
                .usage = .{
                    .color_attachment = true,
                },
                .extent = .{ .width = 240, .height = 400 },
                .format = .a8b8g8r8_unorm,
                .mip_levels = .@"1",
                .array_layers = .@"1", 
            });
            try dev.bindImageMemory(buf.*, color_buffer_memory_gpu.openSlice(i * 400 * 240 * 4));

            view.* = try dev.createImageView(.{
                .type = .@"2d",
                .format = .a8b8g8r8_unorm,
                .image = buf.*,
                .subresource_range = .full,
            });
        }

        const sema = try dev.createSemaphore(.initial_zero);
        errdefer dev.destroySemaphore(sema);

        const pool = try dev.createCommandPool(.no_preheat);
        errdefer dev.destroyCommandPool(pool);

        var cmd: [2]mango.CommandBuffer = undefined;
        try dev.allocateCommandBuffers(.{
            .pool = pool,
            .command_buffer_count = 2, 
        }, &cmd);
        errdefer dev.freeCommandBuffers(pool, &cmd);

        return .{
            .fcram = fcram,

            .swapchain_memory = swapchain_memory,
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

        // NOTE: we have to wait for the command buffers (GPU may be still processing one) AND swapchains (we may have some presents left)
        dev.waitIdle();

        dev.freeCommandBuffers(state.pool, &state.cmd);
        dev.destroyCommandPool(state.pool);
        dev.destroySemaphore(state.sema);
        for (&state.color_buffer_views) |buf| dev.destroyImageView(buf);
        for (&state.color_buffers) |buf| dev.destroyImage(buf);
        dev.freePrivate(state.color_buffer_memory);
        dev.resetDisplay(.top);
        dev.resetDisplay(.bottom);
        state.fcram.free(state.swapchain_memory);
    }

    pub fn acquireNextTarget(state: *State, dev: mango.Device) !struct { mango.CommandBuffer, mango.ImageView } {
        state.current +%= 1;
        try dev.waitSemaphores(.init(&.{state.sema}, &.{state.sync_points[state.current]}), std.math.maxInt(u64));
        return .{ state.cmd[state.current], state.color_buffer_views[state.current] };
    }

    pub fn submitBlit(state: *State, dev: mango.Device, clear_color: [4]u8) !void { 
        const top_idx = try dev.acquireNextImage(.top, std.math.maxInt(u64));
        const bottom_idx = try dev.acquireNextImage(.bottom, std.math.maxInt(u64));

        // NOTE: we initially zero-filled the memory so it will always be black
        try dev.present(null, &.{
            .display = .bottom,
            .image_index = bottom_idx,
            .flags = .{},
        });

        try dev.clearColorImage(&.init(state.sema, state.sync), &.init(state.sema, state.sync + 1), &.{
            .subresource_range = .full,
            .image = state.color_buffers[state.current],
            .color = clear_color,
        });

        try dev.submit(&.init(state.sema, state.sync + 1), &.init(state.sema, state.sync + 2), &.{
            .command_buffer = state.cmd[state.current],
        });

        try dev.blitImage(&.init(state.sema, state.sync + 2), &.init(state.sema, state.sync + 3), &.{
            .src_image = state.color_buffers[state.current],
            .dst_image = state.top_images[top_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
        });

        try dev.present(&.init(state.sema, state.sync + 3), &.{
            .display = .top,
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
