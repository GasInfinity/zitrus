//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/GSP_Services#GSP_service_%22gsp::Gpu%22

pub const service = "gsp::Gpu";

pub const Graphics = @import("GraphicsServerGpu/Graphics.zig");

pub const Shared = extern struct {
    interrupt_queue: [4]Interrupt.Queue,
    _unknown0: [0x100]u8,
    framebuffers: [4][2]FramebufferInfo,
    _unknown1: [0x400]u8,
    command_queue: [4]GxCommand.Queue,

    comptime {
        if (builtin.cpu.arch.isArm()) {
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

        pub fn clear(queue: *Queue) void {
            @atomicStore(Header, &queue.header, .{
                .head = 0,
                .len = 0,
                .missed_other = false,
                .flags = .{},
            }, .monotonic);
        }

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
        left_vaddr: ?[*]const u8,
        right_vaddr: ?[*]const u8,
        stride: u32,
        format: FramebufferFormat,
        select: u32,
        attribute: u32,
    };

    header: Header,
    framebuffers: [2]Framebuffer,
    _unused0: u32 = 0,

    pub fn update(info: *FramebufferInfo, new_framebuffer: Framebuffer) bool {
        const hdr: Header = @atomicLoad(Header, &info.header, .monotonic);

        const next_active = hdr.index +% 1;
        info.framebuffers[next_active] = new_framebuffer;

        @atomicStore(Header, &info.header, .{
            .index = next_active,
            .flags = .{ .new_data = true },
        }, .release);

        return hdr.flags.new_data;
    }

    comptime {
        if (builtin.cpu.arch.isArm()) {
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

        address: [*]align(16) const u32,
        byte_size: usize,
        update_gas_results: UpdateGasResults,
        _unused0: [3]u32 = @splat(0),
        flush: Flush,
    };

    pub const MemoryFill = extern struct {
        pub const Unit = struct {
            pub const Value = union(pica.DisplayController.Framebuffer.Pixel.Size) {
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

        pub const Control = packed struct(u16) {
            pub const none: Control = .{ .busy = false, .width = .@"16" };

            busy: bool,
            finished: bool = false,
            _unused0: u6 = 0,
            width: pica.DisplayController.Framebuffer.Pixel.Size,
            _unused1: u6 = 0,

            pub fn init(size: pica.DisplayController.Framebuffer.Pixel.Size) Control {
                return .{
                    .busy = true,
                    .width = size,
                };
            }
        };

        buffers: [2]Buffer,
        controls: [2]Control,
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
            downscale: pica.PictureFormatter.Flags.Downscale = .none,
            _: u2 = 0,
        };

        source: [*]align(8) const u8,
        destination: [*]align(8) u8,
        source_dimensions: [2]u16,
        destination_dimensions: [2]u16,
        flags: pica.PictureFormatter.Flags,
        _unused0: [2]u32 = @splat(0),
    };

    pub const TextureCopy = extern struct {
        source: [*]align(8) const u8,
        destination: [*]align(8) u8,
        size: u32,
        source_line_gap: [2]u16,
        destination_line_gap: [2]u16,
        flags: pica.PictureFormatter.Flags,
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

        pub fn clear(queue: *Queue) void {
            @atomicStore(Queue.Header, &queue.header, .{
                .current_command_index = 0,
                .total_commands = 0,
                .halted = false,
                .fatal_error = false,
                .halt_processing = false,
            }, .monotonic);
        }
        pub fn pushFrontAssumeCapacity(queue: *Queue, cmd: GxCommand) void {
            const hdr = @atomicLoad(Queue.Header, &queue.header, .monotonic);
            std.debug.assert(hdr.total_commands < max_commands);

            const next_command_index: u4 = @intCast((hdr.current_command_index + hdr.total_commands) % 15);
            queue.commands[next_command_index] = cmd;

            // XXX: Workaround for https://github.com/ziglang/zig/issues/25715
            const as_u8s: *[4]u8 = @ptrCast(&queue.header);
            _ = @atomicRmw(u8, &as_u8s[@divExact(@bitOffsetOf(Queue.Header, "total_commands"), 8)], .Add, 1, .release);
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

    pub fn initProcessCommandList(command_buffer: []align(16) const u32, update_gas: ProcessCommandList.UpdateGasResults, flush: Flush, flags: Header.Flags) GxCommand {
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

    pub fn initDisplayTransfer(src: [*]align(8) const u8, dst: [*]align(8) u8, src_color: pica.ColorFormat, src_dimensions: [2]u16, dst_color: pica.ColorFormat, dst_dimensions: [2]u16, transfer_flags: DisplayTransfer.Flags, flags: Header.Flags) GxCommand {
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
                .src_format = src_color,
                .dst_format = dst_color,
                .use_32x32_tiles = transfer_flags.use_32x32,
                .downscale = transfer_flags.downscale,
                .copy = false,
            },
        } } };
    }

    pub fn initTextureCopy(src: [*]align(8) const u8, dst: [*]align(8) u8, size: u32, src_gaps: [2]u16, dst_gaps: [2]u16, flags: Header.Flags) GxCommand {
        return .{
            .header = .{
                .id = .texture_copy,
                .flags = flags,
            },
            .command = .{
                .texture_copy = .{
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
                        .src_format = .abgr8888,
                        .dst_format = .abgr8888,
                        .use_32x32_tiles = false,
                        .downscale = .none,
                        .copy = true,
                    },
                },
            },
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
    pub const empty: ScreenCapture = std.mem.zeroes(ScreenCapture);

    pub const Info = extern struct {
        left_vaddr: ?*anyopaque,
        right_vaddr: ?*anyopaque,
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

pub fn open(srv: ServiceManager) !GraphicsServerGpu {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(gsp: GraphicsServerGpu) void {
    gsp.session.close();
}

pub fn writeRegisters(gsp: GraphicsServerGpu, comptime T: type, address: *volatile T, value: T) !void {
    return try gsp.writeRegistersBuffer(address, @ptrCast(&value));
}

pub fn writeRegistersBuffer(gsp: GraphicsServerGpu, address: *volatile anyopaque, buffer: []align(1) const u32) !void {
    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 32) {
        const size = @min(buffer.len - buffer_offset, 32);

        try gsp.sendWriteHwRegs(offset + (buffer_offset * @sizeOf(u32)), buffer[buffer_offset..][0..size]);
    }
}

pub fn writeRegistersMasked(gsp: GraphicsServerGpu, comptime T: type, address: *volatile T, value: T, mask: *const [@divExact(@sizeOf(T), @sizeOf(u32))]u32) !void {
    return try gsp.writeRegistersMaskedBuffer(address, @ptrCast(&value), mask);
}

pub fn writeRegistersMaskedBuffer(gsp: GraphicsServerGpu, address: *volatile anyopaque, buffer: []align(1) const u32, mask: []align(1) const u32) !void {
    std.debug.assert(buffer.len == mask.len);

    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 32) {
        const size = @min(buffer.len - buffer_offset, 32);

        try gsp.sendWriteHwRegsWithMask(offset + (buffer_offset * @sizeOf(u32)), buffer[buffer_offset..][0..size], mask[buffer_offset..][0..size]);
    }
}

pub fn readRegisters(gsp: GraphicsServerGpu, comptime T: type, address: *volatile T) !T {
    var value: T = undefined;
    try gsp.readRegistersBuffer(address, @ptrCast(&value));
    return value;
}

pub fn readRegistersBuffer(gsp: GraphicsServerGpu, address: *volatile anyopaque, buffer: []u32) !void {
    const offset = @intFromPtr(address) - 0x1EB00000;
    var buffer_offset: usize = 0;
    while (buffer_offset < buffer.len) : (buffer_offset += 32) {
        const size = @min(buffer.len - buffer_offset, 32);

        try gsp.sendReadHwRegs(offset + (buffer_offset * @sizeOf(u32)), buffer[buffer_offset..][0..size]);
    }
}

const InterruptRelayQueueResult = struct {
    should_initialize_hardware: bool,
    thread_index: u32,
    shared_memory: MemoryBlock,
};

pub fn sendWriteHwRegs(gsp: GraphicsServerGpu, offset: usize, buffer: []align(1) const u32) !void {
    std.debug.assert(buffer.len <= 32);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.WriteHwRegs, .{ .offset = offset, .size = buffer.len * @sizeOf(u32), .data = .static(@ptrCast(buffer)) }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendWriteHwRegsWithMask(gsp: GraphicsServerGpu, offset: usize, buffer: []align(1) const u32, mask: []align(1) const u32) !void {
    std.debug.assert(buffer.len == mask.len);
    std.debug.assert(buffer.len <= 32);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.WriteHwRegsWithMask, .{ .offset = offset, .size = buffer.len * @sizeOf(u32), .data = .static(@ptrCast(buffer)), .mask = .static(@ptrCast(mask)) }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendWriteHwRegRepeat(gsp: GraphicsServerGpu, offset: usize, buffer: []align(1) const u32) !void {
    std.debug.assert(buffer.len <= 32);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.WriteHwRegRepeat, .{ .offset = offset, .size = buffer.len * @sizeOf(u32), .data = .static(@ptrCast(buffer)) }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReadHwRegs(gsp: GraphicsServerGpu, offset: usize, buffer: []u32) !void {
    std.debug.assert(buffer.len <= 32);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.ReadHwRegs, .{ .offset = offset, .size = buffer.len * @sizeOf(u32) }, .{ .buffer = buffer })).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetBufferSwap(gsp: GraphicsServerGpu, screen: Screen, info: FramebufferInfo) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetBufferSwap, .{ .screen = screen, .info = info }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendFlushDataCache(gsp: GraphicsServerGpu, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.FlushDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInvalidateDataCache(gsp: GraphicsServerGpu, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.InvalidateDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetLcdForceBlack(gsp: GraphicsServerGpu, fill: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetLcdForceBlack, .{ .fill = fill }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendTriggerCmdReqQueue(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.TriggerCmdReqQueue, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetAxiConfigQosMode(gsp: GraphicsServerGpu, qos: u32) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetAxiConfigQosMode, .{ .qos = qos }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetPerfLogMode(gsp: GraphicsServerGpu, enabled: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetPerfLogMode, .{ .enabled = enabled }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetPerfLog(gsp: GraphicsServerGpu) !PerfLogInfo {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.GetPerfLog, .{}, .{})).cases()) {
        .success => |s| s.value.info,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const RegisterInterruptRelayQueueResponse = struct {
    first_initialization: bool,
    response: command.RegisterInterruptRelayQueue.Response,
};

pub fn sendRegisterInterruptRelayQueue(gsp: GraphicsServerGpu, unknown_flags: u8, event: Event) !RegisterInterruptRelayQueueResponse {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.RegisterInterruptRelayQueue, .{ .flags = unknown_flags, .ev = event }, .{})).cases()) {
        .success => |s| .{
            .first_initialization = s.code.description == @as(horizon.result.Description, @enumFromInt(0x207)),
            .response = s.value,
        },
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterInterruptRelayQueue(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.UnregisterInterruptRelayQueue, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendTryAcquireRight(gsp: GraphicsServerGpu, init_hw: u8) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.TryAcquireRight, .{ .init_hw = init_hw, .process = .current }, .{})).cases()) {
        .success => true,
        .failure => |code| if (code == @as(horizon.ResultCode, @bitCast(@as(u32, 0xC8402BF0)))) false else horizon.unexpectedResult(code),
    };
}

pub fn sendAcquireRight(gsp: GraphicsServerGpu, init_hw: u8) !void {
    const data = tls.get();

    return switch ((try data.ipc.sendRequest(gsp.session, command.AcquireRight, .{ .init_hw = init_hw, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseRight(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.ReleaseRight, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendImportDisplayCaptureInfo(gsp: GraphicsServerGpu) !ScreenCapture {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.ImportDisplayCaptureInfo, .{}, .{})).cases()) {
        .success => |s| s.value.capture,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSaveVRAMSysArea(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SaveVRamSysArea, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRestoreVRAMSysArea(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.RestoreVRamSysArea, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendResetGpuCore(gsp: GraphicsServerGpu) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.ResetGpuCore, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetLedForceOff(gsp: GraphicsServerGpu, disable: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetLedForceOff, .{ .disable = disable }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSetInternalPriorities(gsp: GraphicsServerGpu, session_thread: u6, command_queue: u6) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.SetInternalPriorities, .{ .session_thread = session_thread, .command_queue = command_queue }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendStoreDataCache(gsp: GraphicsServerGpu, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(gsp.session, command.StoreDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const WriteHwRegs = ipc.Command(Id, .write_hw_regs, struct {
        offset: usize,
        size: usize,
        data: ipc.Static(0),
    }, struct {});
    pub const WriteHwRegsWithMask = ipc.Command(Id, .write_hw_regs_with_mask, struct {
        offset: usize,
        size: usize,
        data: ipc.Static(0),
        mask: ipc.Static(1),
    }, struct {});
    pub const WriteHwRegRepeat = ipc.Command(Id, .write_hw_reg_repeat, struct {
        offset: usize,
        size: usize,
        data: ipc.Static(0),
    }, struct {});
    pub const ReadHwRegs = ipc.Command(Id, .read_hw_regs, struct {
        pub const StaticOutput = struct { buffer: []u32 };
        offset: usize,
        size: usize,
    }, struct {
        buffer: ipc.Static(0),
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

const GraphicsServerGpu = @This();

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;

const horizon = zitrus.horizon;
const memory = horizon.memory;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Screen = pica.Screen;
const ColorFormat = pica.DisplayController.Framebuffer.Pixel;
const DmaSize = pica.DisplayController.Framebuffer.Dma;
const FramebufferFormat = pica.DisplayController.Framebuffer.Format;

const ResultCode = horizon.result.Code;
const Object = horizon.Object;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
