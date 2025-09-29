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
    packed_format: u5,
    is_cube: bool,
    base_array_layer: u3,
    base_mip_level: u3,
    levels_minus_one: u3,
    _: u17 = 0,

    pub fn init(info: mango.ImageViewCreateInfo) Data {
        const b_image: *backend.Image = .fromHandleMutable(info.image);

        if (!b_image.info.mutable_format) {
            std.debug.assert(b_image.info.format == info.format);
        }

        switch (info.type) {
            .@"2d" => std.debug.assert(b_image.info.layersByAmount(info.subresource_range.layer_count, info.subresource_range.base_array_layer) == 1),
            .cube => std.debug.assert(b_image.info.layersByAmount(info.subresource_range.layer_count, info.subresource_range.base_array_layer) == 6),
        }

        const mip_levels = b_image.info.levelsByAmount(info.subresource_range.level_count, info.subresource_range.base_mip_level);

        return .{
            .image = info.image,
            .packed_format = @intCast(@intFromEnum(info.format) - 1),
            .is_cube = info.type == .cube,
            .base_array_layer = @intCast(@intFromEnum(info.subresource_range.base_array_layer)),
            .base_mip_level = @intCast(@intFromEnum(info.subresource_range.base_mip_level)),
            .levels_minus_one = @intCast(mip_levels - 1),
        };
    }

    pub fn format(data: Data) mango.Format {
        return @enumFromInt(@as(u8, data.packed_format) + 1);
    }

    pub fn levels(data: Data) usize {
        return @as(usize, data.levels_minus_one) + 1;
    }
};

pub const RenderingInfo = struct {
    width: u16,
    height: u16,
    address: zitrus.hardware.PhysicalAddress,
};

data: Data,

pub const RenderingAttachment = enum { color, depth_stencil };

pub fn getRenderingInfo(view: ImageView, comptime attachment: RenderingAttachment) RenderingInfo {
    std.debug.assert(view.data.levels() == 1);

    const image: backend.Image = .fromHandle(view.data.image);
    const fmt = switch (attachment) {
        .color => view.data.format().nativeColorFormat(),
        .depth_stencil => view.data.format().nativeDepthStencilFormat(),
    };

    const img_width = image.info.width();
    const img_height = image.info.height();

    const view_width = backend.imageLevelDimension(img_width, view.data.base_mip_level);
    const view_height = backend.imageLevelDimension(img_height, view.data.base_mip_level);

    const unscaled_img_offset = (@as(usize, image.info.layer_size) * view.data.base_array_layer) + backend.imageLevelOffset(img_width * img_height, view_width * view_height);
    const img_offset = fmt.bytesPerPixel() * unscaled_img_offset;

    return .{
        .width = @intCast(view_width),
        .height = @intCast(view_height),
        .address = .fromAddress(@intFromEnum(image.memory_info.boundPhysicalAddress()) + img_offset),
    };
}

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
const pica = zitrus.hardware.pica;
