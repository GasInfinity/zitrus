// https://www.3dbrew.org/wiki/GSP_Services

const service_name = "gsp::Gpu";

pub const Error = ClientSession.RequestError;

pub const Shared = extern struct {
    interrupt_queue: [4]Interrupt.Queue,
    _unknown0: [0x100]u8,
    framebuffers: [4][2]FramebufferInfo,
    _unknown1: [0x400]u8,
    command_queue: [4]gx.Queue,

    comptime {
        std.debug.assert(@offsetOf(Shared, "interrupt_queue") == 0x000);
        std.debug.assert(@sizeOf(Interrupt.Queue) == 0x40);

        std.debug.assert(@offsetOf(Shared, "framebuffers") == 0x200);
        std.debug.assert(@sizeOf([2]FramebufferInfo) == 0x80);

        std.debug.assert(@offsetOf(Shared, "command_queue") == 0x800);
        std.debug.assert(@sizeOf(gx.Queue) == 0x200);
    }
};

// https://www.3dbrew.org/wiki/GSP_Shared_Memory#Interrupt%20Queue
pub const Interrupt = enum(u8) {
    psc0,
    psc1,
    vblank_top,
    vblank_bottom,
    ppf,
    p3d,
    dma,

    pub const Set = std.EnumArray(Interrupt, u32);

    pub const Queue = extern struct {
        pub const Header = packed struct(u32) {
            pub const Flags = packed struct(u8) { skip_pdc: bool = false, _unused: u7 = 0 };

            offset: u8,
            count: u8,
            missed_other: bool,
            _reserved0: u7 = 0,
            flags: Flags,
        };

        pub const max_interrupts = 0x34;

        header: Header,
        missed_pdc0: u32,
        missed_pdc1: u32,
        interrupt_list: [max_interrupts]Interrupt,
    };
};

pub const FramebufferInfo = extern struct {
    pub const Flags = packed struct(u8) { new_data: bool, _unused0: u7 = 0 };

    pub const Header = packed struct(u32) {
        index: u1,
        _unused0: u7 = 0,
        flags: Flags,
        _unused1: u16 = 0,
    };

    pub const Framebuffer = extern struct {
        pub const Active = enum(u32) { first, second };

        active: Active,
        left_vaddr: *anyopaque,
        right_vaddr: *anyopaque,
        stride: usize,
        format: FramebufferFormat,
        select: u32,
        attribute: u32,
    };

    header: Header,
    framebuffers: [2]Framebuffer,
    _unused0: u32 = 0,
};

