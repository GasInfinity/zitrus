pub const CreateInfo = struct {
    /// The GSP session the device will use to communicate with the
    /// process.
    gsp: horizon.services.GraphicsServerGpu,

    /// The address arbiter the device will use when it needs to wait
    /// and signal threads.
    arbiter: horizon.AddressArbiter,

    /// The driver's thread priority, by default is `0x1A` (Very high)
    driver_priority: horizon.Thread.Priority = .priority(0x1A),

    /// The driver's thread processor, by default is `-2`
    driver_processor: horizon.Thread.Processor = .default,
};

const vtable: Device.VTable = .{
    .destroy = destroy,

    .reacquire = reacquire,
    .release = release,

    .waitIdleQueue = waitIdleQueue,
    .wakeIdleQueue = wakeIdleQueue,

    .getShaderCode = getShaderCode,
    .destroyShaderCode = destroyShaderCode,

    .allocateMemory = allocateMemory,
    .freeMemory = freeMemory,
    .mapMemory = mapMemory,
    .unmapMemory = unmapMemory,
    .flushMappedMemoryRanges = flushMappedMemoryRanges,
    .invalidateMappedMemoryRanges = invalidateMappedMemoryRanges,

    .createSwapchain = createSwapchain,
    .destroySwapchain = destroySwapchain,
    .getSwapchainImages = getSwapchainImages,
    .acquireNextImage = acquireNextImage,

    .waitSemaphores = waitSemaphores,
    .signalSemaphore = signalSemaphore,

    .virtualToPhysical = virtualToPhysical,
};

const CodeCache = struct {
    pub const empty: CodeCache = .{
        .uid = .init(0),
        .entries = .empty,
        .mutex = .init,
    };

    const Key = backend.Shader.Code.Key;
    const Context = struct {
        pub fn eql(_: Context, a: Key, b: Key, _: usize) bool {
            return a.hash == b.hash and std.mem.eql(pica.shader.encoding.Instruction, a.instructions, b.instructions) and std.mem.eql(pica.shader.encoding.OperandDescriptor, a.descriptors, b.descriptors);
        }

        pub fn hash(_: Context, k: Key) u32 {
            return k.hash;
        }
    };

    uid: std.atomic.Value(u32),
    entries: std.ArrayHashMapUnmanaged(Key, *backend.Shader.Code, Context, false),
    mutex: AddressArbiter.Mutex,

    pub fn deinit(cache: *CodeCache, gpa: std.mem.Allocator) void {
        cache.entries.deinit(gpa);
        cache.* = undefined;
    }

    pub fn getOrAdd(cache: *CodeCache, gpa: std.mem.Allocator, arbiter: AddressArbiter, key: Key) !*backend.Shader.Code {
        cache.mutex.lock(arbiter);
        defer cache.mutex.unlock(arbiter);

        const entry = try cache.entries.getOrPut(gpa, key);
        errdefer cache.entries.swapRemoveAt(entry.index);

        if (entry.found_existing) {
            const code = entry.value_ptr.*;
            std.debug.assert(code.ref.fetchAdd(1, .monotonic) > 0);

            return code;
        }

        const new_uid = cache.uid.fetchAdd(1, .monotonic);
        const new_code = try gpa.create(backend.Shader.Code);
        errdefer gpa.destroy(new_code);

        const new_instructions = try gpa.dupe(pica.shader.encoding.Instruction, key.instructions);
        errdefer gpa.free(new_instructions);

        const new_descriptors = try gpa.dupe(pica.shader.encoding.OperandDescriptor, key.descriptors);
        errdefer gpa.free(new_descriptors);

        new_code.* = .init(new_uid, key.hash, new_instructions, new_descriptors);

        entry.value_ptr.* = new_code;
        return new_code;
    }

    pub fn destroy(cache: *CodeCache, gpa: std.mem.Allocator, arbiter: AddressArbiter, code: *backend.Shader.Code) void {
        std.debug.assert(code.ref.load(.monotonic) == 0);

        cache.mutex.lock(arbiter);
        defer cache.mutex.unlock(arbiter);

        const key: Key = .initCode(code);
        std.debug.assert(cache.entries.swapRemove(key));

        gpa.free(code.instructions);
        gpa.free(code.descriptors);
        gpa.destroy(code);
    }
};

