// https://www.3dbrew.org/wiki/GSP_Services

const service_name = "gsp::Gpu";

pub const Error = Session.RequestError;

// https://www.3dbrew.org/wiki/GSP_Shared_Memory#Interrupt%20Queue
pub const InterruptKind = enum(u8) {
    psc0,
    psc1,
    vblank_top,
    vblank_bottom,
    ppf,
    p3d,
    dma,
};

pub const InterruptQueue = extern struct {
    pub const Header = packed struct(u32) {
        pub const Flags = packed struct(u8) { skip_pdc: bool = false, _unused: u7 = 0 };

        offset: u8,
        count: u8,
        missed_other: bool,
        _reserved0: u7 = 0,
        flags: Flags,
    };

    pub const max_interrupts = 0x34;
    pub const Interrupts = std.EnumSet(InterruptKind);

    header: Header,
    missed_pdc0: u32,
    missed_pdc1: u32,
    interrupt_list: [max_interrupts]InterruptKind,
};

pub const FramebufferInfo = extern struct {
    pub const Flags = packed struct(u8) { new_data: bool, _unused0: u7 = 0 };

    pub const Header = packed struct(u32) {
        index: u1,
        _unused0: u7 = 0,
        flags: Flags,
        _unused1: u16 = 0,
    };

    pub const Active = enum(u32) { first, second };

    active: Active,
    left_vaddr: *anyopaque,
    right_vaddr: *anyopaque,
    stride: usize,
    format: FramebufferFormat,
    select: u32,
    attribute: u32,
};

// TODO: MOVE THIS TO SEPARATE FILE!
pub const GxCommand = extern struct {
    pub const Header = packed struct(u32) {
        command_id: u8,
        _unused0: u8 = 0,
        stop_processing_queue: bool = 0,
        _unused1: u7,
        fail_if_any: bool,
        _unused2: u7 = 0,
    };

    pub const DmaRequest = extern struct {};
    pub const ListProcessing = extern struct {};
    pub const MemoryFill = extern struct {};
    pub const DisplayTransfer = extern struct {};
    pub const TextureCopy = extern struct {};
    pub const FlushCacheRegions = extern struct {};

    header: Header,
    data: extern union {
        dma_request: DmaRequest,
        command_list_processing: ListProcessing,
        memory_fill: MemoryFill,
        display_transfer: DisplayTransfer,
        texture_copy: TextureCopy,
        flush_cache_regions: FlushCacheRegions,
    },
};

pub const GxCommandQueue = extern struct {
    pub const StatusFlags = packed struct(u8) {
        halted: bool,
        _unused: u6 = 0,
        fatal_error: bool,
    };

    pub const Header = packed struct(u32) {
        current_command_index: u8,
        total_commands: u8,
        halted: bool,
        _unused0: u6 = 0,
        fatal_error: bool,
        halt_processing: bool,
        _unused1: u7 = 0,
    };
};

pub const ScreenCapture = extern struct {
    pub const Info = extern struct {
        left_vaddr: *anyopaque,
        right_vaddr: *anyopaque,
        format: FramebufferFormat,
        stride: u32,
    };

    top: Info,
    bottom: Info,
};

session: Session,
has_right: bool = false,
interrupt_event: ?Event = null,
thread_index: u32 = 0,
shared_memory: ?MemoryBlock = null,
shared_memory_data: ?[]align(horizon.page_size_min) u8 = null,

