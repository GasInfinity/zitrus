pub const empty: Framebuffer = .{
    .color = .empty,
    .depth = .empty,
};

color: Attachment,
depth: Attachment,

pub fn init(dev: mango.Device, w: u16, h: u16, color_fmt: mango.Format, depth_fmt: mango.Format) !Framebuffer {
    const color: Attachment = if (color_fmt != .undefined) try .init(dev, w, h, color_fmt, .a, .{ .color_attachment = true }) else .empty;
    errdefer color.deinit(dev);

    const depth: Attachment = if (depth_fmt != .undefined) try .init(dev, w, h, depth_fmt, .b, .{ .depth_stencil_attachment = true }) else .empty;
    errdefer depth.deinit(dev);

    return .{
        .color = color,
        .depth = depth,
    };
}

pub fn deinit(fb: Framebuffer, dev: mango.Device) void {
    fb.color.deinit(dev);
    fb.depth.deinit(dev);
}

pub const Attachment = struct {
    pub const empty: Attachment = .{
        .mem = &.{},
        .image = .null,
        .view = .null,
    };

    mem: []const u8,
    image: mango.Image,
    view: mango.ImageView,

    pub fn init(dev: mango.Device, w: u16, h: u16, fmt: mango.Format, bank: mango.PrivateMemoryIndex, usage: mango.ImageCreateInfo.Usage) !Attachment {
        const mem = try dev.allocatePrivate(bank, fmt.scale(@as(usize, w) * h)); 
        errdefer dev.freePrivate(mem);

        const img = try dev.createImage(.{
            .flags = .{},
            .tiling = .optimal,
            .usage = usage,
            .extent = .{ .width = w, .height = h },
            .format = fmt,
            .mip_levels = .@"1",
            .array_layers = .@"1",
        });
        errdefer dev.destroyImage(img);
        try dev.bindImageMemory(img, try dev.hostToDevice(mem));

        const view = try dev.createImageView(.{
            .type = .@"2d",
            .format = fmt,
            .image = img,
            .subresource_range = .full,
        });
        errdefer dev.destroyImageView(img);

        return .{
            .mem = mem,
            .image = img,
            .view = view,
        };
    }

    pub fn deinit(att: Attachment, dev: mango.Device) void {
        if (att.view != .null) {
            dev.destroyImageView(att.view);
            dev.destroyImage(att.image);
            dev.freePrivate(att.mem);
        } 
    }
};

const Framebuffer = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const horizon = zitrus.horizon;
