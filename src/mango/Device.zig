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

    pub fn hostAllocator(device: Handle) std.mem.Allocator {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.hostAllocator();
    }

    pub fn allocatePrivate(device: Handle, bank: mango.PrivateMemoryIndex, len: u32) mango.PrivateAllocationError![]const u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.allocatePrivate(bank, len);
    }

    pub fn freePrivate(device: Handle, buffer: []const u8) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.freePrivate(buffer);
    }

    pub fn hostToDevice(device: Handle, buffer: []const u8) mango.HostToDeviceError!mango.DeviceSlice {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.hostToDevice(buffer);
    }

    pub fn flushCachedMemoryRanges(device: Handle, ranges: []const []const u8) mango.FlushMemoryError!void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.flushCachedMemoryRanges(ranges);
    }

    pub fn invalidateCachedMemoryRanges(device: Handle, ranges: []const []const u8) mango.InvalidateMemoryError!void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.invalidateCachedMemoryRanges(ranges);
    }

    pub fn createSemaphore(device: Handle, create_info: mango.SemaphoreCreateInfo) !mango.Semaphore {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSemaphore(create_info);
    }

    pub fn destroySemaphore(device: Handle, semaphore: mango.Semaphore) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySemaphore(semaphore);
    }

    pub fn createQueryPool(device: Handle, create_info: mango.QueryPoolCreateInfo) mango.ObjectCreationError!mango.QueryPool {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createQueryPool(create_info);
    }

    pub fn destroyQueryPool(device: Handle, query_pool: mango.QueryPool) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyQueryPool(query_pool);
    }

    pub fn resetQueryPool(device: Handle, query_pool: mango.QueryPool, first: u32, count: u32) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.resetQueryPool(query_pool, first, count);
    }

    pub fn getQueryPoolResults(device: Handle, query_pool: mango.QueryPool, first: u32, count: u32, data: []u8, stride: u32, flags: mango.QueryResultFlags) mango.GetQueryResultsError!void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getQueryPoolResults(query_pool, first, count, data, stride, flags);
    }

    pub fn createCommandPool(device: Handle, create_info: mango.CommandPoolCreateInfo) !mango.CommandPool {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createCommandPool(create_info);
    }

    pub fn destroyCommandPool(device: Handle, command_pool: mango.CommandPool) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyCommandPool(command_pool);
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

    pub fn createImage(device: Handle, create_info: mango.ImageCreateInfo) !mango.Image {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImage(create_info);
    }

    pub fn destroyImage(device: Handle, image: mango.Image) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImage(image);
    }

    pub fn bindImageMemory(device: Handle, image: mango.Image, buffer: mango.DeviceSlice) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.bindImageMemory(image, buffer);
    }

    pub fn createImageView(device: Handle, create_info: mango.ImageViewCreateInfo) !mango.ImageView {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImageView(create_info);
    }

    pub fn destroyImageView(device: Handle, image_view: mango.ImageView) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImageView(image_view);
    }

    pub fn createSampler(device: Handle, create_info: mango.SamplerCreateInfo) !mango.Sampler {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSampler(create_info);
    }

    pub fn destroySampler(device: Handle, sampler: mango.Sampler) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySampler(sampler);
    }

    pub fn createShader(device: Handle, create_info: mango.ShaderCreateInfo) mango.ObjectCreationError!mango.Shader {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createShader(create_info);
    }

    pub fn destroyShader(device: Handle, shader: mango.Shader) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        b_device.destroyShader(shader);
    }

    pub fn createVertexInputLayout(device: Handle, create_info: mango.VertexInputLayoutCreateInfo) mango.ObjectCreationError!mango.VertexInputLayout {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createVertexInputLayout(create_info);
    }

    pub fn destroyVertexInputLayout(device: Handle, layout: mango.VertexInputLayout) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyVertexInputLayout(layout);
    }

    pub fn createLightLookupTable(device: Handle, create_info: mango.LightLookupTableCreateInfo) !mango.LightLookupTable {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createLightLookupTable(create_info);
    }

    pub fn recreateLightLookupTable(device: *Device, lut: mango.LightLookupTable, create_info: mango.LightLookupTableCreateInfo) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.recreateLightLookupTable(lut, create_info);
    }

    pub fn destroyLightLookupTable(device: Handle, lut: mango.LightLookupTable) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyLightLookupTable(lut);
    }

    pub fn createFogLookupTable(device: Handle, create_info: mango.FogLookupTableCreateInfo) mango.ObjectCreationError!mango.FogLookupTable {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createFogLookupTable(create_info);
    }

    pub fn recreateFogLookupTable(device: Handle, lut: mango.FogLookupTable, create_info: mango.FogLookupTableCreateInfo) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.recreateFogLookupTable(lut, create_info);
    }

    pub fn destroyFogLookupTable(device: Handle, lut: mango.FogLookupTable) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyFogLookupTable(lut);
    }

    pub fn configureDisplay(device: Handle, display: mango.Display, configure_info: *const mango.DisplayConfigureInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.configureDisplay(display, configure_info);
    }

    pub fn resetDisplay(device: Handle, display: mango.Display) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.resetDisplay(display);
    }

    pub fn getDisplayImages(device: Handle, display: mango.Display, images: []mango.Image) !u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getDisplayImages(display, images);
    }

    pub fn acquireNextImage(device: Handle, display: mango.Display, timeout: u64) !u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.acquireNextImage(display, timeout);
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

    /// Copies the region specified onto the destination buffer.
    ///
    /// Valid Usage:
    /// - Slices must be aligned to 8 bytes.
    pub fn copyBuffer(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.CopyBufferInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.copyBuffer(wait, signal, info);
    }

    pub fn copyBufferToImage(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.CopyBufferToImageInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.copyBufferToImage(wait, signal, info);
    }

    /// Blit an image onto another performing format conversion and scaling when appropiate.
    ///
    /// The operation is done layer by layer on the specified mip levels. When scaling is done,
    /// a linear (also called box) filter is applied.
    ///
    /// Valid Usage:
    /// The tiling of the source and destination images **must** not be both LINEAR.
    ///
    /// The sizes of the source and destination image dimensions **can** *only* differ when:
    /// - The width of the destination is half the width of the source.
    /// - The width and height of the destination is half the width of the source.
    pub fn blitImage(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.BlitImageInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.blitImage(wait, signal, info);
    }

    pub fn fillBuffer(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.FillBufferInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.fillBuffer(wait, signal, info);
    }

    pub fn clearColorImage(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.ClearColorInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.clearColorImage(wait, signal, info);
    }

    pub fn clearDepthStencilImage(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.ClearDepthStencilInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.clearDepthStencilImage(wait, signal, info);
    }

    pub fn submit(device: Handle, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.SubmitInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.submit(wait, signal, info);
    }

    pub fn present(device: Handle, wait: ?*const mango.SemaphoreOperation, info: *const mango.PresentInfo) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.present(wait, info);
    }
};