pub fn init(srv: ServiceManager, shm_allocator: *SharedMemoryAddressAllocator) (error{OutOfMemory} || Session.ConnectionError || Event.CreationError || MemoryBlock.MapError || Error)!GspGpu {
    const gsp_handle = try srv.getService(service_name, true);

    var gsp = GspGpu{ .session = gsp_handle };
    // gpu.session = gsp_handle; // compiling with ReleaseSmall doesn't set the session above?
    errdefer gsp.deinit(shm_allocator);
    try gsp.acquireRight(0);

    const interrupt_event = try Event.init(.oneshot);
    gsp.interrupt_event = interrupt_event;

    // XXX: What does this flag mean?
    const queue_result = try gsp.sendRegisterInterruptRelayQueue(0x1, interrupt_event);

    if (queue_result.should_initialize_hardware) {
        try gsp.initializeHardware();
    }

    gsp.thread_index = queue_result.thread_index;
    gsp.shared_memory = queue_result.shared_memory;
    gsp.shared_memory_data = try shm_allocator.alloc(4096, .fromByteUnits(4096));

    try gsp.shared_memory.?.map(gsp.shared_memory_data.?.ptr, .rw, .dont_care);
    return gsp;
}

pub fn deinit(gsp: *GspGpu, shm_alloc: *SharedMemoryAddressAllocator) void {
    if (gsp.shared_memory) |*shm_handle| {
        if (gsp.shared_memory_data) |*shm| {
            shm_handle.unmap(shm.ptr);
            shm_alloc.free(shm.*);
        }

        shm_handle.deinit();
    }

    gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    gsp.releaseRight() catch unreachable;

    if (gsp.interrupt_event) |*int_ev| {
        int_ev.deinit();
    }

    gsp.session.deinit();
    gsp.* = undefined;
}

pub fn waitInterrupts(gsp: *GspGpu) Error!InterruptQueue.Interrupts {
    return (try gsp.waitInterruptsTimeout(-1)).?;
}

pub fn pollInterrupts(gsp: *GspGpu) Error!?InterruptQueue.Interrupts {
    return try gsp.waitInterruptsTimeout(0);
}

pub fn waitInterruptsTimeout(gsp: *GspGpu, timeout_ns: i64) Error!?InterruptQueue.Interrupts {
    const int_ev = gsp.interrupt_event.?;

    int_ev.wait(timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    };

    var interrupts = InterruptQueue.Interrupts.initEmpty();

    while (gsp.dequeueInterrupt()) |interrupt| {
        interrupts.setPresent(interrupt, true);
    }

    return interrupts;
}

pub fn dequeueInterrupt(gsp: *GspGpu) ?InterruptKind {
    const gsp_data = gsp.shared_memory_data.?;
    const interrupt_queue: *InterruptQueue = @alignCast(std.mem.bytesAsValue(InterruptQueue, gsp_data[(gsp.thread_index * @sizeOf(InterruptQueue))..][0..@sizeOf(InterruptQueue)]));
    const interrupt_header_address: *u32 = @ptrCast(&interrupt_queue.header);

    const interrupt = i: while (true) {
        const interrupt_header: InterruptQueue.Header = @bitCast(zitrus.arm.ldrex(interrupt_header_address));

        if (interrupt_header.count == 0) {
            @branchHint(.unlikely);
            zitrus.arm.clrex();
            break :i null;
        }

        const interrupt_index = interrupt_header.offset;
        const interrupt = interrupt_queue.interrupt_list[interrupt_index];

        if (zitrus.arm.strex(interrupt_header_address, @bitCast(InterruptQueue.Header{
            .offset = if (interrupt_index == InterruptQueue.max_interrupts - 1) 0 else interrupt_index + 1,
            .count = interrupt_header.count - 1,
            .missed_other = false,
            .flags = .{},
        }))) {
            @branchHint(.likely);
            break :i interrupt;
        }
    };

    return interrupt;
}

pub fn FramebufferPresent(comptime screen: Screen) type {
    return struct {
        active: FramebufferInfo.Active,
        color_format: ColorFormat,
        left_vaddr: *anyopaque,
        right_vaddr: *anyopaque,
        stride: usize,
        mode: (if (screen == .top) TopFramebufferMode else void) = if (screen == .top) .@"2d" else undefined,
        dma_size: DmaSize,
    };
}

