//! A PICA200 image view
//!
//! Represents a view of an Image which for example can be:
//!     - A face of a cubemap or the cubemap itself.
//!     - An a8_unorm image reinterpreted as an i8_unorm

pub const Handle = enum(u64) {
    null = 0,
    _,
};

pub const Data = packed struct(u64) {
    image: mango.Image,
    format: mango.Format,
    is_cube: bool,
    _: u23 = 0,

    pub fn init(create_info: mango.ImageViewCreateInfo) Data {
        const b_image: *backend.Image = .fromHandleMutable(create_info.image);

        if (!b_image.info.mutable_format) {
            std.debug.assert(b_image.format == create_info.format);
        }

        return .{
            .image = create_info.image,
            .format = create_info.format,
            .is_cube = false, // TODO: Cubemaps
        };
    }
};

data: Data,

pub fn toHandle(view: ImageView) Handle {
    return @enumFromInt(@as(u64, @bitCast(view.data)));
}

pub fn fromHandle(handle: Handle) ImageView {
    // TODO: With runtime safety the handle is a real pointer with some metadata
    return .{
        .data = @bitCast(@intFromEnum(handle)),
    };
}

const ImageView = @This();
const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
