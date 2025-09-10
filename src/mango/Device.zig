//! Represents the PICA200 GPU as a whole.
//!
//! As the GPU is not a standard one, there are lots of simplifications made:
//!     - Supports 3 separate queue families:
//!         * Memory Fills: fillBuffer, clearColorImage, clearDepthStencilImage (they are queue operations instead of command buffer ones!)
//!         * Transfer Engine / Display Transfer: present, copyBufferToImage, copyImageToBuffer, copyImageToImage, blitImage
//!         * 3D Command List: submit

// TODO: Regress portability for simplicity, abstract the implementation when diving into bare metal as some things are almost a must (Threading, for example).
// as this is the ONLY file that depends on horizon it shouldn't be that hard to port it for bare-metal compatibility.

pub const Handle = enum(u32) {
    null = 0,
    _,

    pub fn getQueue(device: Handle, family: mango.QueueFamily) mango.Queue {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getQueue(family);
    }
    
    pub fn allocateMemory(device: Handle, allocate_info: mango.MemoryAllocateInfo, allocator: std.mem.Allocator) !mango.DeviceMemory {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.allocateMemory(allocate_info, allocator);
    }

    pub fn freeMemory(device: Handle, memory: mango.DeviceMemory, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.freeMemory(memory, allocator);
    }

    pub fn mapMemory(device: Handle, memory: mango.DeviceMemory, offset: u32, size: mango.DeviceSize) ![]u8 {
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

    pub fn createSemaphore(device: Handle, create_info: mango.SemaphoreCreateInfo, allocator: std.mem.Allocator) !mango.Semaphore {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSemaphore(create_info, allocator);
    }

    pub fn destroySemaphore(device: Handle, semaphore: mango.Semaphore, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySemaphore(semaphore, allocator);
    }

    pub fn createCommandPool(device: Handle, create_info: mango.CommandPoolCreateInfo, allocator: std.mem.Allocator) !mango.CommandPool {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createCommandPool(create_info, allocator);
    }

    pub fn destroyCommandPool(device: Handle, command_pool: mango.CommandPool, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyCommandPool(command_pool, allocator);
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

    pub fn createBuffer(device: Handle, create_info: mango.BufferCreateInfo, allocator: std.mem.Allocator) !mango.Buffer {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createBuffer(create_info, allocator);
    }

    pub fn destroyBuffer(device: Handle, buffer: mango.Buffer, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyBuffer(buffer, allocator);
    }

    pub fn bindBufferMemory(device: Handle, buffer: mango.Buffer, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.bindBufferMemory(buffer, memory, memory_offset);
    }

    pub fn createImage(device: Handle, create_info: mango.ImageCreateInfo, allocator: std.mem.Allocator) !mango.Image {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImage(create_info, allocator);
    }

    pub fn destroyImage(device: Handle, image: mango.Image, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImage(image, allocator);
    }

    pub fn bindImageMemory(device: Handle, image: mango.Image, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.bindImageMemory(image, memory, memory_offset);
    }

    pub fn createImageView(device: Handle, create_info: mango.ImageViewCreateInfo, allocator: std.mem.Allocator) !mango.ImageView {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createImageView(create_info, allocator);
    }

    pub fn destroyImageView(device: Handle, image_view: mango.ImageView, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroyImageView(image_view, allocator);
    }

    pub fn createSampler(device: Handle, create_info: mango.SamplerCreateInfo, allocator: std.mem.Allocator) !mango.Sampler {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSampler(create_info, allocator);
    }

    pub fn destroySampler(device: Handle, sampler: mango.Sampler, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySampler(sampler, allocator);
    }

    pub fn createSwapchain(device: Handle, create_info: mango.SwapchainCreateInfo, allocator: std.mem.Allocator) !mango.Swapchain {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.createSwapchain(create_info, allocator);
    }

    pub fn destroySwapchain(device: Handle, swapchain: mango.Swapchain, allocator: std.mem.Allocator) void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.destroySwapchain(swapchain, allocator);
    }

    pub fn getSwapchainImages(device: Handle, swapchain: mango.Swapchain, images: []mango.Image) u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.getSwapchainImages(swapchain, images);
    }

    pub fn acquireNextImage(device: Handle, swapchain: mango.Swapchain, timeout: i64) !u8 {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.acquireNextImage(swapchain, timeout);
    }

    pub fn signalSemaphore(device: Handle, signal_info: mango.SemaphoreOperation) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.signalSemaphore(signal_info);
    }

    pub fn waitSemaphore(device: Handle, wait_info: mango.SemaphoreOperation, timeout: i64) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.waitSemaphore(wait_info, timeout);
    }

    pub fn waitIdle(device: Handle) !void {
        const b_device: *Device = @ptrFromInt(@intFromEnum(device));
        return b_device.waitIdle();
    }
};