pub fn presentFramebuffer(gsp: *GspGpu, comptime screen: Screen, present: FramebufferPresent(screen)) Error!bool {
    return gsp.writeFramebufferInfo(screen, FramebufferInfo{
        .active = present.active,
        .left_vaddr = present.left_vaddr,
        .right_vaddr = present.right_vaddr,
        .stride = present.stride,
        .format = FramebufferFormat{
            .color_format = present.color_format,
            .dma_size = present.dma_size,

            // See https://www.3dbrew.org/wiki/GPU/External_Registers#Framebuffer_format *about alternative_pixel_output
            .interlacing_mode = if (screen == .top) switch (present.mode) {
                .@"2d", .full_resolution => .none,
                .@"3d" => .enable,
            } else .none,
            .alternative_pixel_output = screen == .top and present.mode == .@"2d",
        },
        .select = @intFromEnum(present.active),
        .attribute = 0x0,
    });
}

pub fn writeFramebufferInfo(gsp: *GspGpu, screen: Screen, info: FramebufferInfo) Error!bool {
    const gsp_data = gsp.shared_memory_data.?;
    const framebuffer_info_start = gsp_data[0x200 + (@as(usize, @intFromEnum(screen)) * 0x40) + (gsp.thread_index * 0x80) ..];
    const framebuffer_info: []FramebufferInfo = @alignCast(std.mem.bytesAsSlice(FramebufferInfo, framebuffer_info_start[@sizeOf(FramebufferInfo.Header)..][0..(2 * @sizeOf(FramebufferInfo))]));
    const framebuffer_header_address: *u32 = @alignCast(@ptrCast(framebuffer_info_start.ptr));
    const initial_framebuffer_header: FramebufferInfo.Header = @bitCast(framebuffer_header_address.*);

    const next_active = initial_framebuffer_header.index +% 1;
    framebuffer_info[next_active] = info;

    // Ensure the framebuffer info is written and the gsp can see it before we update the header.
    zitrus.arm.dsb();

    const was_presenting = was: while (true) {
        const framebuffer_header: FramebufferInfo.Header = @bitCast(zitrus.arm.ldrex(framebuffer_header_address));

        if (zitrus.arm.strex(framebuffer_header_address, @bitCast(FramebufferInfo.Header{
            .index = next_active,
            .flags = .{ .new_data = true },
        }))) {
            @branchHint(.likely);
            break :was framebuffer_header.flags.new_data;
        }
    } else unreachable;

    // This only is false when the gsp finished processing the last framebuffer
    return was_presenting;
}

