//! Wraps LCD surfaces for PICA200 output for presentation.
//!
//! Swapchains don't allocate memory by themselves, they are linked with up to
//! two linearly tiled `Image`s and one optimally tiled image for render output.
//!
//! They double-buffer (if two images are provided) the linear images on the screen and automatically
//! does a copyImageToImage before presentation.
//!
//! As `Swapchain`s don't own its data, you're free to recreate swapchains with different formats dynamically.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

pub const Info = packed struct(u32) {
    pub const PresentMode = enum(u2) {
        mailbox,
        fifo,
        fifo_relaxed,
        fifo_latest_ready,
    };

    present_mode: PresentMode,
    is_stereo: bool,
    fmt: pica.ColorFormat,
};

info: Info,
images: backend.DeviceMemory.BoundMemoryInfo,

const Swapchain = @This();
const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
