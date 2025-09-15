pub const Config = struct {
    screen: pica.Screen,
    double_buffer: bool = true,
    mode: FramebufferMode = .@"2d",
    color_format: pica.ColorFormat = .bgr888,
    dma_size: DmaSize = .@"64",
};

pub const Side = enum(u1) { left, right };
pub const IgnoreStereo = enum(u1) { none, ignore_stereo };

config: Config,
current_framebuffer: u1 = 0,
allocation: []u8,
framebuffer_bytes: usize,

pub fn init(config: Config, physical_linear_allocator: std.mem.Allocator) !Framebuffer {
    std.debug.assert((config.screen == .bottom and config.mode == .@"2d") or (config.screen == .top)); // Bottom screen can only be in 2D mode

    // a.k.a: bpp * w * h * (2 if double buffering) * (2 if running at 240x800, by full_res or 3d)
    const framebuffer_bytes = (config.color_format.bytesPerPixel() * config.screen.width() * config.screen.height()) << @intFromBool(config.mode != .@"2d");
    const allocation_bytes = framebuffer_bytes << @intFromBool(config.double_buffer);

    const allocation = try physical_linear_allocator.alloc(u8, allocation_bytes);

    return Framebuffer{
        .config = config,
        .allocation = allocation,
        .framebuffer_bytes = framebuffer_bytes,
    };
}

pub fn deinit(fb: *Framebuffer, physical_linear_allocator: std.mem.Allocator) void {
    physical_linear_allocator.free(fb.allocation);
    fb.* = undefined;
}

pub fn currentFramebuffer(fb: *Framebuffer, side: Side) []u8 {
    std.debug.assert((fb.config.mode != .@"3d" and side != .right) or fb.config.mode == .@"3d");

    return fb.allocation[(fb.framebuffer_bytes * fb.current_framebuffer) + (@intFromEnum(side) * (fb.framebuffer_bytes >> 1)) ..][0..(fb.framebuffer_bytes >> @intFromBool(fb.config.mode == .@"3d"))];
}

pub fn flushBuffer(fb: *Framebuffer, gsp: GspGpu) !void {
    try gsp.sendFlushDataCache(fb.allocation);
}

pub fn swapBuffer(fb: *Framebuffer, gfx: *Graphics, ignore_stereo: IgnoreStereo) !void {
    fb.current_framebuffer ^= @intFromBool(fb.config.double_buffer);
    return fb.present(gfx, ignore_stereo);
}

pub fn present(fb: *Framebuffer, gfx: *Graphics, ignore_stereo: IgnoreStereo) !void {
    _ = gfx.shared_memory.framebuffers[gfx.thread_index][@intFromEnum(fb.config.screen)].update(.{
        .active = @enumFromInt(fb.current_framebuffer),
        .left_vaddr = fb.currentFramebuffer(.left).ptr,
        .right_vaddr = (if (fb.config.mode == .@"3d" and (ignore_stereo == .ignore_stereo)) fb.currentFramebuffer(.right) else fb.currentFramebuffer(.left)).ptr,
        .stride = (fb.config.color_format.bytesPerPixel() * fb.config.screen.width()) << @intFromBool(fb.config.mode == .full_resolution),
        .format = .{
            .color_format = fb.config.color_format,
            .dma_size = fb.config.dma_size,

            .interlacing_mode = switch (fb.config.mode) {
                .@"2d", .full_resolution => .none,
                .@"3d" => .enable,
            },
            .alternative_pixel_output = fb.config.screen == .top and fb.config.mode == .@"2d",
        },
        .select = fb.current_framebuffer,
        .attribute = 0,
    });
}

const Framebuffer = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.pica;

const horizon = zitrus.horizon;

const Allocator = std.mem.Allocator;
const GspGpu = horizon.services.GspGpu;
const Graphics = horizon.services.GspGpu.Graphics;

const DmaSize = pica.DmaSize;
const FramebufferMode = pica.FramebufferFormat.Mode;
