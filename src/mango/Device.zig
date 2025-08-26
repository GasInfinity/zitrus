//! Represents the PICA200 GPU as a whole.
//!
//! As the GPU is not a standard one, there are lots of simplifications made:
//!     - It only supports one queue with:
//!         * DMA: copyBuffer, copyBufferToImage (with memcpy flag), copyImageToBuffer (with memcpy flag).
//!         * Memory Fills: fillBuffer, clearColorImage, clearDepthStencilImage (they are queue operations instead of command buffer ones!)
//!         * Transfer Engine / Display Transfer: present, copyBufferToImage, copyImageToBuffer, copyImageToImage, blitImage
//!         * 3D Command List: submit

// TODO: Regress portability for simplicity, abstract the implementation when diving into bare metal as some things are almost a must (Threading, for example).
// as this is the ONLY file that depends on horizon it shouldn't be that hard to port it for bare-metal compatibility.

// TODO: Synchronization primitives.

pub const Handle = enum(u32) { _ };

// NOTE: The C API will have other entrypoint for creating a device.
pub const CreateInfo = struct {
    gsp: *GspGpu,
};

vram_allocators: std.EnumArray(zitrus.memory.VRamBank, VRamBankAllocator),
presentation_engine: PresentationEngine,
gsp: *GspGpu,

pub fn initTodo(gsp: *GspGpu) Device {
    return .{
        .vram_allocators = .init(.{
            .a = .init(@ptrFromInt(horizon.memory.vram_a_begin)),
            .b = .init(@ptrFromInt(horizon.memory.vram_b_begin)),
        }),
        .presentation_engine = .init(),
        .gsp = gsp,
    };
}

