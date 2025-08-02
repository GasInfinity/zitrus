//! Wraps LCD surfaces for PICA200 output.
//!
//! Swapchains don't allocate memory by themselves, they are linked with up to
//! two linearly tiled `Image`s and one optimally tiled image for render output.
//!
//! They double-buffer (if two images are provided) the linear images on the screen and automatically
//! does a copyImageToImage before presentation.
//!
//! As `Swapchain`s don't own its data, you're free to recreate swapchains with different formats dynamically.

const Swapchain = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