pub const gx = struct {
    pub const SubmitFlags = packed struct(u8) {
        pub const none: SubmitFlags = .{};

        stop_processing_queue: bool = false,
        fail_if_busy: bool = false,
        _: u6 = 0,
    };

    pub const MemoryFillUnit = struct {
        pub const Value = union(gpu.PixelSize) {
            @"16": u16,
            @"24": u24,
            @"32": u32,

            pub fn fill16(value: u16) Value {
                return .{ .@"16" = value };
            }

            pub fn fill24(value: u24) Value {
                return .{ .@"24" = value };
            }

            pub fn fill32(value: u32) Value {
                return .{ .@"32" = value };
            }
        };

        buffer: []align(8) u8,
        value: Value,

        pub fn init(buffer: []align(8) u8, value: Value) MemoryFillUnit {
            return .{ .buffer = buffer, .value = value };
        }
    };

    pub const DisplayTransferFlags = packed struct(u8) {
        pub const none: DisplayTransferFlags = .{};
        pub const Mode = enum(u2) {
            tiled_linear,
            linear_tiled,
            tiled_tiled,
        };

        flip_v: bool = false,
        mode: Mode = .tiled_linear,
        use_32x32: bool = false,
        downscale: gpu.Registers.MemoryCopy.Flags.Downscale = .none,
        _: u2 = 0,
    };

    pub const Command = extern struct {
        pub const Id = enum(u8) {
            request_dma,
            process_command_list,
            memory_fill,
            display_transfer,
            texture_copy,
            flush_cache_regions,
        };

        pub const Header = packed struct(u32) {
            command_id: Id,
            _unused0: u8 = 0,
            stop_processing_queue: bool = false,
            _unused1: u7 = 0,
            fail_if_busy: bool = false,
            _unused2: u7 = 0,
        };

        pub const Flush = packed struct(u32) {
            pub const none: Flush = .{};
            pub const flush: Flush = .{ .should_flush = true };

            should_flush: bool = false,
            _: u31 = 0,
        };

        pub const DmaRequest = extern struct {
            source: [*]const u8,
            destination: [*]u8,
            size: usize,
            _unused0: [3]u32 = @splat(0),
            flush: Flush,
        };

        pub const ProcessCommandList = extern struct {
            pub const UpdateGasResults = packed struct(u32) {
                pub const none: UpdateGasResults = .{};
                pub const update_gas: UpdateGasResults = .{ .update_gas_results = true };

                update_gas_results: bool = false,
                _: u31 = 0,
            };

            address: [*]align(8) const u32,
            byte_size: usize,
            update_gas_results: UpdateGasResults,
            _unused0: [3]u32 = @splat(0),
            flush: Flush,
        };

        pub const MemoryFill = extern struct {
            pub const Buffer = extern struct {
                pub const none: Buffer = .{ .start = null, .value = 0, .end = null };

                start: ?*anyopaque,
                value: u32,
                end: ?*anyopaque,

                pub fn init(fill: gx.MemoryFillUnit) Buffer {
                    return .{
                        .start = fill.buffer.ptr,
                        .value = switch (fill.value) {
                            inline else => |v| v,
                        },
                        .end = fill.buffer.ptr + fill.buffer.len,
                    };
                }
            };

            buffers: [2]Buffer,
            controls: [2]gpu.Registers.MemoryFill.Control,
        };

        pub const DisplayTransfer = extern struct {
            source: [*]const u8,
            destination: [*]u8,
            source_dimensions: gpu.U16x2,
            destination_dimensions: gpu.U16x2,
            flags: gpu.Registers.MemoryCopy.Flags,
            _unused0: [2]u32 = @splat(0),
        };

        pub const TextureCopy = extern struct {
            source: [*]const u8,
            destination: [*]u8,
            size: usize,
            source_line_gap: gpu.U16x2,
            destination_line_gap: gpu.U16x2,
            flags: gpu.Registers.MemoryCopy.Flags,
            _unused0: u32 = 0,
        };

        pub const FlushCacheRegions = extern struct {
            pub const Buffer = extern struct {
                pub const none: Buffer = .{ .address = null, .size = 0 };

                address: ?*const anyopaque,
                size: usize,

                pub fn init(buffer: []const u8) Buffer {
                    return .{ .address = buffer.ptr, .size = buffer.len };
                }
            };

            buffers: [3]Buffer,
            _unused0: u32 = 0,
        };

        header: Header,
        data: extern union {
            dma_request: DmaRequest,
            process_command_list: ProcessCommandList,
            memory_fill: Command.MemoryFill,
            display_transfer: DisplayTransfer,
            texture_copy: TextureCopy,
            flush_cache_regions: FlushCacheRegions,
        },
    };

    pub const Queue = extern struct {
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

        pub const max_commands = 15;

        header: Header,
        last_result: ResultCode,
        _unused0: [6]u32 = @splat(0),
        commands: [max_commands]Command,
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

pub const PerfLogInfo = extern struct {
    pub const Measurements = extern struct {
        delta: u32,
        sum: u32,
    };

    psc: [2]Measurements,
    pdc: [2]Measurements,
    ppf: Measurements,
    p3d: Measurements,
    dma: Measurements,
};

session: ClientSession,
has_right: bool = false,
interrupt_event: Event = @bitCast(@intFromEnum(Object.null)),
thread_index: u32 = 0,
shared_memory_block: MemoryBlock = @bitCast(@intFromEnum(Object.null)),
shared_memory: ?*Shared = null,

pub fn init(srv: ServiceManager) !GspGpu {
    const gsp_handle = try srv.getService(service_name, .wait);

    var gsp = GspGpu{ .session = gsp_handle };
    errdefer gsp.deinit();

    try gsp.acquireRight(0x0);

    const interrupt_event = try Event.create(.oneshot);
    gsp.interrupt_event = interrupt_event;

    // XXX: What does this flag mean?
    const queue_result = try gsp.sendRegisterInterruptRelayQueue(0x1, interrupt_event);

    if (queue_result.should_init_hw) {
        try gsp.initializeHardware();
    }

    gsp.thread_index = queue_result.response.thread_index;
    gsp.shared_memory_block = queue_result.response.gsp_memory;

    const shared_memory = try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(@sizeOf(Shared), .fromByteUnits(4096));
    gsp.shared_memory = std.mem.bytesAsValue(Shared, shared_memory);

    try queue_result.response.gsp_memory.map(@alignCast(shared_memory.ptr), .rw, .dont_care);
    return gsp;
}

pub fn deinit(gsp: *GspGpu) void {
    if (gsp.shared_memory_block.obj != .null) {
        if (gsp.shared_memory) |shm| {
            gsp.shared_memory_block.unmap(@ptrCast(@alignCast(shm)));
            // TODO: change this when we find a solution to shared memory
            horizon.heap.non_thread_safe_shared_memory_address_allocator.free(std.mem.asBytes(shm));
        }

        gsp.shared_memory_block.deinit();
    }

    gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    gsp.releaseRight() catch unreachable;

    if (gsp.interrupt_event.int.sync.obj != .null) {
        gsp.interrupt_event.deinit();
    }

    gsp.session.deinit();
    gsp.* = undefined;
}

pub fn waitInterrupts(gsp: *GspGpu) Error!Interrupt.Set {
    return (try gsp.waitInterruptsTimeout(-1)).?;
}

pub fn pollInterrupts(gsp: *GspGpu) Error!?Interrupt.Set {
    return try gsp.waitInterruptsTimeout(0);
}

pub fn waitInterruptsTimeout(gsp: *GspGpu, timeout_ns: i64) Error!?Interrupt.Set {
    const int_ev = gsp.interrupt_event;

    int_ev.wait(timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    };

    var interrupts = Interrupt.Set.initFill(0);

    while (gsp.dequeueInterrupt()) |int| {
        interrupts.set(int, interrupts.get(int) + 1);
    }

    return interrupts;
}

pub fn dequeueInterrupt(gsp: *GspGpu) ?Interrupt {
    const gsp_data = gsp.shared_memory.?;
    const interrupt_queue: *Interrupt.Queue = &gsp_data.interrupt_queue[gsp.thread_index];

    const int = i: while (true) {
        const interrupt_header = @atomicLoad(Interrupt.Queue.Header, &interrupt_queue.header, .monotonic);

        if (interrupt_header.count == 0) {
            break :i null;
        }

        const interrupt_index = interrupt_header.offset;
        const int = interrupt_queue.interrupt_list[interrupt_index];

        if (@cmpxchgWeak(Interrupt.Queue.Header, &interrupt_queue.header, interrupt_header, .{
            .offset = if (interrupt_index == Interrupt.Queue.max_interrupts - 1) 0 else interrupt_index + 1,
            .count = interrupt_header.count - 1,
            .missed_other = false,
            .flags = .{},
        }, .monotonic, .monotonic) == null) {
            @branchHint(.likely);
            break :i int;
        }
    };

    return int;
}

pub fn FramebufferPresent(comptime screen: Screen) type {
    return struct {
        active: FramebufferInfo.Framebuffer.Active,
        color_format: ColorFormat,
        left_vaddr: *anyopaque,
        right_vaddr: *anyopaque,
        stride: usize,
        mode: (if (screen == .top) FramebufferMode else void) = if (screen == .top) .@"2d" else undefined,
        dma_size: DmaSize,
    };
}

pub fn presentFramebuffer(gsp: *GspGpu, comptime screen: Screen, present: FramebufferPresent(screen)) Error!bool {
    return gsp.writeFramebufferInfo(screen, FramebufferInfo.Framebuffer{
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

pub fn writeFramebufferInfo(gsp: *GspGpu, screen: Screen, info: FramebufferInfo.Framebuffer) Error!bool {
    const gsp_data = gsp.shared_memory.?;
    const framebuffer_info: *FramebufferInfo = &gsp_data.framebuffers[gsp.thread_index][@intFromEnum(screen)];
    const initial_framebuffer_header: FramebufferInfo.Header = @atomicLoad(FramebufferInfo.Header, &framebuffer_info.header, .monotonic);

    const next_active = initial_framebuffer_header.index +% 1;
    framebuffer_info.framebuffers[next_active] = info;

    // Ensure the framebuffer info is written and the gsp can see it before we update the header.
    zitrus.arm.dsb();

    var framebuffer_header = initial_framebuffer_header;
    while (@cmpxchgWeak(FramebufferInfo.Header, &framebuffer_info.header, framebuffer_header, .{
        .index = next_active,
        .flags = .{ .new_data = true },
    }, .monotonic, .monotonic)) |_| {
        framebuffer_header = @atomicLoad(FramebufferInfo.Header, &framebuffer_info.header, .monotonic);
    }

    // This only is false when the gsp finished processing the last framebuffer
    return framebuffer_header.flags.new_data;
}

pub fn submitRequestDma(gsp: *GspGpu, src: []const u8, dst: []u8, flush: gx.Command.Flush, submit_flags: gx.SubmitFlags) !void {
    std.debug.assert(src.len == dst.len);

    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .request_dma,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .dma_request = .{
            .source = src.ptr,
            .destination = dst.ptr,
            .size = src.len,
            .flush = flush,
        } },
    });
}

pub fn submitProcessCommandList(gsp: *GspGpu, command_list: []align(8) const u32, update_gas: gx.Command.ProcessCommandList.UpdateGasResults, flush: gx.Command.Flush, submit_flags: gx.SubmitFlags) !void {
    std.debug.assert(std.mem.isAligned(command_list.len * @sizeOf(u32), 16));

    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .process_command_list,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .process_command_list = .{
            .address = command_list.ptr,
            .byte_size = command_list.len * @sizeOf(u32),
            .update_gas_results = update_gas,
            .flush = flush,
        } },
    });
}

