// TODO: This should be one for each screen and should not handle the two at the same time!

pub const Error = error{};

pub const Config = struct {
    pub const ScreenColorFormat = std.EnumArray(Screen, ColorFormat);
    pub const ScreenDoubleBuffer = std.EnumArray(Screen, bool);

    double_buffer: ScreenDoubleBuffer = .initFill(true),
    top_mode: FramebufferMode = .@"2d",
    color_format: ScreenColorFormat = .initFill(.bgr888),
    dma_size: DmaSize = .@"64",
    phys_linear_allocator: Allocator = horizon.heap.linear_page_allocator,
};

config: Config,
current_framebuffer: DoubleBufferIndex = .initFill(0),
top_allocation: []u8,
bottom_allocation: []u8,
top_framebuffer_bytes: usize,
bottom_framebuffer_bytes: usize,

pub fn init(config: Config) !Framebuffers {
    // a.k.a: bpp * w * h * (2 if double buffering) * (2 if running at 240x800, by full_res or 3d)
    const top_framebuffer_bytes = (config.color_format.get(.top).bytesPerPixel() * Screen.top.width() * Screen.top.height()) << @intFromBool(config.top_mode != .@"2d");
    const top_allocation_bytes = top_framebuffer_bytes << @intFromBool(config.double_buffer.get(.top));

    // a.k.a: bpp * w * h * (2 if double buffering)
    const bottom_framebuffer_bytes = (config.color_format.get(.bottom).bytesPerPixel() * Screen.bottom.width() * Screen.bottom.height());
    const bottom_allocation_bytes = bottom_framebuffer_bytes << @intFromBool(config.double_buffer.get(.bottom));

    const top_allocation = try config.phys_linear_allocator.alloc(u8, top_allocation_bytes);
    const bottom_allocation = try config.phys_linear_allocator.alloc(u8, bottom_allocation_bytes);

    return Framebuffers{
        .config = config,
        .top_allocation = top_allocation,
        .bottom_allocation = bottom_allocation,
        .top_framebuffer_bytes = top_framebuffer_bytes,
        .bottom_framebuffer_bytes = bottom_framebuffer_bytes,
    };
}

pub fn deinit(fb: *Framebuffers) void {
    fb.config.phys_linear_allocator.free(fb.top_allocation);
    fb.config.phys_linear_allocator.free(fb.bottom_allocation);
    fb.* = undefined;
}

pub fn currentTopFramebuffers(fb: *Framebuffers) [2][]u8 {
    std.debug.assert(fb.config.top_mode == .@"3d");

    const half_framebuffer_bytes = fb.top_framebuffer_bytes >> 1;
    return .{
        fb.top_allocation[(half_framebuffer_bytes * fb.current_framebuffer.get(.top))..][0..half_framebuffer_bytes],
        fb.top_allocation[(fb.top_framebuffer_bytes + (half_framebuffer_bytes * fb.current_framebuffer.get(.top)))..][0..half_framebuffer_bytes],
    };
}

pub fn currentFramebuffer(fb: *Framebuffers, comptime screen: Screen) []u8 {
    std.debug.assert(fb.config.top_mode != .@"3d");

    return switch (screen) {
        .top => fb.top_allocation[(fb.top_framebuffer_bytes * fb.current_framebuffer.get(.top))..][0..fb.top_framebuffer_bytes],
        .bottom => fb.bottom_allocation[(fb.bottom_framebuffer_bytes * fb.current_framebuffer.get(.bottom))..][0..fb.bottom_framebuffer_bytes],
    };
}

pub fn flushBuffers(fb: *Framebuffers, gsp: GspGpu) !void {
    if (fb.config.top_mode == .@"3d") {
        for (fb.currentTopFramebuffers()) |buffer| {
            try gsp.sendFlushDataCache(buffer);
        }
    } else {
        try gsp.sendFlushDataCache(fb.currentFramebuffer(.top));
    }

    try gsp.sendFlushDataCache(fb.currentFramebuffer(.bottom));
}

pub fn swapBuffers(fb: *Framebuffers, gfx: *Graphics) !void {
    inline for (comptime std.enums.values(Screen)) |screen| {
        fb.current_framebuffer.set(screen, fb.current_framebuffer.get(screen) ^ @intFromBool(fb.config.double_buffer.get(screen)));
    }

    return fb.present(gfx);
}

pub fn present(fb: *Framebuffers, gfx: *Graphics) !void {
    const top_left_framebuffer, const top_right_framebuffer = switch (fb.config.top_mode) {
        .@"2d", .full_resolution => top_fb: {
            const top_framebuffer = fb.currentFramebuffer(.top);
            break :top_fb .{ top_framebuffer, top_framebuffer };
        },
        .@"3d" => fb.currentTopFramebuffers(),
    };

    _ = gfx.shared_memory.framebuffers[gfx.thread_index][@intFromEnum(Screen.top)].update(.{
        .active = .first,
        .left_vaddr = top_left_framebuffer.ptr,
        .right_vaddr = top_right_framebuffer.ptr,
        .stride = (fb.config.color_format.get(.top).bytesPerPixel() * Screen.top.width()) << (if (fb.config.top_mode == .full_resolution) 1 else 0),
        .format = .{
            .color_format = fb.config.color_format.get(.top),
            .dma_size = fb.config.dma_size,

            .interlacing_mode = switch (fb.config.top_mode) {
                .@"2d", .full_resolution => .none,
                .@"3d" => .enable,
            },
            .alternative_pixel_output = fb.config.top_mode == .@"2d",
        },
        .select = 0,
        .attribute = 0,
    });

    const bottom_framebuffer = fb.currentFramebuffer(.bottom);
    _ = gfx.shared_memory.framebuffers[gfx.thread_index][@intFromEnum(Screen.bottom)].update(.{
        .active = .first,
        .left_vaddr = bottom_framebuffer.ptr,
        .right_vaddr = bottom_framebuffer.ptr,
        .stride = fb.config.color_format.get(.bottom).bytesPerPixel() * Screen.bottom.width(),
        .format = .{
            .color_format = fb.config.color_format.get(.bottom),
            .dma_size = fb.config.dma_size,

            .interlacing_mode = .none,
            .alternative_pixel_output = false,
        },
        .select = 0,
        .attribute = 0,
    });
}

const DoubleBufferIndex = std.EnumArray(Screen, u1);
const Framebuffers = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.pica;

const horizon = zitrus.horizon;

const Allocator = std.mem.Allocator;
const GspGpu = horizon.services.GspGpu;
const Graphics = horizon.services.GspGpu.Graphics;

const Screen = gpu.Screen;
const ColorFormat = gpu.ColorFormat;
const DmaSize = gpu.DmaSize;
const FramebufferMode = gpu.FramebufferFormat.Mode;