pub fn initializeHardware(gsp: *GspGpu) Error!void {
    const gpu_registers: *gpu.Registers = memory.gpu_registers;

    // XXX: Unknown, https://www.3dbrew.org/wiki/GPU/External_Registers#Map and libctru also just writes these values without knowing what they do
    try gsp.writeHwRegs(&gpu_registers.internal_registers.write_0_on_init_or_cmd, std.mem.asBytes(&[_]u32{0x00}));
    try gsp.writeHwRegs(&gpu_registers.internal_registers.write_0x12345678_on_init, std.mem.asBytes(&[_]u32{0x12345678}));
    try gsp.writeHwRegs(&gpu_registers.internal_registers.write_0xFFFFFFF0_on_init, std.mem.asBytes(&[_]u32{0xFFFFFFF0}));
    try gsp.writeHwRegs(&gpu_registers.internal_registers.write_1_on_init, std.mem.asBytes(&[_]u32{0x01}));
    try gsp.writeHwRegs(&gpu_registers.write_0x22221200_on_init, std.mem.asBytes(&[_]u32{0x22221200}));
    try gsp.writeHwRegs(&gpu_registers.write_0xFF2_on_init, std.mem.asBytes(&[_]u32{0xFF2}));

    // Initialize top screen
    // Taken from: https://www.3dbrew.org/wiki/GPU/External_Registers#LCD_Source_Framebuffer_Setup / https://www.3dbrew.org/wiki/GPU/External_Registers#Framebuffers
    try gsp.writeHwRegs(&gpu_registers.pdc[0].horizontal, std.mem.asBytes(&gpu.Pdc.Timing{
        .total = 0x1C2,
        .start = 0xD1,
        .border = 0x1C1,
        .front_porch = 0x1C1,
        .sync = 0x00,
        .back_porch = 0xCF,
        .border_end = 0xD1,
        .interrupt = 0x1C501C1,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0]._unknown0, std.mem.asBytes(&@as(u32, 0x10000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].vertical, std.mem.asBytes(&gpu.Pdc.Timing{
        .total = 0x19D,
        .start = 0x2,
        .border = 0x1C2,
        .front_porch = 0x1C2,
        .sync = 0x1C2,
        .back_porch = 0x01,
        .border_end = 0x02,
        .interrupt = 0x1960192,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0]._unknown1, std.mem.asBytes(&@as(u32, 0x00)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].disable_sync, std.mem.asBytes(&@as(u32, 0x00)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].pixel_dimensions, std.mem.asBytes(&gpu.Dimensions{
        .x = Screen.top.width(),
        .y = Screen.top.height(),
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].horizontal_border, std.mem.asBytes(&gpu.Dimensions{
        .x = 209,
        .y = 449,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].vertical_border, std.mem.asBytes(&gpu.Dimensions{
        .x = 2,
        .y = 402,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_format, std.mem.asBytes(&FramebufferFormat{
        .color_format = .abgr8,
        .interlacing_mode = .none,
        .alternative_pixel_output = false,
        .unknown0 = 1,
        .dma_size = .@"128",
        .unknown1 = 1,
        .unknown2 = 8,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].control, std.mem.asBytes(&gpu.Pdc.Control{
        .enable = true,
        .disable_hblank_irq = true,
        .disable_vblank_irq = false,
        .disable_error_irq = true,
        .enable_output = true,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0]._unknown5, std.mem.asBytes(&@as(u32, 0x00)));

    // Initialize bottom screen
    // From here I couldn't find any info about the bottom screen registers so these values are just yoinked from libctru.
    try gsp.writeHwRegs(&gpu_registers.pdc[1].horizontal, std.mem.asBytes(&gpu.Pdc.Timing{
        .total = 0x1C2,
        .start = 0xD1,
        .border = 0x1C1,
        .front_porch = 0x1C1,
        .sync = 0xCD,
        .back_porch = 0xCF,
        .border_end = 0xD1,
        .interrupt = 0x1C501C1,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1]._unknown0, std.mem.asBytes(&@as(u32, 0x10000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].vertical, std.mem.asBytes(&gpu.Pdc.Timing{
        .total = 0x19D,
        .start = 0x52,
        .border = 0x192,
        .front_porch = 0x192,
        .sync = 0x4F,
        .back_porch = 0x50,
        .border_end = 0x52,
        .interrupt = 0x1980194,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1]._unknown1, std.mem.asBytes(&@as(u32, 0x00)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].disable_sync, std.mem.asBytes(&@as(u32, 0x11)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].pixel_dimensions, std.mem.asBytes(&gpu.Dimensions{
        .x = Screen.bottom.width(),
        .y = Screen.bottom.height(),
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].horizontal_border, std.mem.asBytes(&gpu.Dimensions{
        .x = 209,
        .y = 449,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].vertical_border, std.mem.asBytes(&gpu.Dimensions{
        .x = 82,
        .y = 402,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].framebuffer_format, std.mem.asBytes(&FramebufferFormat{
        .color_format = .abgr8,
        .interlacing_mode = .none,
        .alternative_pixel_output = false,
        .unknown0 = 1,
        .dma_size = .@"128",
        .unknown1 = 1,
        .unknown2 = 8,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].control, std.mem.asBytes(&gpu.Pdc.Control{
        .enable = true,
        .disable_hblank_irq = true,
        .disable_vblank_irq = false,
        .disable_error_irq = true,
        .enable_output = true,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1]._unknown5, std.mem.asBytes(&@as(u32, 0x00)));

    // Initialize framebuffers
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_a_first, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_a_second, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_b_first, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_b_second, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].swap, std.mem.asBytes(&@as(u32, 0x1)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].framebuffer_a_first, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].framebuffer_a_second, std.mem.asBytes(&@as(u32, 0x18300000)));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].swap, std.mem.asBytes(&@as(u32, 0x1)));

    // libctru does this also so we'll follow along
    try gsp.writeHwRegs(&gpu_registers.clock, std.mem.asBytes(&@as(u32, 0x70100)));
    try gsp.writeHwRegsWithMask(&gpu_registers.dma.control, std.mem.asBytes(&@as(u32, 0x00)), std.mem.asBytes(&@as(u32, 0xFF00)));
    try gsp.writeHwRegsWithMask(&gpu_registers.psc[0].control, std.mem.asBytes(&@as(u32, 0x00)), std.mem.asBytes(&@as(u32, 0xFF)));
    try gsp.writeHwRegsWithMask(&gpu_registers.psc[1].control, std.mem.asBytes(&@as(u32, 0x00)), std.mem.asBytes(&@as(u32, 0xFF)));
}

pub fn acquireRight(gsp: *GspGpu, unknown_flags: u8) Error!void {
    if (gsp.has_right) {
        return;
    }

    try gsp.sendAcquireRight(unknown_flags);
    gsp.has_right = true;
}

pub fn releaseRight(gsp: *GspGpu) Error!void {
    if (!gsp.has_right) {
        return;
    }

    try gsp.sendReleaseRight();
    gsp.has_right = false;
}

pub fn writeHwRegs(gsp: GspGpu, address: *anyopaque, buffer: []const u8) Error!void {
    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 0x80) {
        const size = @min(buffer.len - buffer_offset, 0x80);

        try gsp.sendWriteHwRegs(offset, buffer[buffer_offset..][0..size]);
    }
}

pub fn writeHwRegsWithMask(gsp: GspGpu, address: *anyopaque, buffer: []const u8, mask: []const u8) Error!void {
    std.debug.assert(buffer.len == mask.len);

    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 0x80) {
        const size = @min(buffer.len - buffer_offset, 0x80);

        try gsp.sendWriteHwRegsWithMask(offset, buffer[buffer_offset..][0..size], mask[buffer_offset..][0..size]);
    }
}

const InterrupRelayQueueResult = struct {
    should_initialize_hardware: bool,
    thread_index: u32,
    shared_memory: MemoryBlock,
};

pub fn sendWriteHwRegs(gsp: GspGpu, offset: usize, buffer: []const u8) Error!void {
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.write_hw_regs, .{ offset, buffer.len }, .{ ipc.StaticBufferTranslationDescriptor.init(buffer.len, 0), @intFromPtr(buffer.ptr) });

    try gsp.session.sendRequest();
}

pub fn sendWriteHwRegsWithMask(gsp: GspGpu, offset: usize, buffer: []const u8, mask: []const u8) Error!void {
    std.debug.assert(buffer.len == mask.len);
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.write_hw_regs_with_mask, .{ offset, buffer.len }, .{ ipc.StaticBufferTranslationDescriptor.init(buffer.len, 0), @intFromPtr(buffer.ptr), ipc.StaticBufferTranslationDescriptor.init(mask.len, 1), @intFromPtr(mask.ptr) });

    try gsp.session.sendRequest();
}

pub fn sendWriteHwRegsRepeat(gsp: GspGpu, offset: usize, buffer: []const u8) Error!void {
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.write_hw_regs, .{ offset, buffer.len }, .{ ipc.StaticBufferTranslationDescriptor.init(buffer.len, 0), @intFromPtr(buffer.ptr) });

    try gsp.session.sendRequest();
}

pub fn sendReadHwRegs(gsp: GspGpu, offset: usize, buffer: []u8) Error!void {
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.read_hw_regs, .{ offset, buffer.len }, .{});
    data.ipc_static_buffers[0] = @bitCast(ipc.StaticBufferTranslationDescriptor.init(buffer.len, 0));
    data.ipc_static_buffers[1] = @intFromPtr(buffer.ptr);

    try gsp.session.sendRequest();
}

pub fn sendRegisterInterruptRelayQueue(gsp: GspGpu, unknown_flags: u8, event: Event) Error!InterrupRelayQueueResult {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.register_interrupt_relay_queue, .{@as(u32, unknown_flags)}, .{ ipc.HandleTranslationDescriptor.init(0), @intFromPtr(event.handle) });

    try gsp.session.sendRequest();

    const last_result = data.ipc.getLastResult();
    const should_initialize_hardware = if (last_result.summary == .success and @intFromEnum(last_result.description) == 0x207)
        true
    else ihw: {
        break :ihw false;
    };

    return InterrupRelayQueueResult{
        .should_initialize_hardware = should_initialize_hardware,
        .thread_index = data.ipc.parameters[1],
        .shared_memory = @bitCast(data.ipc.parameters[3]),
    };
}

pub fn sendFlushDataCache(gsp: GspGpu, buffer: []u8) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.flush_data_cache, .{ @intFromPtr(buffer.ptr), buffer.len }, .{ ipc.HandleTranslationDescriptor.init(0), @intFromPtr(horizon.Handle.current_process) });

    try gsp.session.sendRequest();
}

pub fn sendInvalidateDataCache(gsp: GspGpu, buffer: []u8) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.invalidate_data_cache, .{ @intFromPtr(buffer.ptr), buffer.len }, .{ ipc.HandleTranslationDescriptor.init(0), ipc.HandleTranslationDescriptor.replace_by_proccess_id });

    try gsp.session.sendRequest();
}

pub fn sendSetLcdForceBlack(gsp: GspGpu, force: bool) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.set_lcd_force_black, .{@as(u32, @intFromBool(force))}, .{});

    try gsp.session.sendRequest();
}