pub fn submitMemoryFill(gsp: *GspGpu, fills: [2]?gx.MemoryFillUnit, submit_flags: gx.SubmitFlags) !void {
    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .memory_fill,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .memory_fill = .{
            .buffers = .{
                if (fills[0]) |fill| .init(fill) else .none,
                if (fills[1]) |fill| .init(fill) else .none,
            },
            .controls = .{
                if (fills[0]) |fill| .init(std.meta.activeTag(fill.value)) else .none,
                if (fills[1]) |fill| .init(std.meta.activeTag(fill.value)) else .none,
            },
        } },
    });
}

pub fn submitDisplayTransfer(gsp: *GspGpu, src: [*]const u8, dst: [*]u8, src_color: gpu.ColorFormat, src_dimensions: gpu.U16x2, dst_color: gpu.ColorFormat, dst_dimensions: gpu.U16x2, flags: gx.DisplayTransferFlags, submit_flags: gx.SubmitFlags) !void {
    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .display_transfer,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .display_transfer = .{
            .source = src,
            .destination = dst,
            .source_dimensions = src_dimensions,
            .destination_dimensions = dst_dimensions,
            .flags = .{
                .flip_v = flags.flip_v,
                .output_width_less_than_input = src_dimensions.x > dst_dimensions.x,
                .linear_tiled = flags.mode == .linear_tiled,
                .tiled_tiled = flags.mode == .tiled_tiled,
                .input_format = src_color,
                .output_format = dst_color,
                .use_32x32_tiles = flags.use_32x32,
                .downscale = flags.downscale,
                .texture_copy_mode = false,
            },
        } },
    });
}

