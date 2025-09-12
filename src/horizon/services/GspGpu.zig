// https://www.3dbrew.org/wiki/GSP_Services
const service_name = "gsp::Gpu";

pub const Graphics = @import("GspGpu/Graphics.zig");

pub const Error = ClientSession.RequestError;

pub const Shared = extern struct {
    interrupt_queue: [4]Interrupt.Queue,
    _unknown0: [0x100]u8,
    framebuffers: [4][2]FramebufferInfo,
    _unknown1: [0x400]u8,
    command_queue: [4]GxCommand.Queue,

    comptime {
        if(builtin.cpu.arch.isArm()) {
            std.debug.assert(@offsetOf(Shared, "interrupt_queue") == 0x000);
            std.debug.assert(@sizeOf(Interrupt.Queue) == 0x40);

            std.debug.assert(@offsetOf(Shared, "framebuffers") == 0x200);
            std.debug.assert(@sizeOf([2]FramebufferInfo) == 0x80);

            std.debug.assert(@offsetOf(Shared, "command_queue") == 0x800);
            std.debug.assert(@sizeOf(GxCommand.Queue) == 0x200);
        }
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

    pub const Set = std.EnumSet(Interrupt);

    pub const Queue = extern struct {
        pub const Header = packed struct(u32) {
            pub const Flags = packed struct(u8) { skip_pdc: bool = false, _unused: u7 = 0 };

            head: u8,
            len: u8,
            missed_other: bool,
            _reserved0: u7 = 0,
            flags: Flags,
        };

        pub const max_interrupts = 0x34;

        header: Header,
        missed_pdc0: u32,
        missed_pdc1: u32,
        buffer: [max_interrupts]Interrupt,

        pub fn popBackAll(queue: *Queue) Set {
            var interrupts = Interrupt.Set.initEmpty();

            while (queue.popBack()) |int| {
                interrupts.setPresent(int, true);
            }

            return interrupts;
        }

        pub fn popBack(queue: *Queue) ?Interrupt {
            const int = i: while (true) {
                const hdr = @atomicLoad(Interrupt.Queue.Header, &queue.header, .monotonic);

                if (hdr.len == 0) {
                    return null;
                }

                const int = queue.buffer[hdr.head];

                if (@cmpxchgWeak(Header, &queue.header, hdr, .{
                    .head = if (hdr.head == queue.buffer.len - 1) 0 else hdr.head + 1,
                    .len = hdr.len - 1,
                    .missed_other = false,
                    .flags = .{},
                }, .monotonic, .monotonic) == null) {
                    @branchHint(.likely);
                    break :i int;
                }
            };

            return int;
        }
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
        left_vaddr: [*]const u8,
        right_vaddr: [*]const u8,
        stride: u32,
        format: FramebufferFormat,
        select: u32,
        attribute: u32,
    };

    header: Header,
    framebuffers: [2]Framebuffer,
    _unused0: u32 = 0,

    pub fn update(info: *FramebufferInfo, new_framebuffer: Framebuffer) bool {
        const initial_hdr: Header = @atomicLoad(Header, &info.header, .monotonic);

        const next_active = initial_hdr.index +% 1;
        info.framebuffers[next_active] = new_framebuffer;

        var hdr = initial_hdr;
        while (@cmpxchgWeak(Header, &info.header, hdr, .{
            .index = next_active,
            .flags = .{ .new_data = true },
        }, .release, .monotonic)) |_| {
            hdr = @atomicLoad(Header, &info.header, .monotonic);
        }

        return initial_hdr.flags.new_data;
    }

    comptime {
        if(builtin.cpu.arch.isArm()) {
            std.debug.assert(@sizeOf(FramebufferInfo) == 0x40);
        }
    }
};

pub const GxCommand = extern struct {
    pub const Id = enum(u8) {
        request_dma,
        process_command_list,
        memory_fill,
        display_transfer,
        texture_copy,
        flush_cache_regions,
    };

    pub const Header = packed struct(u32) {
        pub const Flags = packed struct(u16) {
            pub const none: Flags = .{};

            stop_processing_queue: bool = false,
            _unused0: u7 = 0,
            fail_if_busy: bool = false,
            _unused1: u7 = 0,
        };

        id: Id,
        _unused0: u8 = 0,
        flags: Flags = .none,
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
        // TODO: This could be moved
        pub const Unit = struct {
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

            pub fn init(buffer: []align(8) u8, value: Value) Unit {
                return .{ .buffer = buffer, .value = value };
            }
        };

        pub const Buffer = extern struct {
            pub const none: Buffer = .{ .start = null, .value = 0, .end = null };

            start: ?[*]align(8) u8,
            value: u32,
            end: ?[*]align(8) u8,

            pub fn init(fill: Unit) Buffer {
                return .{
                    .start = fill.buffer.ptr,
                    .value = switch (fill.value) {
                        inline else => |v| v,
                    },
                    .end = @alignCast(fill.buffer.ptr + fill.buffer.len),
                };
            }
        };

        buffers: [2]Buffer,
        controls: [2]gpu.Registers.MemoryFill.Control,
    };

    pub const DisplayTransfer = extern struct {
        pub const Flags = packed struct(u8) {
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

        source: [*]align(8) const u8,
        destination: [*]align(8) u8,
        source_dimensions: [2]u16,
        destination_dimensions: [2]u16,
        flags: gpu.Registers.MemoryCopy.Flags,
        _unused0: [2]u32 = @splat(0),
    };

    pub const TextureCopy = extern struct {
        source: [*]align(8) const u8,
        destination: [*]align(8) u8,
        size: u32,
        source_line_gap: [2]u16,
        destination_line_gap: [2]u16,
        flags: gpu.Registers.MemoryCopy.Flags,
        _unused0: u32 = 0,
    };

    pub const FlushCacheRegions = extern struct {
        pub const Buffer = extern struct {
            pub const none: Buffer = .{ .address = null, .size = 0 };

            address: ?*align(8) const u8,
            size: usize,

            pub fn init(buffer: []align(8) const u8) Buffer {
                return .{ .address = buffer.ptr, .size = buffer.len };
            }
        };

        buffers: [3]Buffer,
        _unused0: u32 = 0,
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

        header: Queue.Header,
        last_result: ResultCode,
        _unused0: [6]u32 = @splat(0),
        commands: [max_commands]GxCommand,

        pub fn pushFrontAssumeCapacity(queue: *Queue, cmd: GxCommand) void {
            const hdr = @atomicLoad(Queue.Header, &queue.header, .monotonic);
            std.debug.assert(hdr.total_commands < max_commands);

            const next_command_index: u4 = @intCast((hdr.current_command_index + hdr.total_commands) % 15);
            queue.commands[next_command_index] = cmd;

            _ = @atomicRmw(u8, &queue.header.total_commands, .Add, 1, .release);
        }
    };

    header: Header,
    command: extern union {
        dma_request: DmaRequest,
        process_command_list: ProcessCommandList,
        memory_fill: MemoryFill,
        display_transfer: DisplayTransfer,
        texture_copy: TextureCopy,
        flush_cache_regions: FlushCacheRegions,
    },

    pub fn initMemoryFill(units: [2]?MemoryFill.Unit, flags: Header.Flags) GxCommand {
        return .{
            .header = .{
                .id = .memory_fill,
                .flags = flags,
            },
            .command = .{ .memory_fill = .{
                .buffers = .{
                    if (units[0]) |fill| .init(fill) else .none,
                    if (units[1]) |fill| .init(fill) else .none,
                },
                .controls = .{
                    if (units[0]) |fill| .init(std.meta.activeTag(fill.value)) else .none,
                    if (units[1]) |fill| .init(std.meta.activeTag(fill.value)) else .none,
                },
            } },
        };
    }

    pub fn initRequestDma(src: []const u8, dst: []u8, flush: GxCommand.Flush, flags: Header.Flags) GxCommand {
        std.debug.assert(src.len == dst.len);

        return .{
            .header = .{
                .id = .request_dma,
                .flags = flags,
            },
            .command = .{ .dma_request = .{
                .source = src.ptr,
                .destination = dst.ptr,
                .size = src.len,
                .flush = flush,
            } },
        };
    }

    pub fn initProcessCommandList(command_buffer: []align(8) const u32, update_gas: ProcessCommandList.UpdateGasResults, flush: Flush, flags: Header.Flags) GxCommand {
        return .{
            .header = .{
                .id = .process_command_list,
                .flags = flags,
            },
            .command = .{ .process_command_list = .{
                .address = command_buffer.ptr,
                .byte_size = command_buffer.len * @sizeOf(u32),
                .update_gas_results = update_gas,
                .flush = flush,
            } },
        };
    }

    pub fn initDisplayTransfer(src: [*]align(8) const u8, dst: [*]align(8) u8, src_color: gpu.ColorFormat, src_dimensions: [2]u16, dst_color: gpu.ColorFormat, dst_dimensions: [2]u16, transfer_flags: DisplayTransfer.Flags, flags: Header.Flags) GxCommand {
        return .{ .header = .{
            .id = .display_transfer,
            .flags = flags,
        }, .command = .{ .display_transfer = .{
            .source = src,
            .destination = dst,
            .source_dimensions = src_dimensions,
            .destination_dimensions = dst_dimensions,
            .flags = .{
                .flip_v = transfer_flags.flip_v,
                .output_width_less_than_input = src_dimensions[0] > dst_dimensions[0],
                .linear_tiled = transfer_flags.mode == .linear_tiled,
                .tiled_tiled = transfer_flags.mode == .tiled_tiled,
                .input_format = src_color,
                .output_format = dst_color,
                .use_32x32_tiles = transfer_flags.use_32x32,
                .downscale = transfer_flags.downscale,
                .texture_copy_mode = false,
            },
        } } };
    }

    pub fn initTextureCopy(src: [*]align(8) const u8, dst: [*]align(8) u8, size: u32, src_gaps: [2]u16, dst_gaps: [2]u16, flags: Header.Flags) GxCommand {
        return .{
            .header = .{
                .id = .texture_copy,
                .flags = flags,
            },
            .command = .{ .texture_copy = .{
                .source = src,
                .destination = dst,
                .size = size,
                .source_line_gap = src_gaps,
                .destination_line_gap = dst_gaps,
                .flags = .{
                    .flip_v = false,
                    .output_width_less_than_input = src_gaps[1] != 0 or dst_gaps[1] != 0, // Must be set when not doing contiguous copies.
                    .linear_tiled = false,
                    .tiled_tiled = false,
                    .input_format = .abgr8888,
                    .output_format = .abgr8888,
                    .use_32x32_tiles = false,
                    .downscale = .none,
                    .texture_copy_mode = true,
                },
            } },
        };
    }

    pub fn initFlushCacheRegions(buffers: [3]?[]const u8, flags: Header.Flags) GxCommand {
        return .{
            .header = .{
                .id = .flush_cache_regions,
                .flags = flags,
            },
            .command = .{ .flush_cache_regions = .{
                .buffers = .{
                    if (buffers[0]) |buffer| .init(buffer) else .none,
                    if (buffers[1]) |buffer| .init(buffer) else .none,
                    if (buffers[2]) |buffer| .init(buffer) else .none,
                },
            } },
        };
    }
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

pub fn open(srv: ServiceManager) !GspGpu {
    return .{ .session = try srv.getService(service_name, .wait) };
}

pub fn close(gsp: GspGpu) void {
    gsp.session.close();
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

const InterruptRelayQueueResult = struct {
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
    first_initialization: bool,
    response: command.RegisterInterruptRelayQueue.Response,
};

pub fn sendRegisterInterruptRelayQueue(gsp: GspGpu, unknown_flags: u8, event: Event) Error!RegisterInterruptRelayQueueResponse {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(gsp.session, command.RegisterInterruptRelayQueue, .{ .flags = unknown_flags, .ev = event }, .{})) {
        .success => |s| .{
            .first_initialization = s.code.description == @as(horizon.result.Description, @enumFromInt(0x207)),
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

    return switch (try data.ipc.sendRequest(gsp.session, command.AcquireRight, .{ .init_hw = init_hw, .process = .current }, .{})) {
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

const builtin = @import("builtin");
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