// TODO: restricted function types when they come!
pub const VTable = struct {
    destroy: *const fn (dev: *Device) void,

    release: *const fn (dev: *Device) mango.ReleaseDeviceError!GraphicsServerGpu.ScreenCapture,
    reacquire: *const fn (dev: *Device) mango.ReacquireDeviceError!void,

    waitIdleQueue: *const fn (dev: *Device, queue: Queue.Type) void,
    wakeIdleQueue: *const fn (dev: *Device, queue: Queue.Type) void,

    getShaderCode: *const fn (dev: *Device, key: backend.Shader.Code.Key) mango.ObjectCreationError!*backend.Shader.Code,
    destroyShaderCode: *const fn (dev: *Device, code: *backend.Shader.Code) void,

    allocatePrivate: *const fn (dev: *Device, index: mango.PrivateMemoryIndex, len: u32) mango.PrivateAllocationError![]const u8,
    freePrivate: *const fn (dev: *Device, buffer: []const u8) void,
    hostToDevice: *const fn (dev: *Device, buffer: []const u8) mango.HostToDeviceError!mango.DeviceSlice,
    flushCachedMemoryRanges: *const fn (dev: *Device, ranges: []const []const u8) mango.FlushMemoryError!void,
    invalidateCachedMemoryRanges: *const fn (dev: *Device, ranges: []const []const u8) mango.InvalidateMemoryError!void,

    configureDisplay: *const fn (dev: *Device, display: mango.Display, configure_info: *const mango.DisplayConfigureInfo) mango.ConfigureDisplayError!void,
    resetDisplay: *const fn (dev: *Device, display: mango.Display) void,
    getDisplayImages: *const fn (dev: *Device, display: mango.Display, images: []mango.Image) mango.GetDisplayImagesError!u8,
    acquireNextImage: *const fn (dev: *Device, display: mango.Display, timeout: u64) mango.AcquireNextImageError!u8,

    waitSemaphores: *const fn (dev: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: u64) mango.WaitSemaphoreError!void,
    signalSemaphore: *const fn (dev: *Device, signal_info: mango.SemaphoreSignalInfo) mango.SignalSemaphoreError!void,

    virtualToPhysical: *const fn (dev: *Device, virtual: *const anyopaque) zitrus.hardware.PhysicalAddress,
};