pub fn sendUnregisterInterruptRelayQueue(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.unregister_interrupt_relay_queue, .{}, .{});

    try gsp.session.sendRequest();
}

pub fn sendTryAcquireRight(gsp: GspGpu, unknown_flags: u8) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.try_acquire_right, .{@as(u32, unknown_flags)}, .{ ipc.HandleTranslationDescriptor.init(0), @intFromPtr(horizon.Handle.current_process) });

    try gsp.session.sendRequest();
    return true;
}

pub fn sendAcquireRight(gsp: GspGpu, unknown_flags: u8) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.acquire_right, .{@as(u32, unknown_flags)}, .{ ipc.HandleTranslationDescriptor.init(0), @intFromPtr(horizon.Handle.current_process) });

    // HACK: WHY DOES THIS NOT WORK WITHOUT NOINLINE????
    // What happens is that the event for gsp interrupts never signals after for example returning from home or in rare cases after continuing from a break while debugging...
    // It doesn't make any sense as it happens EVEN if this is not called (e.f: after breaking from debugging somewhere unrelated)
    try @call(.never_inline, Session.sendRequest, .{gsp.session});
}

pub fn sendReleaseRight(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.release_right, .{}, .{});

    try gsp.session.sendRequest();
}

pub fn sendImportDisplayCaptureInfo(gsp: GspGpu) Error!ScreenCapture {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.import_display_capture_info, .{}, .{});

    try gsp.session.sendRequest();

    return ScreenCapture{
        .top = .{
            .left_vaddr = @ptrFromInt(data.ipc.parameters[1]),
            .right_vaddr = @ptrFromInt(data.ipc.parameters[2]),
            .format = @bitCast(data.ipc.parameters[3]),
            .stride = data.ipc.parameters[4],
        },
        .bottom = .{
            .left_vaddr = @ptrFromInt(data.ipc.parameters[5]),
            .right_vaddr = @ptrFromInt(data.ipc.parameters[6]),
            .format = @bitCast(data.ipc.parameters[7]),
            .stride = data.ipc.parameters[8],
        },
    };
}