pub const Native = struct {
    driver_thread: horizon.Thread,
    driver_stack: [16 * 1024]u8 align(8),
};

pub const QueueStatus = enum(i32) {
    working = -1,
    waiting = 0,
    idle = 1,
};

gsp: GspGpu,
gsp_thread_index: u8,
gsp_shm_memory_block: MemoryBlock,
gsp_shm: *GspGpu.Shared,
interrupt_event: Event,
arbiter: AddressArbiter,
driver_thread: horizon.Thread,
driver_stack: [8 * 1024]u8 align(8),

running: std.atomic.Value(bool),
vram_allocators: std.EnumArray(zitrus.memory.VRamBank, VRamBankAllocator),

// TODO: We can allow asking to create X queues, e.g the user may only want a transfer queue + submit queue only (we can basically do a clear by drawing a fullscreen quad!)
// This would introduce an extra indirection, but would reduce mem usage. Look into it sometime pls.
fill_queue: backend.Queue.Fill,
transfer_queue: backend.Queue.Transfer,
submit_queue: backend.Queue.Submit,
presentation_engine: PresentationEngine,

/// Whether we're waiting for operations to complete or not.
/// Waiting for a semaphore is NOT considered idle as we'll eventually wake.
queue_statuses: std.EnumArray(Queue.Type, std.atomic.Value(QueueStatus)),

pub fn initTodo(gsp: GspGpu, arbiter: horizon.AddressArbiter, allocator: std.mem.Allocator) !*Device {
    const device = try allocator.create(Device);
    errdefer allocator.destroy(device);

    try gsp.sendAcquireRight(0x0);

    const interrupt_event: Event = try .create(.oneshot);
    errdefer interrupt_event.close();

    // XXX: What does this flag mean?
    const queue_result = try gsp.sendRegisterInterruptRelayQueue(0x1, interrupt_event);

    if (queue_result.first_initialization) {
        try GspGpu.Graphics.initializeHardware(gsp);
    }

    // FIXME: As everywhere else we use this, this is NOT thread-safe and IS global, two big no-nos (it's easy to replace tho so defer the design!)
    const shared_memory = try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(@sizeOf(GspGpu.Shared), .fromByteUnits(4096));
    errdefer horizon.heap.non_thread_safe_shared_memory_address_allocator.free(shared_memory);

    try queue_result.response.gsp_memory.map(@alignCast(shared_memory.ptr), .rw, .dont_care);
    errdefer device.gsp_shm_memory_block.unmap(shared_memory.ptr);

    device.* = .{
        .running = .init(true),
        .vram_allocators = .init(.{
            .a = .init(@ptrFromInt(horizon.memory.vram_a_begin)),
            .b = .init(@ptrFromInt(horizon.memory.vram_b_begin)),
        }),
        .presentation_engine = .init(device),
        .gsp = gsp,
        .gsp_thread_index = @intCast(queue_result.response.thread_index),
        .gsp_shm_memory_block = queue_result.response.gsp_memory,
        .gsp_shm = @ptrCast(shared_memory),
        .interrupt_event = interrupt_event,
        .arbiter = arbiter,
        .driver_thread = undefined, // NOTE: The driver thread creation is deferred as we want to fully initialize things first!
        .driver_stack = undefined,
        .queue_statuses = .initDefault(.init(.idle), .{}),
        .fill_queue = .init(device),
        .transfer_queue = .init(device),
        .submit_queue = .init(device),
    };

    device.driver_thread = try .create(driverMain, device, (&device.driver_stack).ptr + (device.driver_stack.len - 1), 0x1A, -2);
    return device;
}

pub fn deinit(device: *Device, allocator: std.mem.Allocator) void {
    device.running.store(false, .monotonic);
    device.driver_thread.wait(-1) catch unreachable;
    device.driver_thread.close();
    device.gsp_shm_memory_block.unmap(@ptrCast(@alignCast(device.gsp_shm)));

    // FIXME: Same as the comment in `init`. See above
    horizon.heap.non_thread_safe_shared_memory_address_allocator.free(std.mem.asBytes(device.gsp_shm));
    device.gsp_shm_memory_block.close();
    device.gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    device.gsp.sendReleaseRight() catch {};
    device.interrupt_event.close();
    allocator.destroy(device);
}