vtable: VTable,

gpa: std.mem.Allocator,
linear_gpa: std.mem.Allocator,

queues: std.EnumArray(Queue.Type, backend.Queue),

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

pub fn hostAllocator(device: *Device) std.mem.Allocator {
    return device.linear_gpa;
}

pub fn allocatePrivate(device: *Device, index: mango.PrivateMemoryIndex, len: u32) mango.PrivateAllocationError![]const u8 {
    return try device.vtable.allocatePrivate(device, index, len);
}

pub fn freePrivate(device: *Device, buffer: []const u8) void {
    if (buffer.len == 0) return;
    return device.vtable.freePrivate(device, buffer);
}

pub fn hostToDevice(device: *Device, buffer: []const u8) mango.HostToDeviceError!mango.DeviceSlice {
    return device.vtable.hostToDevice(device, buffer);
}

pub fn flushCachedMemoryRanges(device: *Device, ranges: []const []const u8) mango.FlushMemoryError!void {
    return device.vtable.flushCachedMemoryRanges(device, ranges);
}

pub fn invalidateCachedMemoryRanges(device: *Device, ranges: []const []const u8) mango.InvalidateMemoryError!void {
    return device.vtable.invalidateCachedMemoryRanges(device, ranges);
}

pub fn createSemaphore(device: *Device, create_info: mango.SemaphoreCreateInfo) mango.ObjectCreationError!mango.Semaphore {
    const gpa = device.gpa;
    const b_semaphore: *backend.Semaphore = try gpa.create(backend.Semaphore);
    errdefer gpa.destroy(b_semaphore);
    b_semaphore.* = .init(create_info);
    return b_semaphore.toHandle();
}

pub fn destroySemaphore(device: *Device, semaphore: mango.Semaphore) void {
    const gpa = device.gpa;
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(semaphore);
    gpa.destroy(b_semaphore);
}

pub fn createQueryPool(device: *Device, create_info: mango.QueryPoolCreateInfo) mango.ObjectCreationError!mango.QueryPool {
    const gpa = device.gpa;
    const b_query_pool: *backend.QueryPool = try gpa.create(backend.QueryPool);
    errdefer gpa.destroy(b_query_pool);

    b_query_pool.* = try .init(gpa, create_info);
    return b_query_pool.toHandle();
}

pub fn destroyQueryPool(device: *Device, query_pool: mango.QueryPool) void {
    const gpa = device.gpa;
    const b_query_pool: *backend.QueryPool = .fromHandleMutable(query_pool);
    b_query_pool.deinit(gpa);
    gpa.destroy(b_query_pool);
}

