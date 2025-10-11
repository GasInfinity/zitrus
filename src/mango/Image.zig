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

pub const Info = packed struct(u64) {
    width_minus_one: u10,
    height_minus_one: u10,
    format: mango.Format,
    optimally_tiled: bool,
    mutable_format: bool,
    cube_compatible: bool,
    // NOTE: Is not scaled by bpp. The maximum value that this value could be is `1398080`
    layer_size: u22,
    levels_minus_one: u3 = 0,
    layers_minus_one: u3 = 0,
    _: u5 = 0,

    pub fn init(create_info: mango.ImageCreateInfo) Info {
        return .{
            .width_minus_one = @intCast(create_info.extent.width - 1),
            .height_minus_one = @intCast(create_info.extent.height - 1),
            .format = create_info.format,
            .optimally_tiled = switch (create_info.tiling) {
                .optimal => true,
                .linear => false,
            },
            .mutable_format = create_info.flags.mutable_format,
            .cube_compatible = create_info.flags.cube_compatible,
            .layer_size = @intCast(backend.imageLayerSize(@as(usize, create_info.extent.width) * create_info.extent.height, @intFromEnum(create_info.mip_levels))),
            .layers_minus_one = @intCast(@intFromEnum(create_info.array_layers) - 1),
            .levels_minus_one = @intCast(@intFromEnum(create_info.mip_levels) - 1),
        };
    }

    pub fn width(info: Info) u16 {
        return @as(u16, info.width_minus_one) + 1;
    }

    pub fn height(info: Info) u16 {
        return @as(u16, info.height_minus_one) + 1;
    }

    pub fn size(info: Info) usize {
        return info.width() * @as(usize, info.height());
    }

    pub fn layers(info: Info) usize {
        return @as(usize, info.layers_minus_one) + 1;
    }

    pub fn levels(info: Info) usize {
        return @as(usize, info.levels_minus_one) + 1;
    }

    pub fn levelsByAmount(info: Info, amount: mango.ImageMipLevels, base: mango.ImageMipLevel) usize {
        return switch (amount) {
            .remaining => info.levels() - @intFromEnum(base),
            else => @intFromEnum(amount),
        };
    }

    pub fn layersByAmount(info: Info, amount: mango.ImageArrayLayers, base: mango.ImageArrayLayer) usize {
        return switch (amount) {
            .remaining => info.layers() - @intFromEnum(base),
            else => @intFromEnum(amount),
        };
    }
};

pub fn init(create_info: mango.ImageCreateInfo) Image {
    std.debug.assert(create_info.extent.width >= 8 and create_info.extent.width <= 1024 and std.mem.isAligned(create_info.extent.width, 8) and create_info.extent.height >= 8 and create_info.extent.height <= 1024 and std.mem.isAligned(create_info.extent.height, 8));

    if (create_info.usage.sampled) {
        std.debug.assert(std.math.isPowerOfTwo(create_info.extent.width) and std.math.isPowerOfTwo(create_info.extent.height) and create_info.tiling == .optimal);
    } else {
        // NOTE: We could allow this but it doesn't make sense.
        std.debug.assert(create_info.mip_levels == .@"1");
    }

    if (create_info.usage.color_attachment or create_info.usage.depth_stencil_attachment or create_info.usage.shadow_attachment) {
        std.debug.assert(create_info.tiling == .optimal);
    }

    return .{
        .info = .init(create_info),
        .memory_info = .empty,
    };
}

info: Info,
memory_info: DeviceMemory.BoundMemoryInfo,

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
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