pub fn allocateMemory(device: *Device, allocate_info: *const mango.MemoryAllocateInfo, allocator: std.mem.Allocator) !mango.DeviceMemory {
    _ = allocator;

    const aligned_allocation_size = std.mem.alignForward(usize, @intFromEnum(allocate_info.allocation_size), horizon.heap.page_size);

    const allocated_memory: backend.DeviceMemory = switch (allocate_info.memory_type) {
        // XXX: Hardcode 0 as cached fcram until we have proper memory types.
        0 => fcram: {
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
        1, 2 => |memory_type_index| vram: {
            const bank: zitrus.memory.VRamBank = @enumFromInt(memory_type_index - 1);
            const vram_bank_allocator = device.vram_allocators.getPtr(bank);
            const allocated_virtual_address = try vram_bank_allocator.alloc(aligned_allocation_size, VRamBankAllocator.min_alignment);

            break :vram .{ .data = .init(allocated_virtual_address.ptr, horizon.memory.toPhysical(@intFromPtr(allocated_virtual_address.ptr)), aligned_allocation_size, @enumFromInt(memory_type_index)) };
        },
        else => @panic("TODO, invalid memory type"),
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

// TODO: DeviceSize and whole_size
pub fn mapMemory(device: *Device, memory: mango.DeviceMemory, offset: u32, size: u32) ![*]u8 {
    _ = device;

    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(std.mem.isAligned(offset, horizon.heap.page_size) and offset <= b_memory.size());

    // TODO: see above
    if (size != std.math.maxInt(u32)) {
        std.debug.assert(size <= (b_memory.size() - offset));
    }

    return (b_memory.virtualAddress() + offset);
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
            .whole_size => b_memory.virtualAddress()[offset..][0..(b_memory.size() - offset)],
            // TODO: 0.15 use '_'
            else => |sz| sz: {
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

pub fn signalSemaphore(device: *Device, signal_info: mango.SemaphoreSignalInfo) !void {
    _ = device;
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(signal_info.semaphore);
    b_semaphore.signal(signal_info.value);
}

// XXX: Currently only wait_all semantics are implemented, investigate whether wait_any is approachable
pub fn waitSemaphores(device: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: i64) !void {
    _ = device;
    const semaphores = wait_info.semaphores[0..wait_info.semaphore_count];
    const values = wait_info.values[0..wait_info.semaphore_count];

    switch (timeout) {
        -1 => for (semaphores, values) |b_semaphore, value| {
            b_semaphore.wait(value, -1);
        },
        else => |ns| {
            var accumulated_timeout = ns;
            for (semaphores, values) |b_semaphore, value| {
                const start = horizon.getSystemTick();
                b_semaphore.wait(value, accumulated_timeout); 
                const end = horizon.getSystemTick();
                const elapsed = end - start;

                if(elapsed >= accumulated_timeout) {
                    return; 
                }

                accumulated_timeout -= elapsed;
            }
        }
    }
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

    buffer.* = .{
        .memory_info = .empty,
        .size = @intFromEnum(create_info.size),
        .usage = create_info.usage,
    };

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

    std.debug.assert(create_info.extent.width >= 8 and create_info.extent.width <= 1024 and std.mem.isAligned(create_info.extent.width, 8) and create_info.extent.height >= 8 and create_info.extent.height <= 1024 and std.mem.isAligned(create_info.extent.height, 8));

    if (create_info.usage.sampled) {
        std.debug.assert(std.math.isPowerOfTwo(create_info.extent.width) and std.math.isPowerOfTwo(create_info.extent.width) and create_info.tiling == .optimal);
    }

    if (create_info.usage.color_attachment or create_info.usage.depth_stencil_attachment or create_info.usage.shadow_attachment) {
        std.debug.assert(create_info.tiling == .optimal);
    }

    const image = try allocator.create(backend.Image);
    errdefer allocator.destroy(image);

    image.* = .{
        .memory_info = .empty,
        .format = create_info.format,
        .info = .init(create_info),
    };

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

// TODO: Proper assertions.
pub fn copyBuffer(device: *Device, src_buffer: mango.Buffer, dst_buffer: mango.Buffer, regions: []const mango.BufferCopy) void {
    const gsp = device.gsp;

    const b_src_buffer: backend.Buffer = .fromHandle(src_buffer);
    const b_dst_buffer: backend.Buffer = .fromHandle(dst_buffer);

    const b_src_virt = b_src_buffer.memory_info.virtual();
    const b_dst_virt = b_dst_buffer.memory_info.virtual();

    for (regions) |region| {
        const src = b_src_virt[region.src_offset..][0..region.size];
        const dst = b_dst_virt[region.dst_offset..][0..region.size];

        // TODO: Errors?
        gsp.submitRequestDma(src, dst, .none, .none) catch unreachable;

        while (true) {
            const int = gsp.waitInterrupts() catch unreachable;

            if (int.get(.dma) > 0) {
                break;
            }
        }
    }
}

// TODO: Provide a software callback for directly using host memory (akin to VK_EXT_host_image_copy)
pub fn copyBufferToImage(device: *Device, src_buffer: mango.Buffer, dst_image: mango.Image, info: mango.BufferImageCopy) !void {
    const gsp = device.gsp;

    const b_src_buffer: *backend.Buffer = .fromHandleMutable(src_buffer);
    const b_dst_image: *backend.Image = .fromHandleMutable(dst_image);

    const b_src_memory: backend.DeviceMemory.BoundMemoryInfo = b_src_buffer.memory_info;
    const b_dst_memory: backend.DeviceMemory.BoundMemoryInfo = b_dst_image.memory_info;

    const src_offset = @intFromEnum(info.src_offset);

    const native_fmt = b_dst_image.format.nativeColorFormat();
    const pixel_size = native_fmt.bytesPerPixel();

    const img_width = b_dst_image.info.width();
    const img_height = b_dst_image.info.height();
    const full_image_size = img_width * img_height * pixel_size;

    const src_virt = b_src_memory.boundVirtualAddress()[src_offset..][0..full_image_size];
    const dst_virt = b_dst_memory.boundVirtualAddress()[0..full_image_size];

    std.debug.assert(img_width >= 64 and img_height >= 16);

    if (info.flags.memcpy) {
        try gsp.submitRequestDma(src_virt, dst_virt, .none, .none);

        while (true) {
            const int = gsp.waitInterrupts() catch unreachable;

            if (int.contains(.dma)) {
                break;
            }
        }

        return;
    }

    try gsp.submitDisplayTransfer(src_virt.ptr, dst_virt.ptr, native_fmt, .{
        .x = @intCast(img_width),
        .y = @intCast(img_height),
    }, native_fmt, .{
        .x = @intCast(img_width),
        .y = @intCast(img_height),
    }, .{
        .mode = .linear_tiled,
    }, .none);

    while (true) {
        const int = gsp.waitInterrupts() catch unreachable;

        if (int.contains(.ppf)) {
            break;
        }
    }
}

pub fn copyImageToBuffer() void {}

pub fn blitImage(device: *Device, src_image: mango.Image, dst_image: mango.Image) !void {
    const gsp = device.gsp;

    const b_src_image: *backend.Image = .fromHandleMutable(src_image);
    const b_dst_image: *backend.Image = .fromHandleMutable(dst_image);

    const b_src_virt = b_src_image.memory_info.boundVirtualAddress();
    const b_dst_virt = b_dst_image.memory_info.boundVirtualAddress();

    const b_src_color_format = b_src_image.format.nativeColorFormat();
    const b_dst_color_format = b_dst_image.format.nativeColorFormat();

    gsp.submitDisplayTransfer(b_src_virt, b_dst_virt, b_src_color_format, .{
        .x = @intCast(b_src_image.info.width()),
        .y = @intCast(b_src_image.info.height()),
    }, b_dst_color_format, .{
        .x = @intCast(b_dst_image.info.width()),
        .y = @intCast(b_dst_image.info.height()),
    }, .{
        .flip_v = false,
        .mode = switch (b_src_image.info.optimally_tiled) {
            false => switch (b_dst_image.info.optimally_tiled) {
                false => unreachable, // TODO: Linear -> Linear
                true => .linear_tiled,
            },
            true => switch (b_dst_image.info.optimally_tiled) {
                false => .tiled_linear,
                true => .tiled_tiled,
            },
        },
    }, .none) catch unreachable;

    while (true) {
        const int = gsp.waitInterrupts() catch unreachable;

        if (int.contains(.ppf)) {
            break;
        }
    }
}

// TODO: Merge memory fills
pub fn fillBuffer(device: *Device, dst_buffer: mango.Buffer, dst_offset: usize, data: u32) !void {
    const gsp = device.gsp;
    const b_dst_buffer: backend.Buffer = .fromHandle(dst_buffer);

    std.debug.assert(dst_offset <= b_dst_buffer.size);

    const b_dst_virt = b_dst_buffer.memory_info.virtual() + dst_offset;
    const dst_fill_size = b_dst_buffer.size - dst_offset;

    gsp.submitMemoryFill(.{ .init(@alignCast(b_dst_virt[0..dst_fill_size]), .fill32(data)), null }, .none) catch unreachable;

    while (true) {
        const int = gsp.waitInterrupts() catch unreachable;

        if (int.get(.psc0) > 0) {
            break;
        }
    }
}

pub fn clearColorImage(device: *Device, image: mango.Image, color: *const [4]u8) !void {
    const gsp = device.gsp;

    const b_image: *backend.Image = .fromHandleMutable(image);
    const bound_virtual = b_image.memory_info.boundVirtualAddress();

    const clear_slice, const clear_value: GspGpu.gx.MemoryFillUnit.Value = switch (b_image.format) {
        .a8b8g8r8_unorm => .{
            bound_virtual[0 .. b_image.info.width() * b_image.info.height() * @sizeOf(u32)],
            .fill32(@bitCast(color.*)),
        },
        .b8g8r8_unorm => .{
            bound_virtual[0 .. b_image.info.width() * b_image.info.height() * 3],
            .fill24(@bitCast(pica.ColorFormat.Bgr888{
                .r = color[0],
                .g = color[1],
                .b = color[2],
            })),
        },
        // .a8b8g8r8_unorm =>,
        .r5g6b5_unorm_pack16, .r5g5b5a1_unorm_pack16, .r4g4b4a4_unorm_pack16, .g8r8_unorm => .{
            bound_virtual[0 .. b_image.info.width() * b_image.info.height() * @sizeOf(u16)],
            .fill16(switch (b_image.format) {
                .r5g6b5_unorm_pack16 => @bitCast(pica.ColorFormat.Rgb565{
                    .r = @intCast((@as(usize, color[0]) * std.math.maxInt(u5)) / std.math.maxInt(u8)),
                    .g = @intCast((@as(usize, color[1]) * std.math.maxInt(u6)) / std.math.maxInt(u8)),
                    .b = @intCast((@as(usize, color[2]) * std.math.maxInt(u5)) / std.math.maxInt(u8)),
                }),
                .r5g5b5a1_unorm_pack16 => @bitCast(pica.ColorFormat.Rgba5551{
                    .r = @intCast((@as(usize, color[0]) * std.math.maxInt(u5)) / std.math.maxInt(u8)),
                    .g = @intCast((@as(usize, color[1]) * std.math.maxInt(u5)) / std.math.maxInt(u8)),
                    .b = @intCast((@as(usize, color[2]) * std.math.maxInt(u5)) / std.math.maxInt(u8)),
                    .a = @intFromBool(color[3] != 0),
                }),
                .r4g4b4a4_unorm_pack16 => @bitCast(pica.ColorFormat.Rgba4444{
                    .r = @intCast((@as(usize, color[0]) * std.math.maxInt(u4)) / std.math.maxInt(u8)),
                    .g = @intCast((@as(usize, color[1]) * std.math.maxInt(u4)) / std.math.maxInt(u8)),
                    .b = @intCast((@as(usize, color[2]) * std.math.maxInt(u4)) / std.math.maxInt(u8)),
                    .a = @intCast((@as(usize, color[3]) * std.math.maxInt(u4)) / std.math.maxInt(u8)),
                }),
                .g8r8_unorm => @bitCast(pica.TextureUnitFormat.Hilo88{
                    .r = color[0],
                    .g = color[1],
                }),
                else => unreachable,
            }),
        },
        else => unreachable,
    };

    // TODO: Also applies for above: Maybe we can use the two memory fill units by splitting the addresses?
    gsp.submitMemoryFill(.{ .init(@alignCast(clear_slice), clear_value), null }, .none) catch unreachable;

    while (true) {
        const int = gsp.waitInterrupts() catch unreachable;

        if (int.contains(.psc0)) {
            break;
        }
    }
}

// TODO: Depth-stencil
pub fn clearDepthStencilImage(device: *Device, image: mango.Image, depth: f32, stencil: u8) void {
    _ = device;
    _ = image;
    _ = depth;
    _ = stencil;
}

pub fn submit(device: *Device, submit_info: mango.SubmitInfo) !void {
    const command_buffers = submit_info.command_buffers[0..submit_info.command_buffers_len];
    const gsp = device.gsp;

    for (command_buffers) |cmd| {
        const b_cmd: *backend.CommandBuffer = .fromHandleMutable(cmd);
        std.debug.assert(b_cmd.state == .executable);
        // TODO: set to pending state and reset it to executable

        try gsp.submitProcessCommandList(@alignCast(b_cmd.queue.buffer[0..b_cmd.queue.current_index]), .none, .flush, .none);

        while (true) {
            const int = try gsp.waitInterrupts();

            if (int.contains(.p3d)) {
                break;
            }
        }
    }
}

pub fn getSwapchainImages(device: *Device, swapchain: mango.Swapchain, images: []mango.Image) void {
    return device.presentation_engine.getSwapchainImages(swapchain, images);
}

pub fn acquireNextImage(device: *Device, swapchain: mango.Swapchain) !u8 {
    return device.presentation_engine.acquireNextImage(swapchain);
}

pub fn present(device: *Device, present_info: *const mango.PresentInfo) void {
    _ = device;
    _ = present_info;
}

pub fn waitIdle(device: *Device) void {
    _ = device;
    // TODO: Multithreading when the Io interface lands, this does nothing currently.
}

// XXX: Finish this when we can. Should this should be in the syscore? we must handle vblanks and the app may be badly programmed (no yields)...
fn driverMain(ctx: *anyopaque) callconv(.c) noreturn {
    const device: *Device = @ptrCast(@alignCast(ctx));
    const presentation_engine = &device.presentation_engine;
    const gsp = device.gsp;

    while (true) {
        const interrupts = gsp.waitInterrupts() catch continue;
        var interrupts_it = interrupts.iterator();

        while (interrupts_it.next()) |int| switch (int) {
            .vblank_top => presentation_engine.refresh(gsp, .top),
            .vblank_bottom => presentation_engine.refresh(gsp, .bottom),
            else => {}
        };
    }

    horizon.exitThread();
}

comptime {
    std.debug.assert(VRamBankAllocator.min_alignment_byte_units == 4096);
}

const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(4096), zitrus.memory.vram_bank_size);

const Device = @This();
const backend = @import("backend.zig");

const PresentationEngine = backend.PresentationEngine;

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const GspGpu = horizon.services.GspGpu;

const mango = zitrus.mango;
const pica = zitrus.pica;

const PhysicalAddress = zitrus.PhysicalAddress;
