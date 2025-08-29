/// All index / vertex buffers provided to the gpu are relative to this address
pub const global_attribute_buffer_base: zitrus.PhysicalAddress = .fromAddress(zitrus.memory.arm11.vram_begin);

pub const PresentationEngine = @import("PresentationEngine.zig");

pub const Device = @import("Device.zig");
pub const Semaphore = @import("Semaphore.zig");
pub const DeviceMemory = @import("DeviceMemory.zig");
pub const Buffer = @import("Buffer.zig");
pub const Image = @import("Image.zig");
pub const ImageView = @import("ImageView.zig");
pub const Pipeline = @import("Pipeline.zig");
pub const CommandPool = @import("CommandPool.zig");
pub const CommandBuffer = @import("CommandBuffer.zig");
pub const Sampler = @import("Sampler.zig");
pub const Surface = @import("Surface.zig");
pub const Swapchain = @import("Swapchain.zig");

pub const GraphicsState = @import("GraphicsState.zig");
pub const RenderingState = @import("RenderingState.zig");
pub const VertexInputLayout = @import("VertexInputLayout.zig");

const std = @import("std");
const zitrus = @import("zitrus");