pub fn resetQueryPool(device: *Device, query_pool: mango.QueryPool, first: u32, count: u32) void {
    _ = device;

    const b_query_pool: *backend.QueryPool = .fromHandleMutable(query_pool);
    b_query_pool.reset(first, count);
}

pub fn getQueryPoolResults(device: *Device, query_pool: mango.QueryPool, first: u32, count: u32, data: []u8, stride: u32, flags: mango.QueryResultFlags) mango.GetQueryResultsError!void {
    _ = device;

    const b_query_pool: *backend.QueryPool = .fromHandleMutable(query_pool);
    return b_query_pool.getResults(first, count, data, stride, flags);
}

pub fn createCommandPool(device: *Device, create_info: mango.CommandPoolCreateInfo) mango.ObjectCreationError!mango.CommandPool {
    const gpa = device.gpa;
    const b_command_pool: *backend.CommandPool = try gpa.create(backend.CommandPool);
    errdefer gpa.destroy(b_command_pool);
    b_command_pool.* = try .init(device, create_info, device.linear_gpa, gpa);
    return b_command_pool.toHandle();
}

pub fn destroyCommandPool(device: *Device, command_pool: mango.CommandPool) void {
    const gpa = device.gpa;
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

pub fn allocateCommandBuffers(device: *Device, allocate_info: mango.CommandBufferAllocateInfo, buffers: []mango.CommandBuffer) mango.ObjectCreationError!void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(allocate_info.pool);
    return b_command_pool.allocate(buffers);
}

pub fn freeCommandBuffers(device: *Device, command_pool: mango.CommandPool, buffers: []const mango.CommandBuffer) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    return b_command_pool.free(buffers);
}

pub fn createImage(device: *Device, create_info: mango.ImageCreateInfo) mango.ObjectCreationError!mango.Image {
    const gpa = device.gpa;
    const image = try gpa.create(backend.Image);
    errdefer gpa.destroy(image);

    image.* = try .init(create_info);
    return image.toHandle();
}

pub fn destroyImage(device: *Device, image: mango.Image) void {
    const gpa = device.gpa;
    const b_image: *backend.Image = .fromHandleMutable(image);
    gpa.destroy(b_image);
}

pub fn getImageMemoryRequirements(device: *Device, image: mango.Image) mango.MemoryRequirements {
    _ = device;
    _ = image;

    return .{
        .alignment = 0,
        .size = 0,
    };
}

pub fn bindImageMemory(device: *Device, image: mango.Image, buffer: mango.DeviceSlice) mango.BindMemoryError!void {
    _ = device;

    const b_image: *backend.Image = .fromHandleMutable(image);

    std.debug.assert(b_image.address == .zero);
    std.debug.assert(b_image.info.format.scale(b_image.info.size()) <= buffer.len);

    b_image.address = buffer.address;
}

pub fn createImageView(device: *Device, create_info: mango.ImageViewCreateInfo) mango.ObjectCreationError!mango.ImageView {
    _ = device;

    const b_image_view: backend.ImageView = .{ .data = try .init(create_info) };
    return b_image_view.toHandle();
}

pub fn destroyImageView(device: *Device, image_view: mango.ImageView) void {
    _ = device;
    _ = image_view;
}

pub fn createSampler(device: *Device, create_info: mango.SamplerCreateInfo) mango.ObjectCreationError!mango.Sampler {
    _ = device;

    const b_image_sampler: backend.Sampler = .{ .data = .init(create_info) };
    return b_image_sampler.toHandle();
}

pub fn destroySampler(device: *Device, sampler: mango.Sampler) void {
    _ = device;
    _ = sampler;
}