pub fn getQueue(device: *Device, family: mango.QueueFamily) mango.Queue {
    return switch (family) {
        .transfer => device.transfer_queue.toHandle(),
        .fill => device.fill_queue.toHandle(),
        .submit => device.submit_queue.toHandle(),
        .present => device.presentation_engine.queue.toHandle(),
    };
}

pub fn allocateMemory(device: *Device, allocate_info: mango.MemoryAllocateInfo, allocator: std.mem.Allocator) !mango.DeviceMemory {
    _ = allocator;

    const aligned_allocation_size = std.mem.alignForward(usize, @intFromEnum(allocate_info.allocation_size), horizon.heap.page_size);

    const allocated_memory: backend.DeviceMemory = switch (allocate_info.memory_type) {
        .fcram_cached => fcram: {
            const allocated_virtual_address = switch (horizon.controlMemory(.{
                .fundamental_operation = .commit,
                .area = .all,
                .linear = true,
            }, null, null, aligned_allocation_size, .rw)) {
                .success => |s| s.value,
                .failure => return error.OutOfMemory,
            };

            break :fcram .{ .data = .init(allocated_virtual_address, horizon.memory.toPhysical(@intFromPtr(allocated_virtual_address)), aligned_allocation_size, .fcram) };
        },
        // XXX: Hardcore 1, 2 as VRAM (A) and VRAM (B) with DEVICE_LOCAL only, see above.
        .vram_a, .vram_b => |type_bank| vram: {
            const bank: zitrus.memory.VRamBank = switch (type_bank) {
                .vram_a => .a,
                .vram_b => .b,
                else => unreachable,
            };
            const vram_bank_allocator = device.vram_allocators.getPtr(bank);
            const allocated_virtual_address = try vram_bank_allocator.alloc(aligned_allocation_size, VRamBankAllocator.min_alignment);

            break :vram .{ .data = .init(allocated_virtual_address.ptr, horizon.memory.toPhysical(@intFromPtr(allocated_virtual_address.ptr)), aligned_allocation_size, @enumFromInt(@as(u2, @intFromEnum(bank)) + 1)) };
        },
    };

    return allocated_memory.toHandle();
}

pub fn freeMemory(device: *Device, memory: mango.DeviceMemory, allocator: std.mem.Allocator) void {
    _ = allocator;
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_memory.data.valid);

    switch (b_memory.data.heap) {
        .fcram => _ = horizon.controlMemory(.{
            .fundamental_operation = .free,
            .area = .all,
            .linear = true,
        }, b_memory.virtualAddress(), null, b_memory.size(), .rw),
        .vram_a, .vram_b => {
            const bank: zitrus.memory.VRamBank = switch (b_memory.data.heap) {
                .fcram => unreachable,
                .vram_a => .a,
                .vram_b => .b,
            };

            const vram_bank_allocator = device.vram_allocators.getPtr(bank);
            vram_bank_allocator.free(b_memory.virtualAddress()[0..b_memory.size()]);
        },
    }
}

pub fn mapMemory(device: *Device, memory: mango.DeviceMemory, offset: u32, size: mango.DeviceSize) ![]u8 {
    _ = device;

    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(std.mem.isAligned(offset, horizon.heap.page_size) and offset <= b_memory.size());

    if (size != .whole) {
        std.debug.assert(@intFromEnum(size) <= (b_memory.size() - offset));

        return (b_memory.virtualAddress() + offset)[0..@intFromEnum(size)];
    }

    return (b_memory.virtualAddress() + offset)[0 .. b_memory.size() - offset];
}

pub fn unmapMemory(device: *Device, memory: mango.DeviceMemory) void {
    _ = device;
    _ = memory;
    // NOTE: Currently does nothing, could do something in the future
}

pub fn flushMappedMemoryRanges(device: *Device, ranges: []const mango.MappedMemoryRange) !void {
    _ = device;

    for (ranges) |range| {
        const b_memory: backend.DeviceMemory = .fromHandle(range.memory);

        const offset = @intFromEnum(range.offset);
        const flushed_memory = switch (range.size) {
            .whole => b_memory.virtualAddress()[offset..][0..(b_memory.size() - offset)],
            _ => |sz| sz: {
                const size = @intFromEnum(sz);

                std.debug.assert(size <= (b_memory.size() - offset));

                break :sz b_memory.virtualAddress()[offset..][0..size];
            },
        };

        // TODO: error handling
        _ = horizon.flushProcessDataCache(.current, flushed_memory);
    }
}

