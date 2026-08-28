fcram: std.mem.Allocator,

swapchain_memory: []u8,
top_images: [2]mango.Image,
bottom_images: [2]mango.Image,

sema: mango.Semaphore,
pool: mango.CommandPool,
cmd: [2]mango.CommandBuffer,
sync_points: [2]u64,
sync: u64,
current: u1,

pub fn init(dev: mango.Device, stereo: bool) !State {
    const fcram = dev.hostAllocator();

    const stereo_factor = @as(usize, @intFromBool(stereo)) + 1;

    const swapchain_memory = try fcram.alloc(u8, 400 * 240 * 3 * stereo_factor * 2 + 320 * 240 * 3 * 2);
    errdefer fcram.free(swapchain_memory);
    const swapchain_memory_gpu = try dev.hostToDevice(swapchain_memory);
    
    {
        @memset(swapchain_memory[400*240*3*2*stereo_factor..], 0x22);
        try dev.flushCachedMemoryRanges(&.{swapchain_memory[400*240*3*stereo_factor*2..]});
    }

    try dev.configureDisplay(.top, &.{
        .extent = .{ .width = 240, .height = 400 },
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = @enumFromInt(stereo_factor),
        .image_count = 2,
        .image_memory = &.{ swapchain_memory_gpu, swapchain_memory_gpu.openSlice(400*240*3*stereo_factor) },
    });

    try dev.configureDisplay(.bottom, &.{
        .extent = .{ .width = 240, .height = 320 },
        .present_mode = .fifo,
        .image_format = .b8g8r8_unorm,
        .image_array_layers = .@"1",
        .image_count = 2,
        .image_memory = &.{ swapchain_memory_gpu.openSlice(400*240*3*stereo_factor*2), swapchain_memory_gpu.openSlice(400*240*3*stereo_factor*2+320*240*3) },
    });

    var top_images: [2]mango.Image = undefined;
    _ = try dev.getDisplayImages(.top, &top_images);

    var bottom_images: [2]mango.Image = undefined;
    _ = try dev.getDisplayImages(.bottom, &bottom_images);

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
    dev.resetDisplay(.top);
    dev.resetDisplay(.bottom);
    state.fcram.free(state.swapchain_memory);
}

pub fn acquireNext(state: *State, dev: mango.Device) !mango.CommandBuffer {
    state.current +%= 1;
    try dev.waitSemaphores(.init(&.{state.sema}, &.{state.sync_points[state.current]}), std.math.maxInt(u64));
    return state.cmd[state.current];
}

pub fn syncNext(state: *State) void {
    state.sync_points[state.current] = state.sync;
}

const State = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const horizon = zitrus.horizon;