device: Device,
arbiter: AddressArbiter,
gsp: GraphicsServerGpu,
gsp_owned: bool,
gsp_thread_index: u8,
gsp_shm_memory_block: MemoryBlock,
gsp_shm: *GraphicsServerGpu.Shared,
interrupt_event: Event,
driver: horizon.Thread.Impl,

running: std.atomic.Value(bool),
vram_gpas: std.EnumArray(zitrus.memory.VRamBank, VRamBankAllocator),

presentation_engine: PresentationEngine,
code_cache: CodeCache,

pub fn create(create_info: mango.HorizonBackedDeviceCreateInfo, gpa: std.mem.Allocator) !*Horizon {
    const gsp = create_info.gsp;
    const arbiter = create_info.arbiter;

    const h_device = try gpa.create(Horizon);
    errdefer gpa.destroy(h_device);

    try gsp.sendAcquireRight(0x0);

    const interrupt_event: Event = try .create(.oneshot);
    errdefer interrupt_event.close();

    // XXX: What does this flag mean?
    const queue_result = try gsp.sendRegisterInterruptRelayQueue(0x1, interrupt_event);

    if (queue_result.first_initialization) {
        try GraphicsServerGpu.Graphics.initializeHardware(gsp);
    }

    const shared_memory = horizon.heap.allocShared(@sizeOf(GraphicsServerGpu.Shared));
    try queue_result.response.gsp_memory.map(shared_memory, .rw, .dont_care);
    errdefer queue_result.response.gsp_memory.unmap(shared_memory);

    h_device.* = .{
        .device = .{
            .gpa = gpa,
            .linear_gpa = horizon.heap.linear_page_allocator,
            .vtable = vtable,
            .fill_queue = .init(&h_device.device),
            .transfer_queue = .init(&h_device.device),
            .submit_queue = .init(&h_device.device),
            .presentation_queue = .init(&h_device.device),
            .queue_statuses = .initDefault(.init(.idle), .{}),
        },
        .arbiter = arbiter,
        .running = .init(true),
        .vram_gpas = .init(.{
            .a = .init(@ptrFromInt(horizon.memory.vram_a_begin)),
            .b = .init(@ptrFromInt(horizon.memory.vram_b_begin)),
        }),
        .presentation_engine = .init(),
        .gsp_owned = true,
        .gsp = gsp,
        .gsp_thread_index = @intCast(queue_result.response.thread_index),
        .gsp_shm_memory_block = queue_result.response.gsp_memory,
        .gsp_shm = @ptrCast(shared_memory),
        .interrupt_event = interrupt_event,
        .driver = undefined, // NOTE: The driver thread creation is deferred as we want to fully initialize things first!
        .code_cache = .empty,
    };

    h_device.gsp_shm.framebuffers[h_device.gsp_thread_index][0].header = std.mem.zeroes(GraphicsServerGpu.FramebufferInfo.Header);
    h_device.gsp_shm.framebuffers[h_device.gsp_thread_index][1].header = std.mem.zeroes(GraphicsServerGpu.FramebufferInfo.Header);

    h_device.driver = try .spawnOptions(.{
        .allocator = gpa,
    }, driverMain, .{h_device}, .{
        .priority = create_info.driver_priority,
        .processor = create_info.driver_processor,
    });

    return h_device;
}