pub fn createSemaphore(device: *Device, create_info: mango.SemaphoreCreateInfo, allocator: std.mem.Allocator) !mango.Semaphore {
    _ = device;
    const b_semaphore: *backend.Semaphore = try allocator.create(backend.Semaphore);
    b_semaphore.* = .init(create_info);
    return b_semaphore.toHandle();
}

pub fn destroySemaphore(device: *Device, semaphore: mango.Semaphore, allocator: std.mem.Allocator) void {
    _ = device;
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(semaphore);
    allocator.destroy(b_semaphore);
}

pub fn createCommandPool(device: *Device, create_info: mango.CommandPoolCreateInfo, allocator: std.mem.Allocator) !mango.CommandPool {
    _ = device;
    const b_command_pool: *backend.CommandPool = try allocator.create(backend.CommandPool);
    b_command_pool.* = .init(create_info, allocator);
    return b_command_pool.toHandle();
}

pub fn destroyCommandPool(device: *Device, command_pool: mango.CommandPool, allocator: std.mem.Allocator) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    b_command_pool.deinit(allocator);
    allocator.destroy(b_command_pool);
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

pub fn allocateCommandBuffers(device: *Device, allocate_info: mango.CommandBufferAllocateInfo, buffers: []mango.CommandBuffer) !void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(allocate_info.pool);
    return b_command_pool.allocate(buffers);
}

pub fn freeCommandBuffers(device: *Device, command_pool: mango.CommandPool, buffers: []const mango.CommandBuffer) void {
    _ = device;
    const b_command_pool: *backend.CommandPool = .fromHandleMutable(command_pool);
    return b_command_pool.free(buffers);
}

pub fn createBuffer(device: *Device, create_info: mango.BufferCreateInfo, allocator: std.mem.Allocator) !mango.Buffer {
    _ = device;

    const buffer = try allocator.create(backend.Buffer);
    errdefer allocator.destroy(buffer);

    buffer.* = .init(create_info);
    return buffer.toHandle();
}

pub fn destroyBuffer(device: *Device, buffer: mango.Buffer, allocator: std.mem.Allocator) void {
    _ = device;
    const b_buffer: *backend.Buffer = .fromHandleMutable(buffer);
    allocator.destroy(b_buffer);
}

pub fn bindBufferMemory(device: *Device, buffer: mango.Buffer, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
    _ = device;

    const b_buffer: *backend.Buffer = .fromHandleMutable(buffer);
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_buffer.memory_info.isUnbound());
    std.debug.assert(@intFromEnum(memory_offset) + b_buffer.size <= b_memory.size());

    b_buffer.memory_info = .init(b_memory, @intFromEnum(memory_offset));
}

pub fn createImage(device: *Device, create_info: mango.ImageCreateInfo, allocator: std.mem.Allocator) !mango.Image {
    _ = device;

    const image = try allocator.create(backend.Image);
    errdefer allocator.destroy(image);

    image.* = .init(create_info);
    return image.toHandle();
}

pub fn destroyImage(device: *Device, image: mango.Image, allocator: std.mem.Allocator) void {
    _ = device;
    const b_image: *backend.Image = .fromHandleMutable(image);
    allocator.destroy(b_image);
}

pub fn bindImageMemory(device: *Device, image: mango.Image, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) !void {
    _ = device;

    const b_image: *backend.Image = .fromHandleMutable(image);
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_image.memory_info.isUnbound());
    // TODO: std.debug.assert(memory_offset + image.size() <= memory.size);

    b_image.memory_info = .init(b_memory, @intFromEnum(memory_offset));
}

pub fn createImageView(device: *Device, create_info: mango.ImageViewCreateInfo, allocator: std.mem.Allocator) !mango.ImageView {
    _ = device;
    _ = allocator;

    const b_image_view: backend.ImageView = .{
        .data = .init(create_info),
    };

    return b_image_view.toHandle();
}

pub fn destroyImageView(device: *Device, image_view: mango.ImageView, allocator: std.mem.Allocator) void {
    _ = device;
    _ = image_view;
    _ = allocator;
}

