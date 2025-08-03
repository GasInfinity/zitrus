//! Represents the PICA200 GPU as a whole.
//!
//! As the GPU is not a standard one, there are lots of simplifications made:
//!     - It only supports one queue with:
//!         * DMA: copyBuffer, copyBufferToImage (with memcpy flag), copyImageToBuffer (with memcpy flag).
//!         * Memory Fills: fillBuffer, clearColorImage, clearDepthStencilImage (they are queue operations instead of command buffer ones!)
//!         * Transfer Engine / Display Transfer: present, copyBufferToImage, copyImageToBuffer, copyImageToImage, blitImage
//!         * 3D Command List: submit

// TODO: Synchronization primitives.

pub const CreateInfo = extern struct {
};

pub fn createBuffer(device: *Device, create_info: mango.Buffer.CreateInfo, allocator: std.mem.Allocator) !*mango.Buffer {
    _ = device;

    const buffer = try allocator.create(mango.Buffer);
    errdefer allocator.destroy(buffer);

    buffer.* = .{
        .address = .zero,
        .size = create_info.size,
        .usage = create_info.usage,
    };

    return buffer;
}

pub fn destroyBuffer(device: *Device, buffer: *mango.Buffer, allocator: std.mem.Allocator) void {
    _ = device;
    allocator.destroy(buffer);
}

pub fn bindBufferMemory(device: *Device, buffer: *mango.Buffer, memory: *mango.DeviceMemory, memory_offset: usize) !void {
    _ = device;
    std.debug.assert(buffer.address == .zero);
    std.debug.assert(memory_offset + buffer.size <= memory.size);

    buffer.address = .fromAddress(@intFromEnum(memory.physical) + memory_offset);
}

pub fn createImage(device: *Device, create_info: mango.Image.CreateInfo, allocator: std.mem.Allocator) !*mango.Image {
    _ = device;

    std.debug.assert(create_info.extent.width >= 8 and create_info.extent.width <= 1024 and std.mem.isAligned(create_info.extent.width, 8) and create_info.extent.height >= 8 and create_info.extent.height <= 1024 and std.mem.isAligned(create_info.extent.height, 8));

    if(create_info.usage.sampled) {
        std.debug.assert(std.math.isPowerOfTwo(create_info.extent.width) and std.math.isPowerOfTwo(create_info.extent.width) and create_info.tiling == .optimal);
    }

    if(create_info.usage.color_attachment or create_info.usage.depth_stencil_attachment or create_info.usage.shadow_attachment) {
        std.debug.assert(create_info.tiling == .optimal);
    }

    const image = try allocator.create(mango.Image);
    errdefer allocator.destroy(image);

    image.* = .{
        .address = .zero,
        .info = .init(create_info),
    };

    return image;
}

pub fn destroyImage(device: *Device, image: *mango.Image, allocator: std.mem.Allocator) void {
    _ = device;
    allocator.destroy(image);
}

pub fn bindImageMemory(device: *Device, image: *mango.Image, memory: *mango.DeviceMemory, memory_offset: usize) !void {
    _ = device;

    std.debug.assert(image.address == .zero);
    // TODO: std.debug.assert(memory_offset + image.size() <= memory.size);

    image.address = .fromAddress(@intFromEnum(memory.physical) + memory_offset);
}

pub fn createImageView(device: *Device, create_info: mango.ImageView.CreateInfo, allocator: std.mem.Allocator) !*mango.ImageView {
    _ = device;
    const image_view = try allocator.create(mango.ImageView);
    errdefer allocator.destroy(image_view);

    image_view.* = .{
        .type = create_info.type,
        .format = create_info.format,
        .image = create_info.image,
    };

    return image_view;
}

pub fn destroyImageView(device: *Device, image_view: *mango.ImageView, allocator: std.mem.Allocator) void {
    _ = device;
    allocator.destroy(image_view);
}

pub fn createGraphicsPipeline(device: *Device, create_info: mango.Pipeline.CreateGraphics, allocator: std.mem.Allocator) !*mango.Pipeline {
    _ = device;
    _ = create_info;
    _ = allocator;
    @panic("TODO");
}

pub const BufferCopy = extern struct {
    src_offset: usize,
    dst_offset: usize,
    size: usize,
};

pub fn copyBuffer(device: *Device, src_buffer: *mango.Buffer, dst_buffer: *mango.Buffer, regions: []const BufferCopy) void {
    _ = device;
    _ = src_buffer;
    _ = dst_buffer;
    _ = regions;
}

pub fn copyBufferToImage() void {
}

pub fn copyImageToBuffer() void {
}

pub fn blitImage() void {
}

pub fn fillBuffer(device: *Device, dst_buffer: *mango.Buffer, dst_offset: usize, data: u32) void {
    _ = device;
    _ = dst_buffer;
    _ = dst_offset;
    _ = data;
}

pub fn clearColorImage(device: *Device, image: *mango.Image, color: [4]u8) void {
    _ = device;
    _ = image;
    _ = color;
}

pub fn clearDepthStencilImage(device: *Device, image: *mango.Image, depth: f32, stencil: u8) void {
    _ = device;
    _ = image;
    _ = depth;
    _ = stencil;
}

pub const SubmitInfo = extern struct {
    command_buffers_len: usize,
    command_buffers: [*]const mango.CommandBuffer,
};

pub fn submit(device: *Device, submit_info: *const SubmitInfo) void {
    _ = device;
    _ = submit_info;
}

pub const PresentInfo = extern struct {
    swapchains_len: usize,
    swapchains: [*]const mango.Swapchain,
};

pub fn present(device: *Device, present_info: *const PresentInfo) void {
    _ = device;
    _ = present_info;
}

pub fn waitIdle(device: *Device) void {
    _ = device;
}

const Device = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
