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

pub const Type = enum(u8) {
    @"2d",    
};

pub const Tiling = enum(u8) {
    /// The images are tiled in a PICA200 specific format (8x8 or 32x32 tiles).
    optimal,
    /// The images are linearly stored.
    linear,
};

pub const Usage = packed struct(u8) {
    /// Specifies that the image can be used as the source of a transfer operation.
    transfer_src: bool = false,
    /// Specifies that the image can be used as the destination of a transfer operation.
    transfer_dst: bool = false,
    /// Specifies that the image can be used to create an ImageView suitable for binding with a sampler.
    sampled: bool = false,
    /// Specifies that the image can be used to create an ImageView suitable for use as a color attachment.
    color_attachment: bool = false,
    /// Specifies that the image can be used to create an ImageView suitable for use as a depth-stencil attachment.
    depth_stencil_attachment: bool = false,
    /// Specifies that the image can be used to create an ImageView suitable for use as a shadow attachment.
    shadow_attachment: bool = false,
    _: u2 = 0,
};

pub const CreateInfo = extern struct {
    pub const Flags = packed struct(u8) {
        /// Specifies that the image can be used to create an ImageView with a different format from the image.
        mutable_format: bool = false,
        /// Specifies that the image can be used to create an ImageView of type `cube`
        cube_compatible: bool = false,
        _: u6 = 0,
    };

    flags: Flags,
    type: Type,
    tiling: Tiling,
    usage: Usage,
    extent: mango.Extent2D,
    format: mango.Format,
    mip_levels: u8,
    array_layers: u8,
};

pub const Info = packed struct {
    width_minus_one: u10,
    height_minus_one: u10,
    usage: Usage,
    optimally_tiled: bool,
    mutable_format: bool,
    cube_compatible: bool,

    pub fn init(create_info: CreateInfo) Info {
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

info: Info,
address: PhysicalAddress,

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