fn destroy(dev: *Device) void {
    const gpa = dev.gpa;
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));

    h_dev.code_cache.deinit(dev.gpa);
    h_dev.running.store(false, .monotonic);
    h_dev.interrupt_event.signal(); // NOTE: technically not needed as it is always signaled but better be safe than sorry.
    h_dev.driver.join();
    h_dev.gsp_shm_memory_block.unmap(@ptrCast(@alignCast(h_dev.gsp_shm)));

    h_dev.gsp_shm_memory_block.close();
    h_dev.gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    if (h_dev.gsp_owned) h_dev.gsp.sendReleaseRight() catch unreachable;
    h_dev.interrupt_event.close();
    gpa.destroy(h_dev);
}

fn reacquire(dev: *Device) !void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));

    std.debug.assert(!h_dev.gsp_owned);
    defer h_dev.gsp_owned = true;

    const gsp = h_dev.gsp;
    const pe = &h_dev.presentation_engine;

    gsp.sendAcquireRight(0x0) catch |err| switch (err) {
        else => return error.Unexpected,
    };
    gsp.sendRestoreVRAMSysArea() catch |err| switch (err) {
        else => return error.Unexpected,
    };
    try pe.reacquire(gsp);
}

fn release(dev: *Device) mango.ReleaseDeviceError!GraphicsServerGpu.ScreenCapture {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));

    std.debug.assert(h_dev.gsp_owned);
    defer h_dev.gsp_owned = false;

    const gsp = h_dev.gsp;

    dev.waitIdle();
    gsp.sendSaveVRAMSysArea() catch |err| switch (err) {
        else => return error.Unexpected,
    };
    const capture = gsp.sendImportDisplayCaptureInfo() catch |err| switch (err) {
        else => return error.Unexpected,
    };
    gsp.sendReleaseRight() catch |err| switch (err) {
        else => return error.Unexpected,
    };
    return capture;
}

fn waitIdleQueue(dev: *Device, queue: Queue.Type) void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));

    const queue_status = dev.queue_statuses.getPtr(queue);

    while (true) switch (queue_status.load(.acquire)) {
        .idle, .lost => break,
        .waiting, .working, .work_completed => _ = h_dev.arbiter.wait(Queue.Status, &queue_status.raw, .idle),
    };
}

fn wakeIdleQueue(dev: *Device, queue: Queue.Type) void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));

    if (dev.queue_statuses.getPtr(queue).load(.monotonic) == .idle) {
        h_dev.interrupt_event.signal();
    }
}

fn getShaderCode(dev: *Device, key: backend.Shader.Code.Key) mango.ObjectCreationError!*backend.Shader.Code {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    return try h_dev.code_cache.getOrAdd(dev.gpa, h_dev.arbiter, key);
}

fn destroyShaderCode(dev: *Device, code: *backend.Shader.Code) void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    h_dev.code_cache.destroy(dev.gpa, h_dev.arbiter, code);
}