pub fn sendSaveVRAMSysArea(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.save_vram_sys_area, .{}, .{});

    try gsp.session.sendRequest();
}

pub fn sendRestoreVRAMSysArea(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.restore_vram_sys_area, .{}, .{});

    try gsp.session.sendRequest();
}

pub fn sendResetGpuCore(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.reset_gsp_core, .{}, .{});

    try gsp.session.sendRequest();
}

pub const Command = enum(u16) {
    write_hw_regs = 0x0001,
    write_hw_regs_with_mask,
    write_hw_reg_repeat,
    read_hw_regs,
    set_buffer_swap,
    set_command_list,
    request_dma,
    flush_data_cache,
    invalidate_data_cache,
    register_interrupt_events,
    set_lcd_force_black,
    trigger_cmd_req_queue,
    set_display_transfer,
    set_texture_copy,
    set_memory_fill,
    set_axi_config_qos_mode,
    set_perf_log_mode,
    get_perf_log,
    register_interrupt_relay_queue,
    unregister_interrupt_relay_queue,
    try_acquire_right,
    acquire_right,
    release_right,
    import_display_capture_info,
    save_vram_sys_area,
    restore_vram_sys_area,
    reset_gpu_core,
    set_led_force_off,
    set_test_command,
    set_internal_priorities,
    store_data_cache,

    pub inline fn normalParameters(cmd: Command) u6 {
        return switch (cmd) {
            .write_hw_regs => 2,
            .write_hw_regs_with_mask => 2,
            .write_hw_reg_repeat => 2,
            .read_hw_regs => 2,
            .set_buffer_swap => 8,
            .set_command_list => 2,
            .request_dma => 3,
            .flush_data_cache => 2,
            .invalidate_data_cache => 2,
            .register_interrupt_events => 1,
            .set_lcd_force_black => 1,
            .trigger_cmd_req_queue => 0,
            .set_display_transfer => 5,
            .set_texture_copy => 6,
            .set_memory_fill => 8,
            .set_axi_config_qos_mode => 1,
            .set_perf_log_mode => 1,
            .get_perf_log => 0,
            .register_interrupt_relay_queue => 1,
            .unregister_interrupt_relay_queue => 0,
            .try_acquire_right => 0,
            .acquire_right => 1,
            .release_right => 0,
            .import_display_capture_info => 0,
            .save_vram_sys_area => 0,
            .restore_vram_sys_area => 0,
            .reset_gpu_core => 0,
            .set_led_force_off => 1,
            .set_test_command => 1,
            .set_internal_priorities => 2,
            .store_data_cache => 2,
        };
    }

    pub inline fn translateParameters(cmd: Command) u6 {
        return switch (cmd) {
            .write_hw_regs => 2,
            .write_hw_regs_with_mask => 4,
            .write_hw_reg_repeat => 2,
            .read_hw_regs => 0,
            .set_buffer_swap => 0,
            .set_command_list => 2,
            .request_dma => 2,
            .flush_data_cache => 2,
            .invalidate_data_cache => 2,
            .register_interrupt_events => 4,
            .set_lcd_force_black => 0,
            .trigger_cmd_req_queue => 0,
            .set_display_transfer => 0,
            .set_texture_copy => 0,
            .set_memory_fill => 0,
            .set_axi_config_qos_mode => 0,
            .set_perf_log_mode => 0,
            .get_perf_log => 0,
            .register_interrupt_relay_queue => 2,
            .unregister_interrupt_relay_queue => 0,
            .try_acquire_right => 2,
            .acquire_right => 2,
            .release_right => 0,
            .import_display_capture_info => 0,
            .save_vram_sys_area => 0,
            .restore_vram_sys_area => 0,
            .reset_gpu_core => 0,
            .set_led_force_off => 0,
            .set_test_command => 0,
            .set_internal_priorities => 0,
            .store_data_cache => 2,
        };
    }
};

