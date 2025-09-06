//! Wraps LCD surfaces for PICA200 output for presentation.
//!
//! Swapchains don't allocate memory by themselves, they are linked with up to
//! two linearly tiled `Image`s and one optimally tiled image for render output.
//!
//! They double-buffer (if two images are provided) the linear images on the screen and automatically
//! does a copyImageToImage before presentation.
//!
//! As `Swapchain`s don't own its data, you're free to recreate swapchains with different formats dynamically.
//! As only 2 swapchains can be created at the same time (top and bottom), their data is embedded in the presentation engine.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

pub fn toHandle(screen: pica.Screen) Handle {
    return @enumFromInt(@as(u32, @intFromEnum(screen)) + 1);
}

pub fn fromHandle(handle: Handle) pica.Screen {
    return @enumFromInt(@intFromEnum(handle) - 1);
}

const Swapchain = @This();
const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const pica = zitrus.pica;