fn allocateMemory(dev: *Device, allocate_info: mango.MemoryAllocateInfo, gpa: std.mem.Allocator) mango.ObjectCreationError!mango.DeviceMemory {
    _ = gpa;
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    const aligned_allocation_size = std.mem.alignForward(usize, @intFromEnum(allocate_info.allocation_size), horizon.heap.page_size);

    const allocated_memory: backend.DeviceMemory = switch (allocate_info.memory_type) {
        .fcram_cached => fcram: {
            const allocated_virtual_address = switch (horizon.controlMemory(.{
                .kind = .commit,
                .area = .all,
                .linear = true,
            }, null, null, aligned_allocation_size, .rw).cases()) {
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
            const vram_bank_gpa = h_dev.vram_gpas.getPtr(bank);
            const allocated_virtual_address = try vram_bank_gpa.alloc(aligned_allocation_size, VRamBankAllocator.min_alignment);

            break :vram .{ .data = .init(allocated_virtual_address.ptr, horizon.memory.toPhysical(@intFromPtr(allocated_virtual_address.ptr)), aligned_allocation_size, @enumFromInt(@as(u2, @intFromEnum(bank)) + 1)) };
        },
    };

    return allocated_memory.toHandle();
}

fn freeMemory(dev: *Device, memory: mango.DeviceMemory, gpa: std.mem.Allocator) void {
    _ = gpa;
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    const b_memory: backend.DeviceMemory = .fromHandle(memory);

    std.debug.assert(b_memory.data.valid);

    switch (b_memory.data.heap) {
        .fcram => _ = horizon.controlMemory(.{
            .kind = .free,
            .area = .all,
            .linear = true,
        }, @ptrCast(b_memory.virtualAddress()), null, b_memory.size(), .rw),
        .vram_a, .vram_b => {
            const bank: zitrus.memory.VRamBank = switch (b_memory.data.heap) {
                .fcram => unreachable,
                .vram_a => .a,
                .vram_b => .b,
            };

            const vram_bank_gpa = h_dev.vram_gpas.getPtr(bank);
            vram_bank_gpa.free(b_memory.virtualAddress()[0..b_memory.size()]);
        },
    }
}

fn mapMemory(dev: *Device, memory: mango.DeviceMemory, offset: mango.DeviceSize, size: mango.DeviceSize) mango.MapMemoryError![]u8 {
    _ = dev;
    const b_memory: backend.DeviceMemory = .fromHandle(memory);
    const b_offset = @intFromEnum(offset);

    std.debug.assert(std.mem.isAligned(b_offset, horizon.heap.page_size) and b_offset <= b_memory.size());

    if (size != .whole) {
        std.debug.assert(@intFromEnum(size) <= (b_memory.size() - b_offset));

        return (b_memory.virtualAddress() + b_offset)[0..@intFromEnum(size)];
    }

    return (b_memory.virtualAddress() + b_offset)[0 .. b_memory.size() - b_offset];
}

fn unmapMemory(device: *Device, memory: mango.DeviceMemory) void {
    _ = device;
    _ = memory;
    // NOTE: Currently does nothing, could do something in the future
}

fn flushMappedMemoryRanges(dev: *Device, ranges: []const mango.MappedMemoryRange) mango.FlushMemoryError!void {
    _ = dev;

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

fn invalidateMappedMemoryRanges(dev: *Device, ranges: []const mango.MappedMemoryRange) mango.InvalidateMemoryError!void {
    _ = dev;

    for (ranges) |range| {
        const b_memory: backend.DeviceMemory = .fromHandle(range.memory);

        const offset = @intFromEnum(range.offset);
        const invalidated_memory = switch (range.size) {
            .whole => b_memory.virtualAddress()[offset..][0..(b_memory.size() - offset)],
            _ => |sz| sz: {
                const size = @intFromEnum(sz);

                std.debug.assert(size <= (b_memory.size() - offset));

                break :sz b_memory.virtualAddress()[offset..][0..size];
            },
        };

        // TODO: error handling
        _ = horizon.invalidateProcessDataCache(.current, invalidated_memory);
    }
}

fn createSwapchain(dev: *Device, create_info: mango.SwapchainCreateInfo, gpa: std.mem.Allocator) mango.ObjectCreationError!mango.Swapchain {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    return h_dev.presentation_engine.initSwapchain(create_info, gpa);
}

fn destroySwapchain(dev: *Device, swapchain: mango.Swapchain, gpa: std.mem.Allocator) void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    return h_dev.presentation_engine.deinitSwapchain(h_dev.gsp, h_dev.gsp_owned, swapchain, gpa);
}

fn getSwapchainImages(dev: *Device, swapchain: mango.Swapchain, images: []mango.Image) mango.GetSwapchainImagesError!u8 {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    return h_dev.presentation_engine.getSwapchainImages(swapchain, images);
}

fn acquireNextImage(dev: *Device, swapchain: mango.Swapchain, timeout: u64) mango.AcquireNextImageError!u8 {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    return h_dev.presentation_engine.acquireNextImage(h_dev.arbiter, swapchain, timeout);
}

fn waitSemaphores(dev: *Device, wait_info: mango.SemaphoreWaitInfo, timeout: u64) mango.WaitSemaphoreError!void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    const arbiter = h_dev.arbiter;

    const semas = wait_info.semaphores[0..wait_info.semaphore_count];
    const values = wait_info.values[0..wait_info.semaphore_count];

    var real_timeout: horizon.Timeout, var last: u96 = if (timeout > std.math.maxInt(u63))
        .{ .none, 0 }
    else
        .{ .fromNanoseconds(@intCast(timeout)), horizon.time.getSystemNanoseconds() };

    for (semas, values) |sema, value| {
        const b_sema: *backend.Semaphore = .fromHandleMutable(sema);

        while (b_sema.counterValue() < value) {
            if (@intFromEnum(real_timeout) == 0) return error.Timeout;

            arbiter.decrementWaitTimeout(i32, &b_sema.wake.raw, 1, real_timeout) catch {
                // XXX: Azahar does not have the same behavior as ofw, this somehow becomes a timeout even if timeout == -1
                // So we may get a Timeout before the driver waking us

                return if (b_sema.counterValue() >= value) {} else error.Timeout;
            };

            switch (real_timeout) {
                .none => {},
                _ => {
                    const now = horizon.time.getSystemNanoseconds();
                    const elapsed = now - last;
                    last = now;

                    real_timeout = if (elapsed >= @intFromEnum(real_timeout))
                        .fromNanoseconds(0)
                    else
                        @enumFromInt(@intFromEnum(real_timeout) - @as(u63, @intCast(elapsed)));
                },
            }
        }
    }
}