pub fn submitTextureCopy(gsp: *GspGpu, src: [*]const u8, dst: [*]u8, size: usize, src_gaps: gpu.U16x2, dst_gaps: gpu.U16x2, submit_flags: gx.SubmitFlags) !void {
    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .display_transfer,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .texture_copy = .{
            .source = src,
            .destination = dst,
            .size = size,
            .source_line_gap = src_gaps,
            .destination_line_gap = dst_gaps,
            .flags = .{
                .flip_v = false,
                .output_width_less_than_input = src_gaps.x > dst_gaps.x,
                .linear_tiled = false,
                .tiled_tiled = false,
                .input_format = .bgra8888,
                .output_format = .bgra8888,
                .use_32x32_tiles = false,
                .downscale = .none,
                .texture_copy_mode = true,
            },
        } },
    });
}

pub fn submitFlushCacheRegions(gsp: *GspGpu, buffers: [3]?[]const u8, submit_flags: gx.SubmitFlags) !void {
    return gsp.submitGxCommand(gx.Command{
        .header = .{
            .command_id = .flush_cache_regions,
            .stop_processing_queue = submit_flags.stop_processing_queue,
            .fail_if_busy = submit_flags.fail_if_busy,
        },
        .data = .{ .flush_cache_regions = .{
            .buffers = .{
                if (buffers[0]) |buffer| .init(buffer) else .none,
                if (buffers[1]) |buffer| .init(buffer) else .none,
                if (buffers[2]) |buffer| .init(buffer) else .none,
            },
        } },
    });
}