const GpuRegister = enum(u32) {
    clock = 0x400004,
    memory_fill_pdc0_start = 0x400010,
    memory_fill_pdc1_start = 0x400020,
    unknown_write_22221200_on_init = 0x400050,
    unknown_write_ff2_on_init = 0x400054,
    dma_transfer_state = 0x400C18,
    framebuffer_setup_pdc0_htotal = 0x400400,
    framebuffer_setup_pdc1_htotal = 0x400500,
    unknown_write_0_on_init = 0x401000,
    unknown_write_12345678_on_init = 0x401080,
    unknown_write_fffffff0_on_init = 0x4010C0,
    unknown_write_1_on_init = 0x4010D0,
    _,

    pub inline fn initFramebufferSetup(screen: Screen, fb_setup_reg: FramebufferSetupRegister) GpuRegister {
        return @enumFromInt(@intFromEnum(GpuRegister.framebuffer_setup_pdc0_htotal) + (@as(usize, @intFromEnum(screen)) * 0x100) + @intFromEnum(fb_setup_reg));
    }

    pub inline fn initFramebufferFill(screen: Screen, fb_fill_reg: MemoryFillRegister) GpuRegister {
        return @enumFromInt(@intFromEnum(GpuRegister.memory_fill_pdc0_start) + (@as(usize, @intFromEnum(screen)) * 0x10) + @intFromEnum(fb_fill_reg));
    }
};