pub fn createShader(device: *Device, create_info: mango.ShaderCreateInfo) mango.ObjectCreationError!mango.Shader {
    const gpa = device.gpa;
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

pub fn destroyShader(device: *Device, shader: mango.Shader) void {
    const gpa = device.gpa;
    const b_shader = backend.Shader.fromHandleMutable(shader).?;
    defer gpa.destroy(b_shader);
    defer b_shader.deinit(gpa);

    if (b_shader.code.ref.fetchSub(1, .monotonic) > 1) return;
    device.vtable.destroyShaderCode(device, b_shader.code);
}

pub fn createVertexInputLayout(device: *Device, create_info: mango.VertexInputLayoutCreateInfo) mango.ObjectCreationError!mango.VertexInputLayout {
    const gpa = device.gpa;
    const layout: *backend.VertexInputLayout = try gpa.create(backend.VertexInputLayout);
    errdefer gpa.destroy(layout);

    layout.* = try .compile(
        create_info.bindings[0..create_info.bindings_len],
        create_info.attributes[0..create_info.attributes_len],
        create_info.fixed_attributes[0..create_info.fixed_attributes_len],
    );
    return layout.toHandle();
}

pub fn destroyVertexInputLayout(device: *Device, layout: mango.VertexInputLayout) void {
    const gpa = device.gpa;
    const b_layout: *const backend.VertexInputLayout = .fromHandleMutable(layout);
    gpa.destroy(b_layout);
}

pub fn createLightLookupTable(device: *Device, create_info: mango.LightLookupTableCreateInfo) mango.ObjectCreationError!mango.LightLookupTable {
    const gpa = device.gpa;
    const lut: *backend.LightLookupTable = try gpa.create(backend.LightLookupTable);
    errdefer gpa.destroy(lut);

    lut.* = .init(create_info);
    return lut.toHandle();
}

pub fn recreateLightLookupTable(device: *Device, lut: mango.LightLookupTable, create_info: mango.LightLookupTableCreateInfo) void {
    _ = device;
    const b_lut: *backend.LightLookupTable = .fromHandleMutable(lut);
    b_lut.* = .init(create_info);
}

pub fn destroyLightLookupTable(device: *Device, lut: mango.LightLookupTable) void {
    const gpa = device.gpa;
    const b_lut: *const backend.LightLookupTable = .fromHandleMutable(lut);
    gpa.destroy(b_lut);
}

pub fn createFogLookupTable(device: *Device, create_info: mango.FogLookupTableCreateInfo) mango.ObjectCreationError!mango.FogLookupTable {
    const gpa = device.gpa;
    const lut: *backend.FogLookupTable = try gpa.create(backend.FogLookupTable);
    errdefer gpa.destroy(lut);

    lut.* = .init(create_info);
    return lut.toHandle();
}

pub fn recreateFogLookupTable(device: *Device, lut: mango.FogLookupTable, create_info: mango.FogLookupTableCreateInfo) void {
    _ = device;
    const b_lut: *backend.FogLookupTable = .fromHandleMutable(lut);
    b_lut.* = .init(create_info);
}

pub fn destroyFogLookupTable(device: *Device, lut: mango.FogLookupTable) void {
    const gpa = device.gpa;
    const b_lut: *const backend.FogLookupTable = .fromHandleMutable(lut);
    gpa.destroy(b_lut);
}

pub fn configureDisplay(device: *Device, display: mango.Display, configure_info: *const mango.DisplayConfigureInfo) mango.ConfigureDisplayError!void {
    return try device.vtable.configureDisplay(device, display, configure_info);
}

pub fn resetDisplay(device: *Device, display: mango.Display) void {
    return device.vtable.resetDisplay(device, display);
}

pub fn getDisplayImages(device: *Device, display: mango.Display, images: []mango.Image) mango.GetDisplayImagesError!u8 {
    return try device.vtable.getDisplayImages(device, display, images);
}

pub fn acquireNextImage(device: *Device, display: mango.Display, timeout: u64) mango.AcquireNextImageError!u8 {
    return try device.vtable.acquireNextImage(device, display, timeout);
}

pub fn signalSemaphore(device: *Device, signal_info: mango.SemaphoreSignalInfo) mango.SignalSemaphoreError!void {
    return try device.vtable.signalSemaphore(device, signal_info);
}

pub fn waitSemaphores(device: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: u64) mango.WaitSemaphoreError!void {
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
            // TODO: Make this return an error
            .lost => break,
            .waiting, .working, .work_completed => device.vtable.waitIdleQueue(device, kind),
        };
    }
}