pub fn submitGxCommand(gsp: *GspGpu, cmd: gx.Command) !void {
    const gsp_data = gsp.shared_memory.?;
    const gx_queue: *gx.Queue = &gsp_data.command_queue[gsp.thread_index];
    const gx_header: gx.Queue.Header = @atomicLoad(gx.Queue.Header, &gx_queue.header, .monotonic);

    if (gx_header.total_commands >= gx.Queue.max_commands) {
        return error.OutOfCommandSlots;
    }

    const next_command_index: u4 = (@as(u4, @intCast(gx_header.current_command_index)) +% @as(u4, @intCast(gx_header.total_commands)));
    gx_queue.commands[next_command_index] = cmd;

    // Same as with the fb info
    zitrus.arm.dsb();

    var gx_total_commands = gx_header.total_commands;

    while (@cmpxchgWeak(u8, &gx_queue.header.total_commands, gx_total_commands, gx_total_commands + 1, .monotonic, .monotonic)) |_| {
        gx_total_commands = @atomicLoad(u8, &gx_queue.header.total_commands, .monotonic);
    }

    // NOTE: This means gx_queue.header.total_commands is now 1
    if (gx_total_commands == 0) {
        return gsp.sendTriggerCmdReqQueue();
    }
}

pub fn initializeHardware(gsp: *GspGpu) Error!void {
    const gpu_registers: *gpu.Registers = memory.gpu_registers;

    try gsp.writeHwRegs(&gpu_registers.internal.irq.ack[0], std.mem.asBytes(&[_]u32{0x00}));
    try gsp.writeHwRegs(&gpu_registers.internal.irq.cmp[0], std.mem.asBytes(&[_]u32{0x12345678}));
    try gsp.writeHwRegs(&gpu_registers.internal.irq.mask, std.mem.asBytes(&[_]u32{ 0xFFFFFFF0, 0xFFFFFFFF }));
    try gsp.writeHwRegs(&gpu_registers.internal.irq.autostop, std.mem.asBytes(&gpu.Registers.Internal.Interrupt.AutoStop{
        .stop_command_list = true,
    }));
    try gsp.writeHwRegs(&gpu_registers.timing_control, std.mem.asBytes(&[_]u32{ 0x22221200, 0xFF2 }));

    // Initialize top screen
    // Taken from: https://www.3dbrew.org/wiki/GPU/External_Registers#LCD_Source_Framebuffer_Setup / https://www.3dbrew.org/wiki/GPU/External_Registers#Framebuffers
    try gsp.writeHwRegs(&gpu_registers.pdc[0].horizontal, std.mem.asBytes(&gpu.Registers.Pdc.Timing{
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
    try gsp.writeHwRegs(&gpu_registers.pdc[0].vertical, std.mem.asBytes(&gpu.Registers.Pdc.Timing{
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
    try gsp.writeHwRegs(&gpu_registers.pdc[0].pixel_dimensions, std.mem.asBytes(&gpu.U16x2{
        .x = Screen.top.width(),
        .y = Screen.top.height(),
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].horizontal_border, std.mem.asBytes(&gpu.U16x2{
        .x = 209,
        .y = 449,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].vertical_border, std.mem.asBytes(&gpu.U16x2{
        .x = 2,
        .y = 402,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].framebuffer_format, std.mem.asBytes(&FramebufferFormat{
        .color_format = .abgr8888,
        .interlacing_mode = .none,
        .alternative_pixel_output = false,
        .unknown0 = 1,
        .dma_size = .@"128",
        .unknown1 = 1,
        .unknown2 = 8,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0].control, std.mem.asBytes(&gpu.Registers.Pdc.Control{
        .enable = true,
        .disable_hblank_irq = true,
        .disable_vblank_irq = false,
        .disable_error_irq = true,
        .enable_output = true,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[0]._unknown5, std.mem.asBytes(&@as(u32, 0x00)));

    // Initialize bottom screen
    // From here I couldn't find any info about the bottom screen registers so these values are just yoinked from libctru.
    try gsp.writeHwRegs(&gpu_registers.pdc[1].horizontal, std.mem.asBytes(&gpu.Registers.Pdc.Timing{
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
    try gsp.writeHwRegs(&gpu_registers.pdc[1].vertical, std.mem.asBytes(&gpu.Registers.Pdc.Timing{
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
    try gsp.writeHwRegs(&gpu_registers.pdc[1].pixel_dimensions, std.mem.asBytes(&gpu.U16x2{
        .x = Screen.bottom.width(),
        .y = Screen.bottom.height(),
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].horizontal_border, std.mem.asBytes(&gpu.U16x2{
        .x = 209,
        .y = 449,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].vertical_border, std.mem.asBytes(&gpu.U16x2{
        .x = 82,
        .y = 402,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].framebuffer_format, std.mem.asBytes(&FramebufferFormat{
        .color_format = .abgr8888,
        .interlacing_mode = .none,
        .alternative_pixel_output = false,
        .unknown0 = 1,
        .dma_size = .@"128",
        .unknown1 = 1,
        .unknown2 = 8,
    }));
    try gsp.writeHwRegs(&gpu_registers.pdc[1].control, std.mem.asBytes(&gpu.Registers.Pdc.Control{
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

pub fn readHwRegs(gsp: GspGpu, address: *anyopaque, buffer: []u8) Error!void {
    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 0x80) {
        const size = @min(buffer.len - buffer_offset, 0x80);

        try gsp.sendReadHwRegs(offset, buffer[buffer_offset..][0..size]);
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
    return switch (try data.ipc.sendRequest(gsp.session, command.WriteHwRegs, .{ .offset = offset, .size = buffer.len, .data = .init(buffer) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendWriteHwRegsWithMask(gsp: GspGpu, offset: usize, buffer: []const u8, mask: []const u8) Error!void {
    std.debug.assert(buffer.len == mask.len);
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.WriteHwRegsWithMask, .{ .offset = offset, .size = buffer.len, .data = .init(buffer), .mask = .init(mask) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendWriteHwRegRepeat(gsp: GspGpu, offset: usize, buffer: []const u8) Error!void {
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    return switch (data.ipc.sendRequest(gsp.session, command.WriteHwRegRepeat, .{ .offset = offset, .size = buffer.len, .data = .init(buffer) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReadHwRegs(gsp: GspGpu, offset: usize, buffer: []u8) Error!void {
    std.debug.assert(buffer.len <= 0x80 and std.mem.isAligned(buffer.len, 4));

    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.ReadHwRegs, .{ .offset = offset, .size = buffer.len }, .{buffer})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetBufferSwap(gsp: GspGpu, screen: Screen, info: FramebufferInfo) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetBufferSwap, .{ .screen = screen, .info = info }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendFlushDataCache(gsp: GspGpu, buffer: []u8) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.FlushDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInvalidateDataCache(gsp: GspGpu, buffer: []u8) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.InvalidateDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetLcdForceBlack(gsp: GspGpu, fill: bool) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetLcdForceBlack, .{ .fill = fill }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendTriggerCmdReqQueue(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.TriggerCmdReqQueue, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetAxiConfigQosMode(gsp: GspGpu, qos: u32) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetAxiConfigQosMode, .{ .qos = qos }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetPerfLogMode(gsp: GspGpu, enabled: bool) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetPerfLogMode, .{ .enabled = enabled }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetPerfLog(gsp: GspGpu) Error!PerfLogInfo {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.GetPerfLog, .{}, .{})) {
        .success => |s| s.value.response.info,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const RegisterInterruptRelayQueueResponse = struct {
    should_init_hw: bool,
    response: command.RegisterInterruptRelayQueue.Response,
};

pub fn sendRegisterInterruptRelayQueue(gsp: GspGpu, unknown_flags: u8, event: Event) Error!RegisterInterruptRelayQueueResponse {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.RegisterInterruptRelayQueue, .{ .flags = unknown_flags, .ev = event }, .{})) {
        .success => |s| .{
            .should_init_hw = s.code.description == @as(horizon.result.Description, @enumFromInt(0x207)),
            .response = s.value.response,
        },
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterInterruptRelayQueue(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.UnregisterInterruptRelayQueue, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendTryAcquireRight(gsp: GspGpu, init_hw: u8) Error!bool {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.TryAcquireRight, .{ .init_hw = init_hw, .process = .current }, .{})) {
        .success => true,
        .failure => |code| if (code == @as(horizon.ResultCode, @bitCast(@as(u32, 0xC8402BF0)))) false else horizon.unexpectedResult(code),
    };
}

pub fn sendAcquireRight(gsp: GspGpu, init_hw: u8) Error!void {
    const data = tls.getThreadLocalStorage();
    data.ipc.packRequest(command.AcquireRight, .{ .init_hw = init_hw, .process = .current }, .{});

    // FIXME: WHY DOES THIS NOT WORK WITHOUT NOINLINE????
    // What happens is that the event for gsp interrupts never signals after for example returning from home or in rare cases after continuing from a break while debugging...
    // It doesn't make any sense as it happens EVEN if this is not called (e.f: after breaking from debugging somewhere unrelated)
    try @call(.never_inline, ClientSession.sendRequest, .{gsp.session});
    return switch (data.ipc.unpackResponse(command.AcquireRight)) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseRight(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.ReleaseRight, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendImportDisplayCaptureInfo(gsp: GspGpu) Error!ScreenCapture {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.ImportDisplayCaptureInfo, .{}, .{})) {
        .success => |s| s.value.response.capture,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSaveVRAMSysArea(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SaveVRamSysArea, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRestoreVRAMSysArea(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.RestoreVRamSysArea, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendResetGpuCore(gsp: GspGpu) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.ResetGpuCore, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetLedForceOff(gsp: GspGpu, disable: bool) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetLedForceOff, .{ .disable = disable }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetInternalPriorities(gsp: GspGpu, session_thread: u6, command_queue: u6) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.SetInternalPriorities, .{ .session_thread = session_thread, .command_queue = command_queue }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendStoreDataCache(gsp: GspGpu, buffer: []u8) Error!void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.StoreDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const WriteHwRegs = ipc.Command(Id, .write_hw_regs, struct {
        offset: usize,
        size: usize,
        data: ipc.StaticSlice(0),
    }, struct {});
    pub const WriteHwRegsWithMask = ipc.Command(Id, .write_hw_regs_with_mask, struct {
        offset: usize,
        size: usize,
        data: ipc.StaticSlice(0),
        mask: ipc.StaticSlice(1),
    }, struct {});
    pub const WriteHwRegRepeat = ipc.Command(Id, .write_hw_reg_repeat, struct {
        offset: usize,
        size: usize,
        data: ipc.StaticSlice(0),
    }, struct {});
    pub const ReadHwRegs = ipc.Command(Id, .read_hw_regs, struct {
        pub const static_buffers = 1;
        offset: usize,
        size: usize,
    }, struct {
        output: ipc.StaticSlice(0),
    });
    pub const SetBufferSwap = ipc.Command(Id, .set_buffer_swap, struct { screen: Screen, info: FramebufferInfo }, struct {});
    // SetCommandList stubbed
    // RequestDma stubbed
    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct { address: usize, size: usize, process: horizon.Process }, struct {});
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct { address: usize, size: usize, process: horizon.Process }, struct {});
    // RegisterInterruptEvents stubbed
    pub const SetLcdForceBlack = ipc.Command(Id, .set_lcd_force_black, struct { fill: bool }, struct {});
    pub const TriggerCmdReqQueue = ipc.Command(Id, .trigger_cmd_req_queue, struct {}, struct {});
    // SetDisplayTransfer stubbed
    // SetTextureCopy stubbed
    // SetMemoryFill stubbed
    pub const SetAxiConfigQosMode = ipc.Command(Id, .set_axi_config_qos_mode, struct { qos: u32 }, struct {});
    pub const SetPerfLogMode = ipc.Command(Id, .set_perf_log_mode, struct { enabled: bool }, struct {});
    pub const GetPerfLog = ipc.Command(Id, .get_perf_log, struct {}, struct { info: PerfLogInfo });
    pub const RegisterInterruptRelayQueue = ipc.Command(Id, .register_interrupt_relay_queue, struct {
        flags: u32,
        ev: Event,
    }, struct {
        thread_index: u32,
        gsp_memory: MemoryBlock,
    });
    pub const UnregisterInterruptRelayQueue = ipc.Command(Id, .unregister_interrupt_relay_queue, struct {}, struct {});
    pub const TryAcquireRight = ipc.Command(Id, .try_acquire_right, struct { process: horizon.Process }, struct {});
    pub const AcquireRight = ipc.Command(Id, .acquire_right, struct { init_hw: u32, process: horizon.Process }, struct {});
    pub const ReleaseRight = ipc.Command(Id, .release_right, struct {}, struct {});
    pub const ImportDisplayCaptureInfo = ipc.Command(Id, .import_display_capture_info, struct {}, struct { capture: ScreenCapture });
    pub const SaveVRamSysArea = ipc.Command(Id, .save_vram_sys_area, struct {}, struct {});
    pub const RestoreVRamSysArea = ipc.Command(Id, .restore_vram_sys_area, struct {}, struct {});
    pub const ResetGpuCore = ipc.Command(Id, .reset_gpu_core, struct {}, struct {});
    pub const SetLedForceOff = ipc.Command(Id, .set_led_force_off, struct { disable: bool }, struct {});
    // SetTestCommand stubbed
    pub const SetInternalPriorities = ipc.Command(Id, .set_internal_priorities, struct { session_thread: u6, command_queue: u6 }, struct {});
    pub const StoreDataCache = ipc.Command(Id, .store_data_cache, struct { address: usize, size: usize, process: horizon.Process }, struct {});

    pub const Id = enum(u16) {
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
    };
};

const GspGpu = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.pica;

const horizon = zitrus.horizon;
const memory = horizon.memory;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Screen = gpu.Screen;
const ColorFormat = gpu.ColorFormat;
const DmaSize = gpu.DmaSize;
const FramebufferFormat = gpu.FramebufferFormat;
const FramebufferMode = FramebufferFormat.Mode;

const ResultCode = horizon.result.Code;
const Object = horizon.Object;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
const ClientSession = horizon.ClientSession;
const ServiceManager = zitrus.horizon.ServiceManager;

const SharedMemoryAddressAllocator = horizon.SharedMemoryAddressAllocator;