fn signalSemaphore(dev: *Device, signal_info: mango.SemaphoreSignalInfo) mango.SignalSemaphoreError!void {
    const h_dev: *Horizon = @alignCast(@fieldParentPtr("device", dev));
    const arbiter = h_dev.arbiter;
    const b_semaphore: *backend.Semaphore = .fromHandleMutable(signal_info.semaphore);

    if (b_semaphore.signal(signal_info.value)) {
        // Only wake if anyone was waiting
        arbiter.signal(i32, &b_semaphore.wake.raw, null);
    }
}

fn virtualToPhysical(_: *Device, virtual: *const anyopaque) zitrus.hardware.PhysicalAddress {
    return horizon.memory.toPhysical(@intFromPtr(virtual));
}

// XXX: Currently if some error happens in the driver, the entire app crashes! Should we report an error condition?
// Is really something we can do...?

// TODO: audit queues and rewrite them (without public API changes)
fn driverMain(h_dev: *Horizon) void {
    const dev = &h_dev.device;
    const gsp = h_dev.gsp;
    const int_que = &h_dev.gsp_shm.interrupt_queue[h_dev.gsp_thread_index];
    const gx = &h_dev.gsp_shm.command_queue[h_dev.gsp_thread_index];
    const fbs = &h_dev.gsp_shm.framebuffers[h_dev.gsp_thread_index];
    const presentation_engine = &h_dev.presentation_engine;

    // NOTE: it isn't cleared by GSP
    gx.clear();
    int_que.clear();
    for (fbs, 0..) |*fb, i| _ = fb.update(.{
        .active = .first,
        .left_vaddr = null,
        .right_vaddr = null,
        .stride = 0,
        .format = .{
            .dma_size = .@"64",
            .pixel_format = .abgr8888,
            .interlacing = .none,
            .half_rate = i == 0, // top screen
        },
        .select = 0,
        .attribute = 0,
    });

    var completion_signals: std.EnumArray(Queue.Type, Queue.SemaphoreOperation) = .initFill(.none);
    var submission_time: std.EnumArray(Queue.Type, u96) = .initFill(0);
    var submission_buffer: ?*backend.CommandBuffer = null;

    while (h_dev.running.load(.monotonic)) {
        // It's impossible to get less than 1 interrupt per second, we always get an interrupt,
        // even if we don't have right!
        h_dev.interrupt_event.wait(.fromNanoseconds(std.time.ns_per_s)) catch |err| switch (err) {
            error.Timeout => h_dev.driverLost(gsp, null),
            else => unreachable,
        };

        const interrupts = int_que.popBackAll();

        // NOTE: The application may have wanted to wake us up! In that case we don't get any interrput
        if (!interrupts.eql(.initEmpty())) {
            for (std.enums.values(GraphicsServerGpu.Interrupt)) |int| {
                const kind: Queue.Type = switch (int) {
                    .psc0, .psc1 => .fill,
                    .ppf => .transfer,
                    .p3d => .submit,
                    .vblank_top, .vblank_bottom => .present,
                    else => continue,
                };

                if (interrupts.contains(int)) {
                    defer dev.queue_statuses.getPtr(kind).store(.work_completed, .monotonic);

                    const completion = completion_signals.getPtr(kind);
                    defer completion.* = .none;

                    if (completion.sema) |sema| {
                        signalSemaphore(dev, .{
                            .semaphore = sema.toHandle(),
                            .value = completion.value,
                        }) catch unreachable;
                    }

                    switch (int) {
                        .p3d => {
                            submission_buffer.?.notifyCompleted();
                            submission_buffer = null;
                        },
                        .vblank_top => presentation_engine.refresh(h_dev.arbiter, gsp, fbs, .top),
                        .vblank_bottom => presentation_engine.refresh(h_dev.arbiter, gsp, fbs, .bottom),
                        .dma, .psc0, .psc1, .ppf => {},
                    }

                    continue;
                }
            }
        }

        var enqueued_commands: usize = 0;
        queue: for (std.enums.values(Queue.Type)) |kind| {
            const queue_status = dev.queue_statuses.getPtr(kind);

            hang: switch (queue_status.load(.monotonic)) {
                .working => {
                    if (kind == .present) break :hang;

                    const last_submission_time = submission_time.get(kind);
                    const elapsed_without_interrupt = horizon.time.getSystemNanoseconds() -% last_submission_time;

                    if (elapsed_without_interrupt > lose_ns_sentinel) h_dev.driverLost(gsp, kind);
                    continue :queue;
                },
                .work_completed, .waiting, .idle, .lost => {},
            }

            switch (kind) {
                inline else => |comptime_kind| {
                    const queue = switch (comptime_kind) {
                        .fill => &dev.fill_queue,
                        .transfer => &dev.transfer_queue,
                        .submit => &dev.submit_queue,
                        .present => &dev.presentation_queue,
                    };

                    work: switch (queue.workPopBack()) {
                        .empty => {
                            const empty_status: Queue.Status = switch (comptime_kind) {
                                .fill, .transfer, .submit => .idle,

                                // NOTE: The present queue is considered idle when all outstanding present operations are handled, a.k.a: unless we presented all frames we're still working!
                                .present => present_status: for (std.enums.values(pica.Screen)) |screen| {
                                    if (presentation_engine.chain_presents.getPtr(screen).load(.monotonic) > 0) {
                                        break :present_status .working;
                                    }
                                } else .idle,
                            };

                            const last_status = queue_status.swap(empty_status, .monotonic);

                            // Is anyone waiting for us? Wake them!
                            if (last_status != .idle and empty_status == .idle) {
                                h_dev.arbiter.signal(Queue.Status, &queue_status.raw, null);
                            }
                        },
                        .wait => queue_status.store(.waiting, .monotonic),
                        .work => |item| {
                            queue_status.store(.working, .monotonic);
                            defer {
                                enqueued_commands += 1;
                                completion_signals.getPtr(comptime_kind).* = item.signal;
                                submission_time.set(comptime_kind, horizon.time.getSystemNanoseconds());
                            }

                            const value = item.value;

                            switch (comptime_kind) {
                                .fill => {
                                    gx.pushFrontAssumeCapacity(.initMemoryFill(.{ .init(value.data, value.value), null }, .none));
                                },
                                .transfer => {
                                    switch (value.flags.kind) {
                                        .copy => gx.pushFrontAssumeCapacity(.initTextureCopy(
                                            value.src,
                                            value.dst,
                                            value.flags.extra.copy,
                                            value.input_gap_size,
                                            value.output_gap_size,
                                            .none,
                                        )),
                                        .linear_tiled, .tiled_linear, .tiled_tiled => gx.pushFrontAssumeCapacity(.initDisplayTransfer(
                                            value.src,
                                            value.dst,
                                            value.flags.extra.transfer.src_fmt,
                                            value.input_gap_size,
                                            value.flags.extra.transfer.dst_fmt,
                                            value.output_gap_size,
                                            .{
                                                .mode = switch (value.flags.kind) {
                                                    .copy => unreachable,
                                                    .linear_tiled => .linear_tiled,
                                                    .tiled_linear => .tiled_linear,
                                                    .tiled_tiled => .tiled_tiled,
                                                },
                                                .downscale = value.flags.extra.transfer.downscale,
                                                .use_32x32 = value.flags.extra.transfer.use_32x32,
                                            },
                                            .none,
                                        )),
                                    }
                                },
                                .submit => {
                                    const b_cmd = value.cmd_buffer;
                                    defer submission_buffer = b_cmd;

                                    {
                                        var next = b_cmd.stream.list.first;

                                        while (next) |node| {
                                            next = node.next;

                                            const segment: *pica.command.stream.Segment = @alignCast(@fieldParentPtr("node", node));
                                            _ = horizon.flushProcessDataCache(.current, @ptrCast(segment.queue.buffer[0..segment.queue.end]));
                                        }
                                    }

                                    const buffer = b_cmd.head;
                                    gx.pushFrontAssumeCapacity(.initProcessCommandList(buffer, .none, .none, .none));
                                },
                                .present => {
                                    // NOTE: Same as above, the present queue is "special".
                                    // It never has to wait to present (the user is the one who waits when acquiring an image!)
                                    presentation_engine.present(h_dev.arbiter, fbs, value);
                                    continue :work queue.workPopBack();
                                },
                            }
                        },
                    }
                },
            }
        }

        if (enqueued_commands > 0) gsp.sendTriggerCmdReqQueue() catch unreachable;
    }
}

