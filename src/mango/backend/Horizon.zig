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
driver_state: Driver,

running: std.atomic.Value(bool),
vram_gpas: std.EnumArray(zitrus.memory.VRamBank, VRamBankAllocator),

presentation_engine: PresentationEngine,
code_cache: CodeCache,

pub fn create(create_info: CreateInfo, gpa: std.mem.Allocator) !*Horizon {
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

    var fill_queue: Queue = try .init(gpa, .fill, &h_device.device, backend.max_buffered_queue_items, @sizeOf(Queue.FillItem), .of(Queue.FillItem));
    errdefer fill_queue.deinit(gpa);

    var transfer_queue: Queue = try .init(gpa, .transfer, &h_device.device, backend.max_buffered_queue_items, @sizeOf(Queue.TransferItem), .of(Queue.TransferItem));
    errdefer transfer_queue.deinit(gpa);

    var submit_queue: Queue = try .init(gpa, .submit, &h_device.device, backend.max_buffered_queue_items, @sizeOf(Queue.SubmitItem), .of(Queue.SubmitItem));
    errdefer submit_queue.deinit(gpa);

    var present_queue: Queue = try .init(gpa, .present, &h_device.device, backend.max_present_queue_items, @sizeOf(Queue.PresentationItem), .of(Queue.PresentationItem));
    errdefer present_queue.deinit(gpa);

    h_device.* = .{
        .device = .{
            .gpa = gpa,
            .linear_gpa = horizon.heap.linear_page_allocator,
            .vtable = vtable,
            .queues = .init(.{
                .fill = fill_queue,
                .transfer = transfer_queue,
                .submit = submit_queue,
                .present = present_queue,
            }),
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
        .driver_state = .init,
        .code_cache = .empty,
    };

    h_device.gsp_shm.framebuffers[h_device.gsp_thread_index][0].header = std.mem.zeroes(GraphicsServerGpu.FramebufferInfo.Header);
    h_device.gsp_shm.framebuffers[h_device.gsp_thread_index][1].header = std.mem.zeroes(GraphicsServerGpu.FramebufferInfo.Header);

    h_device.driver = try .spawnOptions(.{
        .allocator = gpa,
    }, Driver.main, .{h_device}, .{
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
    for (std.enums.values(Queue.Type)) |typ| h_dev.device.queues.getPtr(typ).deinit(gpa);
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

const Driver = struct {
    pub const init: Driver = .{
        .submission_signals = .initFill(.none),
        .submission_time = .initFill(0),

        .submission_buffer = null,
        .submission_buffer_node = null,
        .submission_buffer_busy = .empty,
        .enqueued_commands = 0,
    };

    submission_signals: std.EnumArray(Queue.Type, Queue.SemaphoreOperation),
    submission_time: std.EnumArray(Queue.Type, u96),

    submission_buffer: ?*CommandBuffer,
    submission_buffer_node: ?*CommandBuffer.operation.Node,
    // Whether the queue is busy due to the submission buffer.
    submission_buffer_busy: std.EnumSet(Queue.Type),
    enqueued_commands: u8,

    // XXX: Currently if some error happens in the driver, the entire app crashes! Should we report an error condition?
    // Is there really something we can do if that happens...?
    // NOTE: SCHEDULING
    // The scheduling follows a somewhat simple pattern (currently) and MAY CHANGE AT ANY TIME so don't depend on this.
    // Drain all interrupts, signaling semaphores (if any)
    // Drain the current command buffer (has priority over queues)
    // Drain the queues
    fn main(h_dev: *Horizon) void {
        const drv = &h_dev.driver_state;
        const gsp = h_dev.gsp;
        const int_que = &h_dev.gsp_shm.interrupt_queue[h_dev.gsp_thread_index];
        const gx = &h_dev.gsp_shm.command_queue[h_dev.gsp_thread_index];
        const fbs = &h_dev.gsp_shm.framebuffers[h_dev.gsp_thread_index];

        clearState(int_que, gx, fbs);

        while (h_dev.running.load(.monotonic)) {
            // It's impossible to get less than 1 interrupt per second, we always get an interrupt,
            // even if we don't have right!
            h_dev.interrupt_event.wait(.fromNanoseconds(std.time.ns_per_s)) catch |err| switch (err) {
                error.Timeout => drv.lost(null),
                else => unreachable,
            };

            drv.drainInterrupts();
            drv.drainCommandBufferNodes();
            drv.drainQueues();

            if (drv.enqueued_commands > 0) {
                gsp.sendTriggerCmdReqQueue() catch unreachable;
                drv.enqueued_commands = 0;
            }
        }
    }

    fn drainInterrupts(drv: *Driver) void {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const dev = &h_dev.device;
        const int_que = &h_dev.gsp_shm.interrupt_queue[h_dev.gsp_thread_index];
        const fbs = &h_dev.gsp_shm.framebuffers[h_dev.gsp_thread_index];
        const gsp = h_dev.gsp;
        const presentation_engine = &h_dev.presentation_engine;

        const interrupts = int_que.popBackAll();

        // NOTE: The application may have wanted to wake us up! In that case we don't get any interrput
        var it = interrupts.iterator();

        while (it.next()) |int| {
            const kind: Queue.Type = switch (int) {
                .psc0, .psc1 => .fill,
                .ppf => .transfer,
                .p3d => .submit,
                .vblank_top, .vblank_bottom => .present,
                else => continue,
            };

            defer dev.queue_statuses.getPtr(kind).store(.work_completed, .monotonic);

            switch (int) {
                .p3d => {
                    // NOTE: P3D can only happen from the submission buffer
                    std.debug.assert(drv.submission_buffer_busy.contains(.submit));
                    std.debug.assert(drv.submission_buffer_node.?.kind == .graphics);
                    drv.submission_buffer_busy.setPresent(.submit, false);
                    drv.submission_buffer_node = drv.submission_buffer_node.?.nextPtr();
                },
                .ppf, .psc0, .psc1 => {
                    if (drv.submission_buffer_busy.contains(kind)) {
                        std.debug.assert(drv.submission_signals.get(kind).sema == null); // We must have no signals here!
                        drv.submission_buffer_busy.setPresent(kind, false);
                        continue;
                    }

                    const signal = drv.submission_signals.get(kind);
                    drv.submission_signals.set(kind, .none);

                    if (signal.sema) |sema| {
                        signalSemaphore(dev, .{
                            .semaphore = sema.toHandle(),
                            .value = signal.value,
                        }) catch unreachable;
                    }
                },
                .dma => {},
                .vblank_top => presentation_engine.refresh(h_dev.arbiter, gsp, fbs, .top),
                .vblank_bottom => presentation_engine.refresh(h_dev.arbiter, gsp, fbs, .bottom),
            }
        }
    }

    fn drainCommandBufferNodes(drv: *Driver) void {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const dev = &h_dev.device;
        const gx = &h_dev.gsp_shm.command_queue[h_dev.gsp_thread_index];

        if (!drv.submission_buffer_busy.eql(.empty)) return;

        drain_nodes: while (drv.submission_buffer_node) |node| switch (node.kind) {
            .graphics => |kind| {
                const queue_type: Queue.Type = switch (kind) {
                    .graphics => .submit,
                    .timestamp, .begin_query, .end_query => unreachable,
                };

                switch (dev.queue_statuses.getPtr(queue_type).load(.monotonic)) {
                    .work_completed, .idle, .waiting => {
                        const gfx: *CommandBuffer.operation.Graphics = @alignCast(@fieldParentPtr("node", node));
                        std.debug.assert(std.mem.isAligned(@intFromPtr(gfx.head), 16) and std.mem.isAligned(gfx.len, 4));

                        gx.pushFrontAssumeCapacity(.initProcessCommandList(gfx.head[0..gfx.len], .none, .none, .none));
                        drv.submission_buffer_busy.setPresent(queue_type, true);
                        drv.submission_time.set(queue_type, horizon.time.getSystemNanoseconds());
                        dev.queue_statuses.getPtr(queue_type).store(.working, .monotonic);
                        drv.enqueued_commands += 1;
                    },
                    .working, .lost => {},
                }

                break :drain_nodes;
            },
            .timestamp => {
                const tmp: *CommandBuffer.operation.Query = @alignCast(@fieldParentPtr("node", node));
                tmp.pool.writeTimestamp(tmp.query, @truncate(horizon.time.getSystemNanoseconds()));
                drv.submission_buffer_node = node.nextPtr();
            },
            .begin_query, .end_query => |k| {
                const query: *CommandBuffer.operation.Query = @alignCast(@fieldParentPtr("node", node));
                const pool = query.pool;
                const storage: []u32 = @ptrCast(@alignCast(pool.getQueryStorage(query.query)));

                if (k == .begin_query) pool.beginQuery(query.query);
                switch (pool.type) {
                    .timestamp => unreachable,
                    .statistics => {
                        const stats = pool.statistics;
                        const all: extern struct {
                            rast: pica.Graphics.Rasterizer.Statistics,
                            traffic: pica.Registers.TrafficStatistics,
                        } = .{
                            .rast = if (stats.anyRasterizer()) drv.readRasterizerStatistics() else undefined,
                            .traffic = if (stats.anyTraffic()) drv.readTrafficStatistics() else undefined,
                        };
                        const all_slice: []const u32 = @ptrCast(&all);
                        const set: std.bit_set.IntegerBitSet(32) = @bitCast(stats);

                        var i: u32 = 0;
                        var it = set.iterator(.{});
                        while (it.next()) |index| : (i += 1) storage[i] = all_slice[index] -% storage[i];
                    },
                    // TODO: currently not needed
                    // .performance_counter => @panic("TODO"),
                }
                if (k == .end_query) pool.endQuery(query.query);
                drv.submission_buffer_node = node.nextPtr();
            },
        } else if (drv.submission_buffer) |cmd_buf| {
            const signal = drv.submission_signals.get(.submit);
            drv.submission_signals.set(.submit, .none);

            if (signal.sema) |sema| {
                signalSemaphore(dev, .{
                    .semaphore = sema.toHandle(),
                    .value = signal.value,
                }) catch unreachable;
            }

            cmd_buf.notifyCompleted();
            drv.submission_buffer = null;
        }
    }

    fn readTrafficStatistics(drv: *Driver) pica.Registers.TrafficStatistics {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const gsp = h_dev.gsp;

        return gsp.readRegisters(pica.Registers.TrafficStatistics, &horizon.memory.gpu_registers.traffic_statistics) catch unreachable;
    }

    fn readRasterizerStatistics(drv: *Driver) pica.Graphics.Rasterizer.Statistics {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const gsp = h_dev.gsp;

        return gsp.readRegisters(pica.Graphics.Rasterizer.Statistics, &horizon.memory.gpu_registers.p3d.rasterizer.statistics) catch unreachable;
    }

    fn drainQueues(drv: *Driver) void {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const dev = &h_dev.device;
        const gx = &h_dev.gsp_shm.command_queue[h_dev.gsp_thread_index];
        const fbs = &h_dev.gsp_shm.framebuffers[h_dev.gsp_thread_index];
        const presentation_engine = &h_dev.presentation_engine;

        // NOTE: we WANT this order so CommandBuffers are handled first
        queue: for ([_]Queue.Type{ .submit, .fill, .transfer, .present }) |kind| {
            const queue = dev.queues.getPtr(kind);
            const queue_status = dev.queue_statuses.getPtr(kind);

            hang: switch (queue_status.load(.monotonic)) {
                .working => {
                    // The present queue can never hang, PDC *can* hang but that depends on the irq event timeout, not us.
                    if (kind == .present) break :hang;

                    const last_submission_time = drv.submission_time.get(kind);
                    const elapsed_without_interrupt = horizon.time.getSystemNanoseconds() -% last_submission_time;

                    if (elapsed_without_interrupt > lose_ns_sentinel) drv.lost(kind);
                    continue :queue;
                },
                .work_completed, .waiting, .idle, .lost => {},
            }

            work: switch (queue.peekBack()) {
                .empty => {
                    const empty_status: Queue.Status = switch (kind) {
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
                .ready => switch (kind) {
                    .fill, .transfer => {
                        const signal = signal: switch (kind) {
                            .fill => {
                                const fill, const signal = queue.popBackAssumeReady(Queue.FillItem);
                                gx.pushFrontAssumeCapacity(.initMemoryFill(.{ .init(fill.data, fill.value), null }, .none));
                                break :signal signal;
                            },
                            .transfer => {
                                const transfer, const signal = queue.popBackAssumeReady(Queue.TransferItem);
                                switch (transfer.flags.kind) {
                                    .copy => gx.pushFrontAssumeCapacity(.initTextureCopy(
                                        transfer.src,
                                        transfer.dst,
                                        transfer.flags.extra.copy,
                                        transfer.input_gap_size,
                                        transfer.output_gap_size,
                                        .none,
                                    )),
                                    .linear_tiled, .tiled_linear, .tiled_tiled => gx.pushFrontAssumeCapacity(.initDisplayTransfer(
                                        transfer.src,
                                        transfer.dst,
                                        transfer.flags.extra.transfer.src_fmt,
                                        transfer.input_gap_size,
                                        transfer.flags.extra.transfer.dst_fmt,
                                        transfer.output_gap_size,
                                        .{
                                            .mode = switch (transfer.flags.kind) {
                                                .copy => unreachable,
                                                .linear_tiled => .linear_tiled,
                                                .tiled_linear => .tiled_linear,
                                                .tiled_tiled => .tiled_tiled,
                                            },
                                            .downscale = transfer.flags.extra.transfer.downscale,
                                            .use_32x32 = transfer.flags.extra.transfer.use_32x32,
                                        },
                                        .none,
                                    )),
                                }

                                break :signal signal;
                            },
                            .submit, .present => unreachable,
                        };

                        drv.enqueued_commands += 1;
                        drv.submission_signals.set(kind, signal);
                        queue_status.store(.working, .monotonic);
                        drv.submission_time.set(kind, horizon.time.getSystemNanoseconds());
                    },
                    .present => {
                        const present, _ = queue.popBackAssumeReady(Queue.PresentationItem);

                        // NOTE: Same as above, the present queue is "special".
                        // It never has to wait to present (the user is the one who waits when acquiring an image!)
                        presentation_engine.present(h_dev.arbiter, fbs, present);
                        continue :work queue.peekBack();
                    },
                    .submit => {
                        if (drv.submission_buffer) |_| continue :queue; // We have to finish the current one

                        const submit, const signal = queue.popBackAssumeReady(Queue.SubmitItem);
                        drv.submission_signals.getPtr(kind).* = signal;

                        const b_cmd = submit.cmd_buffer;
                        drv.submission_buffer = b_cmd;
                        drv.submission_buffer_node = b_cmd.head;

                        {
                            var next = b_cmd.stream.list.first;

                            while (next) |node| {
                                next = node.next;

                                const segment: *pica.command.stream.Segment = @alignCast(@fieldParentPtr("node", node));
                                _ = horizon.flushProcessDataCache(.current, @ptrCast(segment.queue.buffer[0..segment.queue.end]));
                            }
                        }

                        drv.drainCommandBufferNodes();
                    },
                },
            }
        }
    }

    fn clearState(int_que: *GraphicsServerGpu.Interrupt.Queue, gx: *GraphicsServerGpu.GxCommand.Queue, fbs: *[2]GraphicsServerGpu.FramebufferInfo) void {
        int_que.clear();
        gx.clear();
        // NOTE: we previously set the framebuffers to point to physical address 0
        // but let's better not do that. It may trigger asserts in emulators (such as azahar)
        // and we gain almost nothing by setting them to a known state (as they will be updated
        // afterwards...)
        _ = fbs;
    }

    // TODO: make this not a panic (error.DeviceLost maybe?)
    fn lost(drv: *Driver, maybe_kind: ?Queue.Type) noreturn {
        const h_dev: *Horizon = @alignCast(@fieldParentPtr("driver_state", drv));
        const gsp = h_dev.gsp;

        gsp.sendResetGpuCore() catch {};
        GraphicsServerGpu.Graphics.initializeHardware(gsp) catch {};

        h_dev.running.store(false, .monotonic);

        for (std.enums.values(Queue.Type)) |v| {
            // TODO: wake them when we return an error
            _ = h_dev.device.queue_statuses.getPtr(v).swap(.lost, .release);
        }

        log.err("!!!! PICA200 HANG !!!!", .{});
        log.err("Affected queue: {s}", .{if (maybe_kind) |k| @tagName(k) else "irq (none)"});

        if (drv.submission_buffer) |cmd_buf| {
            log.err("With active submission buffer", .{});

            var busy_it = drv.submission_buffer_busy.iterator();
            while (busy_it.next()) |queue_type| log.err(" -> which had the {t} queue busy", .{queue_type});

            {
                var current = cmd_buf.head;
                var i: usize = 1;
                while (current) |node| : (i += 1) {
                    log.err(" {d}. {t} -> {*}", .{ i, node.kind, node });

                    switch (node.kind) {
                        .graphics => {
                            const gfx: *CommandBuffer.operation.Graphics = @alignCast(@fieldParentPtr("node", node));
                            log.err("    with head {*} and length (in words) {d}", .{ gfx.head, gfx.len });
                        },
                        .timestamp, .begin_query, .end_query => {
                            const query_op: *CommandBuffer.operation.Query = @alignCast(@fieldParentPtr("node", node));
                            log.err("    for query {d} and pool {*}", .{ query_op.query, query_op.pool });
                        },
                    }

                    if (node == drv.submission_buffer_node) log.err("    -----> GPU was lost here", .{});
                    current = node.nextPtr();
                }
            }

            // TODO: make this configurable as a lot of other things.
            // This bloats the binary A LOT (we're literally bringing entire type info of all the registers)
            if (false) {
                log.err("Dumping graphic streams...", .{});

                var current = cmd_buf.head;
                var i: usize = 1;
                while (current) |node| : (i += 1) {
                    defer current = node.nextPtr();

                    if (node.kind != .graphics) continue;

                    const gfx: *CommandBuffer.operation.Graphics = @alignCast(@fieldParentPtr("node", node));

                    log.err(" {d}. Dump start", .{i});
                    var it: pica.command.Dump.Iterator = .init(gfx.head[0..gfx.len]);
                    while (it.next()) |dumped| log.err("{f}", .{dumped});
                    log.err(" {d}. Dump end", .{i});
                }
            } else log.err("Could not dump graphic streams: disabled", .{});
        } else {
            log.err("No active submission buffer", .{});
        }

        @panic("GPU Lost (Timer ran out, see debug output for more info)");
    }
};

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
const CommandBuffer = backend.CommandBuffer;

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
