//! High-level abstraction around software rendering.
//!
//! If you need more control, you can use this as a reference
//! of how should things be done.
//!
//! It initializes both screens to black and turns off LCD fill.
//!
//! Use this for prototypes or simple apps as `mango` is preferred!

pub const Config = struct {
    top_mode: pica.FramebufferFormat.Mode,
    double_buffer: std.EnumArray(pica.Screen, bool),
    color_format: std.EnumArray(pica.Screen, pica.ColorFormat),
    /// The initial contents to copy into the framebuffer before turning
    /// LCD fill off. If null it'll be filled with black.
    ///
    /// Asserts that the buffer has at least W * H * BPP bytes.
    initial_contents: std.EnumArray(pica.Screen, ?[]const u8),
};

gfx: Graphics,
top: Framebuffer,
bottom: Framebuffer,

pub fn init(config: Config, gsp: GspGpu, physical_linear_allocator: std.mem.Allocator) !Software {
    var gfx = try Graphics.init(gsp);
    errdefer gfx.deinit(gsp);

    var top = try Framebuffer.init(.{
        .screen = .top,
        .mode = config.top_mode,
        .double_buffer = config.double_buffer.get(.top),
        .color_format = config.color_format.get(.top),
    }, physical_linear_allocator);
    errdefer top.deinit(physical_linear_allocator);

    var bottom = try Framebuffer.init(.{
        .screen = .bottom,
        .mode = .@"2d",
        .double_buffer = config.double_buffer.get(.bottom),
        .color_format = config.color_format.get(.bottom),
    }, physical_linear_allocator);
    errdefer bottom.deinit(physical_linear_allocator);

    if (config.initial_contents.get(.top)) |initial| {
        @memcpy(top.current(.left), initial);
    } else @memset(top.current(.left), 0x00);

    if (config.initial_contents.get(.bottom)) |initial| {
        @memcpy(bottom.current(.left), initial);
    } else @memset(bottom.current(.left), 0x00);

    var soft: Software = .{
        .gfx = gfx,
        .top = top,
        .bottom = bottom,
    };

    soft.flush();
    soft.swap(.ignore_stereo);
    try soft.waitVBlank();
    try gsp.sendSetLcdForceBlack(false);

    return soft;
}

pub fn deinit(soft: *Software, gsp: GspGpu, physical_linear_allocator: std.mem.Allocator, must_close: bool) void {
    if (!must_close) {
        soft.waitVBlank() catch {};
        gsp.sendSetLcdForceBlack(true) catch {};
    }

    soft.bottom.deinit(physical_linear_allocator);
    soft.top.deinit(physical_linear_allocator);
    soft.gfx.deinit(gsp);
    soft.* = undefined;
}

/// Flushes both framebuffers
///
/// Must be called after modifying backbuffer contents.
pub fn flush(soft: *Software) void {
    soft.top.flush();
    soft.bottom.flush();
}

/// Updates the next presentation at VBlank and swaps buffers (if double-buffered).
pub fn swap(soft: *Software, ignore_stereo: Framebuffer.IgnoreStereo) void {
    soft.top.swap(&soft.gfx, ignore_stereo);
    soft.bottom.swap(&soft.gfx, ignore_stereo);
}

pub fn current(soft: *Software, screen: pica.Screen, side: Framebuffer.Side) []u8 {
    return switch (screen) {
        .top => soft.top.current(side),
        .bottom => soft.bottom.current(.left),
    };
}

/// Waits for the next VBlank on both screens.
pub fn waitVBlank(soft: *Software) !void {
    soft.gfx.discardInterrupts();

    var top = false;
    var bottom = false;

    while (!top or !bottom) {
        const interrupts = try soft.gfx.waitInterrupts();

        if (interrupts.contains(.vblank_top)) top = true;
        if (interrupts.contains(.vblank_bottom)) bottom = true;
    }
}

const Software = @This();
const GspGpu = horizon.services.GspGpu;
const Graphics = GspGpu.Graphics;
const Framebuffer = Graphics.Framebuffer;

const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;

const horizon = zitrus.horizon;
const memory = horizon.memory;
const tls = horizon.tls;
const ipc = horizon.ipc;