const MemoryFillRegister = enum(u32) { config = 0x00, control = 0x0C };

const FramebufferSetupRegister = enum(u32) {
    htotal = 0x00,
    hstart = 0x04,
    hbr = 0x08,
    hpf = 0x0C,
    hsync = 0x10,
    hpb = 0x14,
    hbl = 0x18,
    hinterrupt_timing = 0x1C,
    unknown0 = 0x20,
    vtotal = 0x24,
    possibly_vblank = 0x28,
    unknown_2c = 0x2c,
    vscanlines = 0x30,
    vdisp = 0x34,
    vdata_offset = 0x38,
    unknown_3c = 0x3c,
    vinterrupt_timing = 0x40,
    similar_hsync = 0x44,
    disable = 0x48,
    overscan_fill_color = 0x4C,
    hcount = 0x50,
    vcount = 0x54,

    image_dimensions = 0x5C,
    hdisp = 0x60,
    unknown_framebuffer_height = 0x64,
    framebuffer_a_first_address = 0x68,
    framebuffer_a_second_address = 0x6C,
    framebuffer_format = 0x70,
    pdc_control = 0x74,
    framebuffer_select_status = 0x78,
    framebuffer_b_first_address = 0x94,
    framebuffer_b_second_address = 0x98,
    unknown_9c = 0x9C,
};

const GspGpu = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const horizon = zitrus.horizon;
const memory = horizon.memory;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Screen = gpu.Screen;
const ColorFormat = gpu.ColorFormat;
const DmaSize = gpu.DmaSize;
const TopFramebufferMode = gpu.TopFramebufferMode;
const FramebufferFormat = gpu.FramebufferFormat;

const ResultCode = horizon.ResultCode;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
const Session = horizon.Session;
const ServiceManager = zitrus.horizon.ServiceManager;

const SharedMemoryAddressAllocator = horizon.SharedMemoryAddressAllocator;