pub fn createSampler(device: *Device, create_info: mango.SamplerCreateInfo, allocator: std.mem.Allocator) !mango.Sampler {
    _ = device;
    _ = allocator;

    const b_image_sampler: backend.Sampler = .{
        .data = .init(create_info),
    };

    return b_image_sampler.toHandle();
}

pub fn destroySampler(device: *Device, sampler: mango.Sampler, allocator: std.mem.Allocator) void {
    _ = device;
    _ = sampler;
    _ = allocator;
}

pub fn createGraphicsPipeline(device: *Device, create_info: mango.GraphicsPipelineCreateInfo, allocator: std.mem.Allocator) !mango.Pipeline {
    _ = device;

    const graphics_pipeline: *backend.Pipeline.Graphics = try allocator.create(backend.Pipeline.Graphics);
    graphics_pipeline.* = try .init(create_info, allocator);

    return graphics_pipeline.toHandle();
}

pub fn destroyPipeline(device: *Device, pipeline: mango.Pipeline, allocator: std.mem.Allocator) void {
    _ = device;
    const b_gfx_pipeline: *backend.Pipeline.Graphics = .fromHandleMutable(pipeline);

    b_gfx_pipeline.deinit(allocator);
    allocator.destroy(b_gfx_pipeline);
}

pub fn createSwapchain(device: *Device, create_info: mango.SwapchainCreateInfo, allocator: std.mem.Allocator) !mango.Swapchain {
    return device.presentation_engine.initSwapchain(create_info, allocator);
}

pub fn destroySwapchain(device: *Device, swapchain: mango.Swapchain, allocator: std.mem.Allocator) void {
    return device.presentation_engine.deinitSwapchain(swapchain, allocator);
}

pub fn getSwapchainImages(device: *Device, swapchain: mango.Swapchain, images: []mango.Image) u8 {
    return device.presentation_engine.getSwapchainImages(swapchain, images);
}

pub fn acquireNextImage(device: *Device, swapchain: mango.Swapchain, timeout: i64) !u8 {
    return device.presentation_engine.acquireNextImage(swapchain, timeout);
}

pub fn signalSemaphore(device: *Device, signal_info: mango.SemaphoreOperation) !void {
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(signal_info.semaphore);

    zitrus.atomicStore64(u64, &b_semaphore.raw_value, signal_info.value);
    device.arbiter.arbitrate(&b_semaphore.wake, .{ .signal = -1 }) catch unreachable;
}

pub fn waitSemaphore(device: *Device, wait_info: mango.SemaphoreOperation, timeout: i64) !void {
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(wait_info.semaphore);

    while (true) {
        if (b_semaphore.counterValue() >= wait_info.value) {
            return;
        }

        try device.arbiter.arbitrate(&b_semaphore.wake, .{ .wait_if_less_than_timeout = .{
            .value = 0,
            .timeout = timeout,
        } });
    }
}

pub fn waitIdle(device: *Device) !void {
    inline for (comptime std.enums.values(Queue.Type)) |kind| {
        const queue_status = device.queue_statuses.getPtr(kind);

        switch (queue_status.load(.monotonic)) {
            .idle => {},
            .waiting, .working => _ = device.arbiter.arbitrate(@ptrCast(&queue_status.raw), .{ .wait_if_less_than = @intFromEnum(QueueStatus.idle) }) catch unreachable,
        }
    }
}

pub fn driverWake(device: *Device, reason: Queue.Type) void {
    if (device.queue_statuses.getPtr(reason).load(.monotonic) == .idle) {
        device.interrupt_event.signal();
    }
}