// TODO: make this not a panic (error.DeviceLost)
// TODO: make this dump useful info (like the command buffer)
fn driverLost(h_dev: *Horizon, gsp: GraphicsServerGpu, kind: ?Queue.Type) noreturn {
    gsp.sendResetGpuCore() catch {};
    GraphicsServerGpu.Graphics.initializeHardware(gsp) catch {};

    h_dev.running.store(false, .monotonic);

    for (std.enums.values(Queue.Type)) |v| {
        // TODO: wake them when we return an error
        _ = h_dev.device.queue_statuses.getPtr(v).swap(.lost, .release);
    }

    log.err(
        \\!!!! PICA200 HANG !!!!
        \\Affected Queue: {s}
    , .{if (kind) |k| @tagName(k) else "irq (none)"});
    @panic("GPU Lost (Timer ran out, see debug output for more info)");
}

const VRamBankAllocator = zalloc.bitmap.StaticBitmapAllocator(.fromByteUnits(4096), zitrus.memory.vram_bank_size);

comptime {
    std.debug.assert(VRamBankAllocator.min_alignment_byte_units == 4096);
}

// anything taking more than 1s in any queue is sus
// TODO: move this somewhere else
const lose_ns_sentinel = 1 * std.time.ns_per_s;

const Horizon = @This();

const PresentationEngine = @import("Horizon/PresentationEngine.zig");
const backend = @import("../backend.zig");

const Device = backend.Device;

const log = validation.log;
const validation = backend.validation;

const Queue = backend.Queue;

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const AddressArbiter = horizon.AddressArbiter;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
