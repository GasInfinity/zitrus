//! A PICA200 image
//!
//! Images have numerous usages and thus they can be sampled, rendered to, and presented as an LCD framebuffer.
//!
//! However the PICA200 imposes some limitations:
//!     - Sampled images MUST be optimally tiled, powers of two and have a size of `[8, 1024]`.
//!     - Color / Depth attachment images MUST be optimally tiled, divisible by the attachment render block size {8, 32} (TODO), be device local, and have a size `[8, 1024]`.
//!
//!
//! There's one more limitation which is not imposed by the PICA200 but by the LCD framebuffers, images must be linearly tiled.

pub const Handle = enum(u32) {
    null = 0,
    _,
};

pub const Info = packed struct(u32) {
    width_minus_one: u10,
    height_minus_one: u10,
    usage: mango.ImageCreateInfo.Usage,
    optimally_tiled: bool,
    mutable_format: bool,
    cube_compatible: bool,
    _: bool = false,

    pub fn init(create_info: mango.ImageCreateInfo) Info {
        return .{
            .width_minus_one = @intCast(create_info.extent.width - 1),
            .height_minus_one = @intCast(create_info.extent.height - 1),
            .usage = create_info.usage,
            .optimally_tiled = switch (create_info.tiling) {
                .optimal => true,
                .linear => false,
            },
            .mutable_format = create_info.flags.mutable_format,
            .cube_compatible = create_info.flags.cube_compatible,
        };
    }

    pub fn width(info: Info) usize {
        return @as(usize, info.width_minus_one) + 1;
    }

    pub fn height(info: Info) usize {
        return @as(usize, info.height_minus_one) + 1;
    }
};

memory_info: DeviceMemory.BoundMemoryInfo,
format: mango.Format,
info: Info,

pub fn toHandle(image: *Image) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *Image {
    return @as(*Image, @ptrFromInt(@intFromEnum(handle)));
}

pub fn fromHandle(handle: Handle) Image {
    return fromHandleMutable(handle).*;
}

const Image = @This();
const backend = @import("backend.zig");
const DeviceMemory = backend.DeviceMemory;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