// XXX: Should this should be in the syscore? we must handle vblanks and the app may be badly programmed (no yields)...
// FIXME: Currently if some error happens in the driver, the entire app crashes! Should we report an error condition?
fn driverMain(ctx: *anyopaque) callconv(.c) void {
    const device: *Device = @ptrCast(@alignCast(ctx));
    const presentation_engine = &device.presentation_engine;
    const gsp = device.gsp;
    const gsp_int = &device.gsp_shm.interrupt_queue[device.gsp_thread_index];
    const gsp_gx = &device.gsp_shm.command_queue[device.gsp_thread_index];
    const gsp_framebuffers = &device.gsp_shm.framebuffers[device.gsp_thread_index];

    while (device.running.load(.monotonic)) {
        device.interrupt_event.wait(-1) catch unreachable;

        const interrupts = gsp_int.popBackAll();

        // NOTE: The application may have wanted to wake us up!
        if (!interrupts.eql(.initEmpty())) {
            var interrupts_it = interrupts.iterator();

            while (interrupts_it.next()) |int| {
                switch (int) {
                    .dma => {}, // XXX: Should we use the CPU DMA engines?
                    .psc0, .psc1 => _ = device.fill_queue.complete() catch unreachable,
                    .ppf => _ = device.transfer_queue.complete() catch unreachable,
                    .p3d => {
                        const last_submission = device.submit_queue.complete() catch unreachable;

                        last_submission.cmd_buffer.notifyCompleted();
                    },
                    .vblank_top => _ = presentation_engine.refresh(gsp_framebuffers, .top),
                    .vblank_bottom => _ = presentation_engine.refresh(gsp_framebuffers, .bottom),
                }
            }
        }

        var enqueued_commands: usize = 0;
        inline for (comptime std.enums.values(Queue.Type)) |kind| {
            const queue = switch (kind) {
                .fill => &device.fill_queue,
                .transfer => &device.transfer_queue,
                .submit => &device.submit_queue,
                .present => &presentation_engine.queue,
            };

            const queue_status = device.queue_statuses.getPtr(kind);
            switch (queue.workPopBack()) {
                .empty => {
                    const empty_status: QueueStatus = switch (kind) {
                        .fill, .transfer, .submit => .idle,

                        // NOTE: The present queue is considered idle when all outstanding present operations are handled, a.k.a: unless we presented all frames we're still working!
                        .present => present_status: inline for (comptime std.enums.values(pica.Screen)) |screen| {
                            if (presentation_engine.chain_presents.getPtr(screen).load(.monotonic) > 0) {
                                break :present_status .working;
                            }
                        } else .idle,
                    };

                    _ = queue_status.store(empty_status, .monotonic);

                    // Is anyone waiting for us? Wake them!
                    if (empty_status == .idle) {
                        device.arbiter.arbitrate(@ptrCast(&queue_status.raw), .{ .signal = -1 }) catch unreachable;
                    }
                },
                .wait => _ = queue_status.store(.waiting, .monotonic),
                .work => |itm| {
                    _ = queue_status.store(.working, .monotonic);

                    switch (kind) {
                        .fill => {
                            gsp_gx.pushFrontAssumeCapacity(.initMemoryFill(.{ .init(itm.data, itm.value), null }, .none));
                        },
                        .transfer => {
                            switch (itm.flags.kind) {
                                .copy => gsp_gx.pushFrontAssumeCapacity(.initTextureCopy(itm.src, itm.dst, itm.flags.extra.copy, itm.input_gap_size, itm.output_gap_size, .none)),
                                .linear_tiled, .tiled_linear, .tiled_tiled => gsp_gx.pushFrontAssumeCapacity(.initDisplayTransfer(itm.src, itm.dst, itm.flags.extra.transfer.src_fmt, itm.input_gap_size, itm.flags.extra.transfer.dst_fmt, itm.output_gap_size, .{
                                    .mode = switch (itm.flags.kind) {
                                        .copy => unreachable,
                                        .linear_tiled => .linear_tiled,
                                        .tiled_linear => .tiled_linear,
                                        .tiled_tiled => .tiled_tiled,
                                    },
                                }, .none)),
                            }
                        },
                        .submit => {
                            const b_cmd = itm.cmd_buffer;

                            gsp_gx.pushFrontAssumeCapacity(.initProcessCommandList(b_cmd.queue.buffer[0..b_cmd.queue.current_index], .none, .flush, .none));
                        },
                        .present => presentation_engine.queueWork(itm),
                    }

                    enqueued_commands += 1;
                },
            }
        }

        if (enqueued_commands > 0) {
            gsp.sendTriggerCmdReqQueue() catch unreachable;
        }
    }

    horizon.exitThread();
}

comptime {
    std.debug.assert(VRamBankAllocator.min_alignment_byte_units == 4096);
}

const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(4096), zitrus.memory.vram_bank_size);

const Device = @This();
const backend = @import("backend.zig");

const Queue = backend.Queue;
const PresentationEngine = backend.PresentationEngine;

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const AddressArbiter = horizon.AddressArbiter;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
const GspGpu = horizon.services.GspGpu;
const Thread = horizon.Thread;

const mango = zitrus.mango;
const pica = zitrus.pica;

const PhysicalAddress = zitrus.PhysicalAddress;