pub fn wakeIdleQueue(device: *Device, reason: Queue.Type) void {
    if (device.queue_statuses.getPtr(reason).load(.monotonic) == .idle) {
        device.vtable.wakeIdleQueue(device, reason);
    }
}

pub fn copyBuffer(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.CopyBufferInfo) !void {
    const queue = device.queues.getPtr(.transfer);
    var it: Queue.Transfer.Iterator = .initBuffer(info);
    try pushOperations(Queue.Transfer, queue, wait, signal, &it);
}

// TODO: Provide a software fallback for directly using host memory (akin to VK_EXT_host_image_copy)
pub fn copyBufferToImage(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.CopyBufferToImageInfo) !void {
    const queue = device.queues.getPtr(.transfer);
    var it: Queue.Transfer.Iterator = .initBufferToImage(info);
    try pushOperations(Queue.Transfer, queue, wait, signal, &it);
}

pub fn blitImage(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.BlitImageInfo) !void {
    const queue = device.queues.getPtr(.transfer);
    var it: Queue.Transfer.Iterator = .initBlit(info);
    try pushOperations(Queue.Transfer, queue, wait, signal, &it);
}

pub fn fillBuffer(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.FillBufferInfo) !void {
    const queue: *Queue = device.queues.getPtr(.fill);

    try queue.pushFrontBounded(Queue.Fill, .{
        .ptr = .fromPhysical(info.buffer.address),
        .extra = .{
            .len = @intCast(info.buffer.len),
            .size = switch (info.pattern_type) {
                .u16 => .@"16",
                .u24 => .@"24",
                .u32 => .@"32",
            },
        },
        .value = info.pattern,
    }, .init(wait), .init(signal));
}

pub fn clearColorImage(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.ClearColorInfo) !void {
    const queue = device.queues.getPtr(.fill);
    var it: Queue.Fill.Iterator = .initColor(info);
    try pushOperations(Queue.Fill, queue, wait, signal, &it);
}

pub fn clearDepthStencilImage(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.ClearDepthStencilInfo) !void {
    const queue = device.queues.getPtr(.fill);
    var it: Queue.Fill.Iterator = .initDepth(info);
    try pushOperations(Queue.Fill, queue, wait, signal, &it);
}

fn pushOperations(comptime Operation: type, queue: *Queue, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, it: *Operation.Iterator) !void {
    const wait_op: Queue.SemaphoreOperation = .init(wait);

    var i: usize = 0;
    var current = it.next();
    while (current) |op| : (i += 1) {
        const next = it.next();
        const signal_op: Queue.SemaphoreOperation = if (next != null) .none else .init(signal);

        try queue.pushFrontBounded(Operation, op, wait_op, signal_op);
        current = next;
    }
}

pub fn submit(device: *Device, wait: ?*const mango.SemaphoreOperation, signal: ?*const mango.SemaphoreOperation, info: *const mango.SubmitInfo) !void {
    const queue = device.queues.getPtr(.submit);
    const b_cmd: *backend.CommandBuffer = .fromHandleMutable(info.command_buffer);
    b_cmd.notifyPending();

    return try queue.pushFrontBounded(Queue.Submit, .{
        .cmd = b_cmd,
    }, .init(wait), .init(signal));
}

pub fn present(device: *Device, wait: ?*const mango.SemaphoreOperation, info: *const mango.PresentInfo) !void {
    const queue = device.queues.getPtr(.present);
    const screen: pica.Screen = @enumFromInt(@intFromEnum(info.display));

    return try queue.pushFrontBounded(Queue.Presentation, .{
        .misc = .{
            .screen = screen,
            .ignore_stereo = info.flags.ignore_stereoscopic,
        },
        .index = info.image_index,
    }, .init(wait), .none);
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

const horizon = zitrus.horizon;
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
