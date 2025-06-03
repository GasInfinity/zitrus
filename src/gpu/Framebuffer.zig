pub const Error = error{};

pub const Config = struct {
    pub const ScreenColorFormat = std.EnumArray(Screen, GspGpu.ColorFormat);
    pub const ScreenDoubleBuffer = std.EnumArray(Screen, bool);

    double_buffer: ScreenDoubleBuffer = .initFill(true),
    top_mode: GspGpu.FramebufferMode = .@"2d",
    color_format: ScreenColorFormat = .initFill(.bgr8),
    dma_size: GspGpu.DmaSize = .@"128",
    phys_linear_allocator: Allocator = horizon.linear_page_allocator,
};

config: Config,
current_framebuffer: DoubleBufferIndex = .initFill(0),
top_allocation: []u8,
bottom_allocation: []u8,
top_framebuffer_bytes: usize,
bottom_framebuffer_bytes: usize,

pub fn init(config: Config) !Framebuffer {
    // a.k.a: bpp * w * h * (2 if double buffering) * (2 if running at 240x800, by full_res or 3d)
    const top_framebuffer_bytes = (config.color_format.get(.top).bytesPerPixel() * Screen.top.width() * Screen.top.height()) << @intFromBool(config.top_mode != .@"2d");
    const top_allocation_bytes = top_framebuffer_bytes << @intFromBool(config.double_buffer.get(.top));

    // a.k.a: bpp * w * h * (2 if double buffering)
    const bottom_framebuffer_bytes = (config.color_format.get(.bottom).bytesPerPixel() * Screen.bottom.width() * Screen.bottom.height());
    const bottom_allocation_bytes = bottom_framebuffer_bytes << @intFromBool(config.double_buffer.get(.bottom));

    const top_allocation = try config.phys_linear_allocator.alloc(u8, top_allocation_bytes);
    const bottom_allocation = try config.phys_linear_allocator.alloc(u8, bottom_allocation_bytes);

    return Framebuffer{
        .config = config,
        .top_allocation = top_allocation,
        .bottom_allocation = bottom_allocation,
        .top_framebuffer_bytes = top_framebuffer_bytes,
        .bottom_framebuffer_bytes = bottom_framebuffer_bytes,
    };
}

pub fn deinit(fb: *Framebuffer) void {
    fb.config.phys_linear_allocator.free(fb.top_allocation);
    fb.config.phys_linear_allocator.free(fb.bottom_allocation);
    fb.* = undefined;
}

pub fn currentTopFramebuffers(fb: *Framebuffer) [2][]u8 {
    std.debug.assert(fb.config.top_mode == .@"3d");

    const half_framebuffer_bytes = fb.top_framebuffer_bytes >> 1;
    return .{
        fb.top_allocation[(half_framebuffer_bytes * fb.current_framebuffer.get(.top))..][0..half_framebuffer_bytes],
        fb.top_allocation[(fb.top_framebuffer_bytes + (half_framebuffer_bytes * fb.current_framebuffer.get(.top)))..][0..half_framebuffer_bytes],
    };
}

pub fn currentFramebuffer(fb: *Framebuffer, comptime screen: Screen) []u8 {
    std.debug.assert(fb.config.top_mode != .@"3d");

    return switch (screen) {
        .top => fb.top_allocation[(fb.top_framebuffer_bytes * fb.current_framebuffer.get(.top))..][0..fb.top_framebuffer_bytes],
        .bottom => fb.bottom_allocation[(fb.bottom_framebuffer_bytes * fb.current_framebuffer.get(.bottom))..][0..fb.bottom_framebuffer_bytes],
    };
}

pub fn flushBuffers(fb: *Framebuffer, gpu: *GspGpu) !void {
    if (fb.config.top_mode == .@"3d") {
        for (fb.currentTopFramebuffers()) |buffer| {
            try gpu.sendFlushDataCache(buffer);
        }
    } else {
        try gpu.sendFlushDataCache(fb.currentFramebuffer(.top));
    }

    try gpu.sendFlushDataCache(fb.currentFramebuffer(.bottom));
}

pub fn swapBuffers(fb: *Framebuffer, gpu: *GspGpu) !void {
    // Swap buffers after presenting the current back-buffer
    defer inline for (comptime std.enums.values(Screen)) |screen| {
        fb.current_framebuffer.set(screen, fb.current_framebuffer.get(screen) ^ @intFromBool(fb.config.double_buffer.get(screen)));
    };

    return fb.present(gpu);
}

pub fn present(fb: *Framebuffer, gpu: *GspGpu) !void {
    const current_top_framebuffer: usize = fb.current_framebuffer.get(.top);
    const top_left_framebuffer, const top_right_framebuffer = switch (fb.config.top_mode) {
        .@"2d", .full_resolution => top_fb: {
            const top_framebuffer = fb.currentFramebuffer(.top);
            break :top_fb .{ top_framebuffer, top_framebuffer };
        },
        .@"3d" => fb.currentTopFramebuffers(),
    };

    _ = try gpu.presentFramebuffer(.top, .{
        .active = @enumFromInt(current_top_framebuffer),
        .color_format = fb.config.color_format.get(.top),
        .left_vaddr = top_left_framebuffer.ptr,
        .right_vaddr = top_right_framebuffer.ptr,
        .stride = (fb.config.color_format.get(.top).bytesPerPixel() * GspGpu.Screen.top.width()) << (if (fb.config.top_mode == .full_resolution) 1 else 0),
        .mode = fb.config.top_mode,
        .dma_size = fb.config.dma_size,
    });

    const current_bottom_framebuffer: usize = fb.current_framebuffer.get(.bottom);
    const bottom_framebuffer = fb.currentFramebuffer(.bottom);
    _ = try gpu.presentFramebuffer(.bottom, .{
        .active = @enumFromInt(current_bottom_framebuffer),
        .color_format = fb.config.color_format.get(.bottom),
        .left_vaddr = bottom_framebuffer.ptr,
        .right_vaddr = bottom_framebuffer.ptr,
        .stride = fb.config.color_format.get(.bottom).bytesPerPixel() * GspGpu.Screen.bottom.width(),
        .dma_size = fb.config.dma_size,
    });
}

const DoubleBufferIndex = std.EnumArray(GspGpu.Screen, u1);
const Framebuffer = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const Allocator = std.mem.Allocator;
const GspGpu = horizon.services.GspGpu;
const Screen = GspGpu.Screen;
