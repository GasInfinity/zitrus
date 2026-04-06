//! Represents the PICA200 GPU as a whole.
//!
//! As the GPU is not a standard one, there are lots of simplifications made:
//!     - Supports 3 separate queue families:
//!         * Memory Fills: fillBuffer, clearColorImage, clearDepthStencilImage (they are queue operations instead of command buffer ones!)
//!         * Transfer Engine / Display Transfer: present, copyBufferToImage, copyImageToBuffer, copyImageToImage, blitImage
//!         * 3D Command List: submit

pub const Handle = enum(u32) {
    null = 0,
    _,

    pub fn destroy(device: Handle) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        b_device.destroy();
    }

    pub fn reacquire(device: Handle) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return try b_device.reacquire();
    }

    pub fn release(device: Handle) !GraphicsServerGpu.ScreenCapture {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return try b_device.release();
    }

    pub fn getQueue(device: Handle, family: mango.QueueFamily) mango.Queue {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getQueue(family);
    }

    pub fn allocateMemory(device: Handle, allocate_info: mango.MemoryAllocateInfo, maybe_gpa: ?std.mem.Allocator) !mango.DeviceMemory {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.allocateMemory(allocate_info, maybe_gpa);
    }

    pub fn freeMemory(device: Handle, memory: mango.DeviceMemory, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.freeMemory(memory, maybe_gpa);
    }

    pub fn mapMemory(device: Handle, memory: mango.DeviceMemory, offset: mango.DeviceSize, size: mango.DeviceSize) ![]u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.mapMemory(memory, offset, size);
    }

    pub fn unmapMemory(device: Handle, memory: mango.DeviceMemory) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.unmapMemory(memory);
    }

    pub fn flushMappedMemoryRanges(device: Handle, ranges: []const mango.MappedMemoryRange) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.flushMappedMemoryRanges(ranges);
    }

    pub fn invalidateMappedMemoryRanges(device: Handle, ranges: []const mango.MappedMemoryRange) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.invalidateMappedMemoryRanges(ranges);
    }

    pub fn createSemaphore(device: Handle, create_info: mango.SemaphoreCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.Semaphore {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSemaphore(create_info, maybe_gpa);
    }

    pub fn destroySemaphore(device: Handle, semaphore: mango.Semaphore, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySemaphore(semaphore, maybe_gpa);
    }

    pub fn createCommandPool(device: Handle, create_info: mango.CommandPoolCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.CommandPool {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createCommandPool(create_info, maybe_gpa);
    }

    pub fn destroyCommandPool(device: Handle, command_pool: mango.CommandPool, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyCommandPool(command_pool, maybe_gpa);
    }

    pub fn resetCommandPool(device: Handle, command_pool: mango.CommandPool) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.resetCommandPool(command_pool);
    }

    pub fn trimCommandPool(device: Handle, command_pool: mango.CommandPool) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.trimCommandPool(command_pool);
    }

    pub fn allocateCommandBuffers(device: Handle, allocate_info: mango.CommandBufferAllocateInfo, buffers: []mango.CommandBuffer) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.allocateCommandBuffers(allocate_info, buffers);
    }

    pub fn freeCommandBuffers(device: Handle, command_pool: mango.CommandPool, buffers: []const mango.CommandBuffer) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.freeCommandBuffers(command_pool, buffers);
    }

    pub fn createBuffer(device: Handle, create_info: mango.BufferCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.Buffer {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createBuffer(create_info, maybe_gpa);
    }

    pub fn destroyBuffer(device: Handle, buffer: mango.Buffer, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyBuffer(buffer, maybe_gpa);
    }

    pub fn bindBufferMemory(device: Handle, buffer: mango.Buffer, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.bindBufferMemory(buffer, memory, memory_offset);
    }

    pub fn createImage(device: Handle, create_info: mango.ImageCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.Image {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImage(create_info, maybe_gpa);
    }

    pub fn destroyImage(device: Handle, image: mango.Image, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImage(image, maybe_gpa);
    }

    pub fn bindImageMemory(device: Handle, image: mango.Image, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.bindImageMemory(image, memory, memory_offset);
    }

    pub fn createImageView(device: Handle, create_info: mango.ImageViewCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.ImageView {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImageView(create_info, maybe_gpa);
    }

    pub fn destroyImageView(device: Handle, image_view: mango.ImageView, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImageView(image_view, maybe_gpa);
    }

    pub fn createSampler(device: Handle, create_info: mango.SamplerCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.Sampler {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSampler(create_info, maybe_gpa);
    }

    pub fn destroySampler(device: Handle, sampler: mango.Sampler, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySampler(sampler, maybe_gpa);
    }

    pub fn createShader(device: Handle, create_info: mango.ShaderCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Shader {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createShader(create_info, maybe_gpa);
    }

    pub fn destroyShader(device: Handle, shader: mango.Shader, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        b_device.destroyShader(shader, maybe_gpa);
    }

    pub fn createVertexInputLayout(device: Handle, create_info: mango.VertexInputLayoutCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.VertexInputLayout {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createVertexInputLayout(create_info, maybe_gpa);
    }

    pub fn destroyVertexInputLayout(device: Handle, layout: mango.VertexInputLayout, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyVertexInputLayout(layout, maybe_gpa);
    }

    pub fn createLightLookupTable(device: Handle, create_info: mango.LightLookupTableCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.LightLookupTable {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createLightLookupTable(create_info, maybe_gpa);
    }

    pub fn destroyLightLookupTable(device: Handle, lut: mango.LightLookupTable, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyLightLookupTable(lut, maybe_gpa);
    }

    pub fn createSwapchain(device: Handle, create_info: mango.SwapchainCreateInfo, maybe_gpa: ?std.mem.Allocator) !mango.Swapchain {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSwapchain(create_info, maybe_gpa);
    }

    pub fn destroySwapchain(device: Handle, swapchain: mango.Swapchain, maybe_gpa: ?std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySwapchain(swapchain, maybe_gpa);
    }

    pub fn getSwapchainImages(device: Handle, swapchain: mango.Swapchain, images: []mango.Image) !u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getSwapchainImages(swapchain, images);
    }

    pub fn acquireNextImage(device: Handle, swapchain: mango.Swapchain, timeout: u64) !u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.acquireNextImage(swapchain, timeout);
    }

    pub fn signalSemaphore(device: Handle, signal_info: mango.SemaphoreSignalInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.signalSemaphore(signal_info);
    }

    pub fn waitSemaphores(device: Handle, wait_info: mango.SemaphoreWaitInfo, timeout: u64) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.waitSemaphores(wait_info, timeout);
    }

    pub fn waitIdle(device: Handle) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.waitIdle();
    }
};

// TODO: restricted function types when they come!
pub const VTable = struct {
    destroy: *const fn (dev: *Device) void,

    release: *const fn (dev: *Device) ReleaseDeviceError!GraphicsServerGpu.ScreenCapture,
    reacquire: *const fn (dev: *Device) ReacquireDeviceError!void,

    waitIdleQueue: *const fn (dev: *Device, queue: Queue.Type) void,
    wakeIdleQueue: *const fn (dev: *Device, queue: Queue.Type) void,

    getShaderCode: *const fn (dev: *Device, key: backend.Shader.Code.Key) mango.ObjectCreationError!*backend.Shader.Code,
    destroyShaderCode: *const fn (dev: *Device, code: *backend.Shader.Code) void,

    allocateMemory: *const fn (dev: *Device, allocate_info: mango.MemoryAllocateInfo, gpa: std.mem.Allocator) mango.ObjectCreationError!mango.DeviceMemory,
    freeMemory: *const fn (dev: *Device, memory: mango.DeviceMemory, gpa: std.mem.Allocator) void,
    mapMemory: *const fn (dev: *Device, memory: mango.DeviceMemory, offset: mango.DeviceSize, size: mango.DeviceSize) MapMemoryError![]u8,
    unmapMemory: *const fn (device: *Device, memory: mango.DeviceMemory) void,
    flushMappedMemoryRanges: *const fn (dev: *Device, ranges: []const mango.MappedMemoryRange) FlushMemoryError!void,
    invalidateMappedMemoryRanges: *const fn (dev: *Device, ranges: []const mango.MappedMemoryRange) InvalidateMemoryError!void,

    createSwapchain: *const fn (dev: *Device, create_info: mango.SwapchainCreateInfo, gpa: std.mem.Allocator) ObjectCreationError!mango.Swapchain,
    destroySwapchain: *const fn (dev: *Device, swapchain: mango.Swapchain, gpa: std.mem.Allocator) void,
    getSwapchainImages: *const fn (dev: *Device, swapchain: mango.Swapchain, images: []mango.Image) GetSwapchainImagesError!u8,
    acquireNextImage: *const fn (dev: *Device, swapchain: mango.Swapchain, timeout: u64) AcquireNextImageError!u8,

    waitSemaphores: *const fn (dev: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: u64) WaitSemaphoreError!void,
    signalSemaphore: *const fn (dev: *Device, signal_info: mango.SemaphoreSignalInfo) SignalSemaphoreError!void,
};

const ObjectCreationError = mango.ObjectCreationError;
const MapMemoryError = mango.MapMemoryError;
const FlushMemoryError = mango.FlushMemoryError;
const InvalidateMemoryError = mango.InvalidateMemoryError;
const BindMemoryError = mango.BindMemoryError;
const AcquireNextImageError = mango.AcquireNextImageError;
const SignalSemaphoreError = mango.SignalSemaphoreError;
const WaitSemaphoreError = mango.WaitSemaphoreError;
const ReleaseDeviceError = mango.ReleaseDeviceError;
const ReacquireDeviceError = mango.ReacquireDeviceError;
const GetSwapchainImagesError = mango.GetSwapchainImagesError;

vtable: VTable,

gpa: std.mem.Allocator,
linear_gpa: std.mem.Allocator,

fill_queue: backend.Queue.Fill,
transfer_queue: backend.Queue.Transfer,
submit_queue: backend.Queue.Submit,
presentation_queue: backend.Queue.Presentation = undefined,

/// Whether we're waiting for operations to complete or not.
/// Waiting for a semaphore is NOT considered idle as we'll eventually wake.
queue_statuses: std.EnumArray(Queue.Type, std.atomic.Value(Queue.Status)),

pub fn destroy(device: *Device) void {
    device.vtable.destroy(device);
}

pub fn reacquire(device: *Device) !void {
    return try device.vtable.reacquire(device);
}

pub fn release(device: *Device) !GraphicsServerGpu.ScreenCapture {
    return try device.vtable.release(device);
}

pub fn getQueue(device: *Device, family: mango.QueueFamily) mango.Queue {
    return switch (family) {
        .transfer => device.transfer_queue.toHandle(),
        .fill => device.fill_queue.toHandle(),
        .submit => device.submit_queue.toHandle(),
        .present => device.presentation_queue.toHandle(),
    };
}

pub fn allocateMemory(device: *Device, allocate_info: mango.MemoryAllocateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.DeviceMemory {
    const gpa = maybe_gpa orelse device.gpa;
    return try device.vtable.allocateMemory(device, allocate_info, gpa);
}

pub fn freeMemory(device: *Device, memory: mango.DeviceMemory, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    return device.vtable.freeMemory(device, memory, gpa);
}

pub fn mapMemory(device: *Device, memory: mango.DeviceMemory, offset: mango.DeviceSize, size: mango.DeviceSize) MapMemoryError![]u8 {
    return try device.vtable.mapMemory(device, memory, offset, size);
}

pub fn unmapMemory(device: *Device, memory: mango.DeviceMemory) void {
    return device.vtable.unmapMemory(device, memory);
}

pub fn flushMappedMemoryRanges(device: *Device, ranges: []const mango.MappedMemoryRange) FlushMemoryError!void {
    return try device.vtable.flushMappedMemoryRanges(device, ranges);
}

pub fn invalidateMappedMemoryRanges(device: *Device, ranges: []const mango.MappedMemoryRange) InvalidateMemoryError!void {
    return try device.vtable.invalidateMappedMemoryRanges(device, ranges);
}

pub fn createSemaphore(device: *Device, create_info: mango.SemaphoreCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Semaphore {
    const gpa = maybe_gpa orelse device.gpa;
    const b_semaphore: *backend.Semaphore = try gpa.create(backend.Semaphore);
    b_semaphore.* = .init(create_info);
    return b_semaphore.toHandle();
}

pub fn destroySemaphore(device: *Device, semaphore: mango.Semaphore, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(semaphore);
    gpa.destroy(b_semaphore);
}

pub fn createCommandPool(device: *Device, create_info: mango.CommandPoolCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.CommandPool {
    const gpa = maybe_gpa orelse device.gpa;
    const b_command_pool: *backend.CommandPool = try gpa.create(backend.CommandPool);
    b_command_pool.* = try .init(create_info, device.linear_gpa, gpa);
    return b_command_pool.toHandle();
}

pub fn destroyCommandPool(device: *Device, command_pool: mango.CommandPool, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    b_command_pool.deinit(gpa);
    gpa.destroy(b_command_pool);
}

pub fn resetCommandPool(device: *Device, command_pool: mango.CommandPool) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    b_command_pool.reset();
}

pub fn trimCommandPool(device: *Device, command_pool: mango.CommandPool) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    b_command_pool.trim();
}

pub fn allocateCommandBuffers(device: *Device, allocate_info: mango.CommandBufferAllocateInfo, buffers: []mango.CommandBuffer) ObjectCreationError!void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(allocate_info.pool);
    return b_command_pool.allocate(buffers);
}

pub fn freeCommandBuffers(device: *Device, command_pool: mango.CommandPool, buffers: []const mango.CommandBuffer) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    return b_command_pool.free(buffers);
}

pub fn createBuffer(device: *Device, create_info: mango.BufferCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Buffer {
    const gpa = maybe_gpa orelse device.gpa;
    const buffer = try gpa.create(backend.Buffer);
    errdefer gpa.destroy(buffer);

    buffer.* = .init(create_info);
    return buffer.toHandle();
}

pub fn destroyBuffer(device: *Device, buffer: mango.Buffer, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_buffer: *backend.Buffer = .fromHandleMutable(buffer);
    gpa.destroy(b_buffer);
}

pub fn bindBufferMemory(device: *Device, buffer: mango.Buffer, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) BindMemoryError!void {
    _ = device;

    const b_buffer: *backend.Buffer = .fromHandleMutable(buffer);
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_buffer.memory_info.isUnbound());
    std.debug.assert(@intFromEnum(memory_offset) + b_buffer.size <= b_memory.size());

    b_buffer.memory_info = .init(b_memory, @intFromEnum(memory_offset));
}

pub fn createImage(device: *Device, create_info: mango.ImageCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Image {
    const gpa = maybe_gpa orelse device.gpa;
    const image = try gpa.create(backend.Image);
    errdefer gpa.destroy(image);

    image.* = try .init(create_info);
    return image.toHandle();
}

pub fn destroyImage(device: *Device, image: mango.Image, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_image: *backend.Image = .fromHandleMutable(image);
    gpa.destroy(b_image);
}

pub fn bindImageMemory(device: *Device, image: mango.Image, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) BindMemoryError!void {
    _ = device;

    const b_image: *backend.Image = .fromHandleMutable(image);
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_image.memory_info.isUnbound());
    std.debug.assert(@intFromEnum(memory_offset) + b_image.info.format.scale(b_image.info.size()) <= b_memory.size());

    b_image.memory_info = .init(b_memory, @intFromEnum(memory_offset));
}

pub fn createImageView(device: *Device, create_info: mango.ImageViewCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.ImageView {
    _ = device;
    _ = maybe_gpa;

    const b_image_view: backend.ImageView = .{
        .data = try .init(create_info),
    };

    return b_image_view.toHandle();
}

pub fn destroyImageView(device: *Device, image_view: mango.ImageView, maybe_gpa: ?std.mem.Allocator) void {
    _ = device;
    _ = image_view;
    _ = maybe_gpa;
}

pub fn createSampler(device: *Device, create_info: mango.SamplerCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Sampler {
    _ = device;
    _ = maybe_gpa;

    const b_image_sampler: backend.Sampler = .{
        .data = .init(create_info),
    };

    return b_image_sampler.toHandle();
}

pub fn destroySampler(device: *Device, sampler: mango.Sampler, maybe_gpa: ?std.mem.Allocator) void {
    _ = device;
    _ = sampler;
    _ = maybe_gpa;
}

pub fn createShader(device: *Device, create_info: mango.ShaderCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Shader {
    const gpa = maybe_gpa orelse device.gpa;
    return switch (create_info.code_type) {
        .psh => {
            const parsed = zitrus.fmt.zpsh.Parsed.initBuffer(create_info.code[0..create_info.code_len]) catch return error.ValidationFailed;
            const entrypoint_name = create_info.name[0..create_info.name_len];
            const entry = blk: {
                var it = parsed.iterator();
                while (it.next()) |entry| if (std.mem.eql(u8, entry.name, entrypoint_name)) {
                    break :blk entry;
                };

                try validation.assert(
                    false,
                    validation.shader.entry_not_found,
                    .{entrypoint_name},
                );
                unreachable;
            };

            const code = try device.vtable.getShaderCode(device, .initZpsh(parsed));
            errdefer device.vtable.destroyShaderCode(device, code);

            const shader = try gpa.create(backend.Shader);
            errdefer gpa.destroy(shader);

            shader.* = try .init(gpa, code, entry);
            errdefer shader.deinit(gpa);

            return shader.toHandle();
        },
        else => |c| {
            try validation.assert(
                false,
                validation.shader.unknown_code_type,
                .{c},
            );
            unreachable;
        },
    };
}

pub fn destroyShader(device: *Device, shader: mango.Shader, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_shader = backend.Shader.fromHandleMutable(shader).?;
    defer gpa.destroy(b_shader);
    defer b_shader.deinit(gpa);

    if (b_shader.code.ref.fetchSub(1, .monotonic) > 1) return;
    device.vtable.destroyShaderCode(device, b_shader.code);
}

pub fn createVertexInputLayout(device: *Device, create_info: mango.VertexInputLayoutCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.VertexInputLayout {
    const gpa = maybe_gpa orelse device.gpa;
    const layout: *backend.VertexInputLayout = try gpa.create(backend.VertexInputLayout);
    layout.* = try .compile(
        create_info.bindings[0..create_info.bindings_len],
        create_info.attributes[0..create_info.attributes_len],
        create_info.fixed_attributes[0..create_info.fixed_attributes_len],
    );
    return layout.toHandle();
}

pub fn destroyVertexInputLayout(device: *Device, layout: mango.VertexInputLayout, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_layout: *const backend.VertexInputLayout = .fromHandleMutable(layout);
    gpa.destroy(b_layout);
}

pub fn createLightLookupTable(device: *Device, create_info: mango.LightLookupTableCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.LightLookupTable {
    const gpa = maybe_gpa orelse device.gpa;
    const lut: *backend.LightLookupTable = try gpa.create(backend.LightLookupTable);
    lut.* = .init(create_info);

    return lut.toHandle();
}

pub fn destroyLightLookupTable(device: *Device, lut: mango.LightLookupTable, maybe_gpa: ?std.mem.Allocator) void {
    const gpa = maybe_gpa orelse device.gpa;
    const b_lut: *const backend.LightLookupTable = .fromHandleMutable(lut);
    gpa.destroy(b_lut);
}

pub fn createSwapchain(device: *Device, create_info: mango.SwapchainCreateInfo, maybe_gpa: ?std.mem.Allocator) ObjectCreationError!mango.Swapchain {
    return try device.vtable.createSwapchain(device, create_info, maybe_gpa orelse device.gpa);
}

pub fn destroySwapchain(device: *Device, swapchain: mango.Swapchain, maybe_gpa: ?std.mem.Allocator) void {
    return device.vtable.destroySwapchain(device, swapchain, maybe_gpa orelse device.gpa);
}

pub fn getSwapchainImages(device: *Device, swapchain: mango.Swapchain, images: []mango.Image) !u8 {
    return try device.vtable.getSwapchainImages(device, swapchain, images);
}

pub fn acquireNextImage(device: *Device, swapchain: mango.Swapchain, timeout: u64) AcquireNextImageError!u8 {
    return try device.vtable.acquireNextImage(device, swapchain, timeout);
}

pub fn signalSemaphore(device: *Device, signal_info: mango.SemaphoreSignalInfo) SignalSemaphoreError!void {
    return try device.vtable.signalSemaphore(device, signal_info);
}

pub fn waitSemaphores(device: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: u64) WaitSemaphoreError!void {
    var i: usize = 0;
    while (i < wait_info.semaphore_count) : (i += 1) {
        const sema = wait_info.semaphores[i];
        const value = wait_info.values[i];

        const b_sema: *backend.Semaphore = .fromHandleMutable(sema);
        if (b_sema.counterValue() >= value) continue;

        return try device.vtable.waitSemaphores(device, .{
            .semaphore_count = wait_info.semaphore_count - i,
            .semaphores = wait_info.semaphores[i..],
            .values = wait_info.values[i..],
        }, timeout);
    }
}

pub fn waitIdle(device: *Device) void {
    for (std.enums.values(Queue.Type)) |kind| {
        const queue_status = device.queue_statuses.getPtr(kind);

        while (true) switch (queue_status.load(.monotonic)) {
            .idle => break,
            .waiting, .working, .work_completed => device.vtable.waitIdleQueue(device, kind),
        };
    }
}

pub fn wakeIdleQueue(device: *Device, reason: Queue.Type) void {
    if (device.queue_statuses.getPtr(reason).load(.monotonic) == .idle) {
        device.vtable.wakeIdleQueue(device, reason);
    }
}

pub fn toHandle(device: *Device) Handle {
    return @enumFromInt(@intFromPtr(device));
}

pub fn fromHandleMutable(handle: Handle) *Device {
    return @as(*Device, @ptrFromInt(@intFromEnum(handle)));
}

const Device = @This();
const backend = @import("backend.zig");

const log = validation.log;
const validation = backend.validation;

const Queue = backend.Queue;

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
