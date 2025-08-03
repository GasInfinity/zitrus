//! A PICA200 image view
//!
//! Represents a view of an Image which for example can be:
//!     - A face of a cubemap or the cubemap itself.
//!     - An a8_unorm image reinterpreted as an i8_unorm

pub const Type = enum(u8) {
    @"2d",    
    cube,
};

pub const CreateInfo = extern struct {
    type: Type,
    format: mango.Format,
    image: *mango.Image,
    // TODO: subresource range with the mip levels and array layers (for cubemaps)
};

type: Type,
format: mango.Format,
image: *mango.Image,

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
