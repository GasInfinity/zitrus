//! Represents an independent PICA200 unit.
//!
//! The PICA200 has 3 independent units for Memory Fills, Transfers and Submits (Command Lists)
//!
//! Each queue independently manages state for waiting and signaling, allowing for inter-queue dependencies,
//! the driver handles waiting and signaling those queue dependencies so the app is free to do anything else.
//!
//! Must not depend on anything Horizon related, that is handled by the `Device` which is environment-dependent.

pub const Handle = enum(u32) {
    null = 0,
    _,

    /// Copies the region specified onto the destination buffer.
    ///
    /// Valid Usage:
    /// - Offsets must be aligned to 8 bytes.
    pub fn copyBuffer(queue: Handle, info: mango.CopyBufferInfo) !void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        const b_src_buffer: backend.Buffer = .fromHandle(info.src_buffer);
        const b_dst_buffer: backend.Buffer = .fromHandle(info.dst_buffer);

        const src_virt = b_src_buffer.memory_info.boundVirtualAddress();
        const dst_virt = b_dst_buffer.memory_info.boundVirtualAddress();

        const src_size = b_src_buffer.sizeByAmount(info.size, info.src_offset);
        const dst_size = b_dst_buffer.sizeByAmount(info.size, info.dst_offset);
        std.debug.assert(src_size == dst_size);

        const src = src_virt[@intFromEnum(info.src_offset)..][0..src_size];
        const dst = dst_virt[@intFromEnum(info.dst_offset)..][0..dst_size];

        return transfer.wakePushFront(.{
            .flags = .{
                .kind = .copy,
                .extra = .{
                    // XXX: Yes this could fail but how can the size be higher than 2^29 really?
                    .copy = @intCast(src_size),
                },
            },
            .src = @alignCast(src.ptr),
            .dst = @alignCast(dst.ptr),
            .input_gap_size = @splat(0),
            .output_gap_size = @splat(0),
        }, .initSemaphoreOperation(info.wait_semaphore), .initSemaphoreOperation(info.signal_semaphore));
    }

    // TODO: Provide a software fallback for directly using host memory (akin to VK_EXT_host_image_copy)
    pub fn copyBufferToImage(queue: Handle, info: mango.CopyBufferToImageInfo) !void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        const b_src_buffer: *backend.Buffer = .fromHandleMutable(info.src_buffer);
        const b_dst_image: *backend.Image = .fromHandleMutable(info.dst_image);

        const src_memory: backend.DeviceMemory.BoundMemoryInfo = b_src_buffer.memory_info;
        const dst_memory: backend.DeviceMemory.BoundMemoryInfo = b_dst_image.memory_info;

        const native_fmt = b_dst_image.info.format.nativeColorFormat();
        const pixel_size = native_fmt.bytesPerPixel();

        const dst_width: usize = b_dst_image.info.width();
        const dst_height: usize = b_dst_image.info.height();

        const dst_mip_width = backend.imageLevelDimension(dst_width, @intFromEnum(info.dst_subresource.mip_level));
        const dst_mip_height = backend.imageLevelDimension(dst_height, @intFromEnum(info.dst_subresource.mip_level));

        std.debug.assert(dst_mip_width >= 64 and dst_mip_height >= 16);

        const dst_mip_offset = pixel_size * backend.imageLevelOffset(dst_width * dst_height, dst_mip_width * dst_mip_height);
        const dst_mip_size = pixel_size * dst_mip_width * dst_mip_height;

        const dst_image_full_layer_size = @as(usize, b_dst_image.info.layer_size) * pixel_size;

        const src_virt = src_memory.boundVirtualAddress();
        const dst_virt = dst_memory.boundVirtualAddress();

        const dst_blitting_layers = b_dst_image.info.layersByAmount(info.dst_subresource.layer_count, info.dst_subresource.base_array_layer);

        var src_virt_offset = src_virt + @intFromEnum(info.src_offset);
        var dst_image_layer_virt_offset = dst_virt + dst_image_full_layer_size * @intFromEnum(info.dst_subresource.base_array_layer) + dst_mip_offset;
        var i: usize = 0;

        // TODO: Add the memcpy flag again

        while (i < dst_blitting_layers) : ({
            i += 1;
            dst_image_layer_virt_offset += dst_image_full_layer_size;
            src_virt_offset += dst_mip_size;
        }) {
            // NOTE: Queue operations start and execute sequentially within a queue.
            const wait_op: SemaphoreOperation = if (i == 0) .initSemaphoreOperation(info.wait_semaphore) else .none;
            const signal_op: SemaphoreOperation = if (i == (dst_blitting_layers - 1)) .initSemaphoreOperation(info.signal_semaphore) else .none;

            try transfer.wakePushFront(.{
                .flags = .{
                    .kind = .linear_tiled,
                    .extra = .{
                        .transfer = .{
                            .src_fmt = native_fmt,
                            .dst_fmt = native_fmt,
                            .downscale = .none,
                        },
                    },
                },
                .src = @alignCast(src_virt_offset),
                .dst = @alignCast(dst_image_layer_virt_offset),
                .input_gap_size = .{ @intCast(dst_mip_width), @intCast(dst_mip_height) },
                .output_gap_size = .{ @intCast(dst_mip_width), @intCast(dst_mip_height) },
            }, wait_op, signal_op);
        }
    }

    pub fn copyImageToBuffer(queue: Handle) void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        _ = transfer;
        @panic("TODO");
    }

    pub fn copyImageToImage(queue: Handle) void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        _ = transfer;
        @panic("TODO");
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
    pub fn blitImage(queue: Handle, info: mango.BlitImageInfo) !void {
        const transfer: *Transfer = .fromHandleMutable(queue);

        const b_src_image: *backend.Image = .fromHandleMutable(info.src_image);
        const b_dst_image: *backend.Image = .fromHandleMutable(info.dst_image);

        const src_blitting_layers = b_src_image.info.layersByAmount(info.src_subresource.layer_count, info.src_subresource.base_array_layer);
        const dst_blitting_layers = b_dst_image.info.layersByAmount(info.dst_subresource.layer_count, info.dst_subresource.base_array_layer);

        std.debug.assert(src_blitting_layers == dst_blitting_layers); // Obvously, we must have matching layers to copy.

        const src_color_format, const dst_color_format = switch (b_src_image.info.format) {
            // NOTE: we can (ab)use the GPU DMA for unswizzling images of the same format.
            .d16_unorm, .g8r8_unorm, .i8a8_unorm => |f| if (b_dst_image.info.format == f) .{ .rgb565, .rgb565 } else unreachable,
            .d24_unorm => |f| if (b_dst_image.info.format == f) .{ .bgr888, .bgr888 } else unreachable,
            .d24_unorm_s8_uint => |f| if (b_dst_image.info.format == f) .{ .abgr8888, .abgr8888 } else unreachable,
            else => |fmt| .{ fmt.nativeColorFormat(), b_dst_image.info.format.nativeColorFormat() }, // it must be a valid color format if not
        };

        const src_width: usize = b_src_image.info.width();
        const src_height: usize = b_src_image.info.height();

        const src_mip_width = backend.imageLevelDimension(src_width, @intFromEnum(info.src_subresource.mip_level));
        const src_mip_height = backend.imageLevelDimension(src_height, @intFromEnum(info.src_subresource.mip_level));

        const dst_width: usize = b_dst_image.info.width();
        const dst_height: usize = b_dst_image.info.height();

        const dst_mip_width = backend.imageLevelDimension(dst_width, @intFromEnum(info.src_subresource.mip_level));
        const dst_mip_height = backend.imageLevelDimension(dst_height, @intFromEnum(info.src_subresource.mip_level));

        std.debug.assert(src_mip_width >= dst_mip_width and src_mip_height >= dst_mip_height); // Output must not be bigger than input.

        // Only allow downscale of the X or XY axes. Otherwise sizes must match (for simplicity, the hardware allows bigger inputs than outputs, does that have an use-case?).
        // TODO: Yes dummy, if you have a bigger input you're basically blitting subimages!
        const downscale: pica.PictureFormatter.Flags.Downscale = if (dst_mip_width < src_mip_width and dst_mip_height < src_mip_height) blk: {
            std.debug.assert(dst_mip_width == (src_mip_width >> 1) and dst_mip_height == (src_mip_height >> 1));
            break :blk .@"2x2";
        } else if (dst_mip_width < src_mip_width) blk: {
            std.debug.assert(dst_mip_width == (src_mip_width >> 1) and dst_mip_height == (src_mip_height >> 1));
            break :blk .@"2x1";
        } else blk: {
            @branchHint(.likely);
            std.debug.assert(src_mip_width == dst_mip_width and src_mip_height == dst_mip_height and !(b_src_image.info.optimally_tiled and b_dst_image.info.optimally_tiled));
            break :blk .none;
        };

        const kind: TransferItem.Flags.Kind = switch (b_src_image.info.optimally_tiled) {
            false => switch (b_dst_image.info.optimally_tiled) {
                false => unreachable, // NOTE: Blits are not supported between LINEAR -> LINEAR, hardware doesn't support it explicitly.
                true => .linear_tiled,
            },
            true => switch (b_dst_image.info.optimally_tiled) {
                false => .tiled_linear,
                true => .tiled_tiled,
            },
        };

        switch (kind) {
            .linear_tiled, .tiled_linear => std.debug.assert(src_width >= 64 and src_height >= 16),
            .tiled_tiled => std.debug.assert(src_width >= 64 and src_height >= 32),
            .copy => unreachable,
        }

        const src_bpp = src_color_format.bytesPerPixel();
        const dst_bpp = dst_color_format.bytesPerPixel();

        const src_image_full_layer_size: usize = @as(usize, b_src_image.info.layer_size) * src_bpp;
        const dst_image_full_layer_size: usize = @as(usize, b_dst_image.info.layer_size) * dst_bpp;

        const src_virt = b_src_image.memory_info.boundVirtualAddress();
        const dst_virt = b_dst_image.memory_info.boundVirtualAddress();

        const src_mip_offset = src_bpp * backend.imageLevelOffset(src_width * src_height, src_mip_width * src_mip_height);
        const dst_mip_offset = dst_bpp * backend.imageLevelOffset(dst_width * dst_height, dst_mip_width * dst_mip_height);

        var i: usize = 0;
        var src_image_layer_virt_offset = src_virt + src_image_full_layer_size * @intFromEnum(info.src_subresource.base_array_layer) + src_mip_offset;
        var dst_image_layer_virt_offset = dst_virt + dst_image_full_layer_size * @intFromEnum(info.dst_subresource.base_array_layer) + dst_mip_offset;

        while (i < dst_blitting_layers) : ({
            i += 1;
            src_image_layer_virt_offset += src_image_full_layer_size;
            dst_image_layer_virt_offset += dst_image_full_layer_size;
        }) {
            // NOTE: Queue operations start and execute sequentially within a queue.
            const wait_op: SemaphoreOperation = if (i == 0) .initSemaphoreOperation(info.wait_semaphore) else .none;
            const signal_op: SemaphoreOperation = if (i == (dst_blitting_layers - 1)) .initSemaphoreOperation(info.signal_semaphore) else .none;

            try transfer.wakePushFront(.{
                .flags = .{
                    .kind = kind,
                    .extra = .{
                        .transfer = .{
                            .src_fmt = src_color_format,
                            .dst_fmt = dst_color_format,
                            .downscale = downscale,
                            .use_32x32 = false,
                        },
                    },
                },
                .src = @alignCast(src_image_layer_virt_offset),
                .dst = @alignCast(dst_image_layer_virt_offset),
                .input_gap_size = .{ @intCast(src_mip_width), @intCast(src_mip_height) },
                .output_gap_size = .{ @intCast(src_mip_width), @intCast(src_mip_height) },
            }, wait_op, signal_op);
        }
    }

    pub fn fillBuffer(queue: Handle, info: mango.FillBufferInfo) !void {
        const fill: *Fill = .fromHandleMutable(queue);
        const buffer: *backend.Buffer = .fromHandleMutable(info.buffer);

        const virt = buffer.memory_info.boundVirtualAddress();
        const size = buffer.sizeByAmount(info.size, info.offset);

        const dst = virt[@intFromEnum(info.offset)..][0..size];

        try fill.wakePushFront(.{
            .data = @alignCast(dst),
            .value = switch (info.pattern_type) {
                .u16 => .fill16(@truncate(info.pattern)),
                .u24 => .fill24(@truncate(info.pattern)),
                .u32 => .fill32(info.pattern),
            },
        }, .initSemaphoreOperation(info.wait_semaphore), .initSemaphoreOperation(info.signal_semaphore));
    }

    /// Clear one color attachment image.
    pub fn clearColorImage(queue: Handle, info: mango.ClearColorInfo) !void {
        const fill: *Fill = .fromHandleMutable(queue);
        const color = info.color;
        const b_image: *backend.Image = .fromHandleMutable(info.image);

        const clear_scale: usize, const clear_value: GraphicsServerGpu.GxCommand.MemoryFill.Unit.Value = switch (b_image.info.format) {
            .a8b8g8r8_unorm => .{
                @sizeOf(u32),
                .fill32(@bitCast(pica.ColorFormat.Abgr8888{
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                    .a = color[3],
                })),
            },
            .b8g8r8_unorm => .{
                3,
                .fill24(@bitCast(pica.ColorFormat.Bgr888{
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                })),
            },
            // .a8b8g8r8_unorm =>,
            .r5g6b5_unorm_pack16, .r5g5b5a1_unorm_pack16, .r4g4b4a4_unorm_pack16, .g8r8_unorm => .{
                @sizeOf(u16),
                .fill16(switch (b_image.info.format) {
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

        const cleared_levels = b_image.info.levelsByAmount(info.subresource_range.level_count, info.subresource_range.base_mip_level);
        const cleared_layers = b_image.info.layersByAmount(info.subresource_range.layer_count, info.subresource_range.base_array_layer);

        const virt_start = b_image.memory_info.boundVirtualAddress();
        const full_layer_size = clear_scale * b_image.info.layer_size;

        // We can fully clear all the layers! This common case must be optimized!
        if (info.subresource_range.base_mip_level == .@"0" and cleared_levels == b_image.info.levels()) {
            return fill.wakePushFront(.{
                .data = @alignCast(virt_start[(full_layer_size * @intFromEnum(info.subresource_range.base_array_layer))..][0..(full_layer_size * cleared_layers)]),
                .value = clear_value,
            }, .initSemaphoreOperation(info.wait_semaphore), .initSemaphoreOperation(info.signal_semaphore));
        }

        const width: usize = b_image.info.width();
        const height: usize = b_image.info.height();

        const mip_width = backend.imageLevelDimension(width, @intFromEnum(info.subresource_range.base_mip_level));
        const mip_height = backend.imageLevelDimension(height, @intFromEnum(info.subresource_range.base_mip_level));

        const mip_offset = clear_scale * backend.imageLevelOffset(width * mip_height, mip_width * mip_height);
        const full_cleared_size = clear_scale * backend.imageLayerSize(mip_width * mip_height, cleared_levels);

        var current_virt_offset: [*]u8 = virt_start + full_layer_size * @intFromEnum(info.subresource_range.base_array_layer) + mip_offset;
        var i: usize = 0;

        while (i < cleared_layers) : ({
            current_virt_offset += full_layer_size;
            i += 1;
        }) {
            // NOTE: Queue operations start and execute sequentially within a queue.
            const wait_op: SemaphoreOperation = if (i == 0) .initSemaphoreOperation(info.wait_semaphore) else .none;
            const signal_op: SemaphoreOperation = if (i == (cleared_layers - 1)) .initSemaphoreOperation(info.signal_semaphore) else .none;

            try fill.wakePushFront(.{
                .data = @alignCast(current_virt_offset[0..full_cleared_size]),
                .value = clear_value,
            }, wait_op, signal_op);
        }
    }

    pub fn clearDepthStencilImage(queue: Handle, info: mango.ClearDepthStencilInfo) !void {
        std.debug.assert(0.0 <= info.depth and info.depth <= 1.0);

        // TODO: Subresource range
        const fill: *Fill = .fromHandleMutable(queue);
        const depth = info.depth;
        const stencil = info.stencil;

        const b_image: *backend.Image = .fromHandleMutable(info.image);
        const bound_virtual = b_image.memory_info.boundVirtualAddress();

        const clear_slice, const clear_value: GraphicsServerGpu.GxCommand.MemoryFill.Unit.Value = switch (b_image.info.format) {
            .d16_unorm => .{ bound_virtual[0..(b_image.info.size() * @sizeOf(u16))], .fill16(@intFromFloat(@trunc(depth * std.math.maxInt(u16)))) },
            .d24_unorm => .{ bound_virtual[0..(b_image.info.size() * 3)], .fill24(@intFromFloat(@trunc(depth * std.math.maxInt(u24)))) },
            .d24_unorm_s8_uint => .{ bound_virtual[0..(b_image.info.size() * @sizeOf(u32))], .fill32(@as(u32, @intFromFloat(@trunc(depth * std.math.maxInt(u24)))) | (@as(u32, stencil) << 24)) },
            else => unreachable,
        };

        return fill.wakePushFront(.{
            .data = @alignCast(clear_slice),
            .value = clear_value,
        }, .initSemaphoreOperation(info.wait_semaphore), .initSemaphoreOperation(info.signal_semaphore));
    }

    pub fn submit(queue: Handle, submit_info: mango.SubmitInfo) !void {
        const submt: *Submit = .fromHandleMutable(queue);
        const b_cmd: *backend.CommandBuffer = .fromHandleMutable(submit_info.command_buffer);
        b_cmd.notifyPending();

        return submt.wakePushFront(.{
            .cmd_buffer = b_cmd,
        }, .initSemaphoreOperation(submit_info.wait_semaphore), .initSemaphoreOperation(submit_info.signal_semaphore));
    }

    pub fn present(queue: Handle, info: mango.PresentInfo) !void {
        const prsent: *Presentation = .fromHandleMutable(queue);
        const screen = backend.Swapchain.fromHandle(info.swapchain);

        return prsent.wakePushFront(.{
            .misc = .{
                .screen = screen,
                .ignore_stereo = info.flags.ignore_stereoscopic,
            },
            .index = info.image_index,
        }, .initSemaphoreOperation(info.wait_semaphore), .none);
    }
};

pub const Type = enum {
    fill,
    transfer,
    submit,
    present,
};

pub const SemaphoreOperation = struct {
    pub const none: SemaphoreOperation = .{ .sema = null, .value = 0 };

    sema: ?*backend.Semaphore,
    value: u64,

    pub fn initSemaphoreOperation(maybe_op: ?*const mango.SemaphoreQueueOperation) SemaphoreOperation {
        return if (maybe_op) |op| .{
            .sema = .fromHandleMutable(op.semaphore),
            .value = op.value,
        } else .none;
    }
};

pub const FillItem = struct {
    data: []align(8) u8,
    value: GraphicsServerGpu.GxCommand.MemoryFill.Unit.Value,
};

pub const TransferItem = struct {
    pub const Flags = packed struct(u32) {
        pub const Kind = enum(u2) {
            copy,
            linear_tiled,
            tiled_linear,
            tiled_tiled,
        };

        kind: Kind,
        extra: packed union(u30) {
            copy: u30,
            transfer: packed struct(u30) {
                src_fmt: pica.ColorFormat,
                dst_fmt: pica.ColorFormat,
                downscale: pica.PictureFormatter.Flags.Downscale,
                use_32x32: bool = false,
                _: u21 = 0,
            },
        },
    };

    src: [*]align(8) const u8,
    dst: [*]align(8) u8,
    input_gap_size: [2]u16,
    output_gap_size: [2]u16,
    flags: Flags,
};

pub const SubmitItem = struct { cmd_buffer: *backend.CommandBuffer };

pub const PresentationItem = struct {
    pub const Misc = packed struct(u8) {
        screen: pica.Screen,
        ignore_stereo: bool,
        _: u6 = 0,
    };

    misc: Misc,
    index: u8,
};

pub const Status = enum(i32) {
    /// The queue has submitted work and is waiting for the GPU
    working = -2,
    /// The GPU notified us, it'll either continue working,
    /// waiting or stay idle.
    work_completed = -1,
    /// The queue is waiting for another queue to signal its semaphore
    waiting = 0,
    /// The queue doesn't have any outstanding operation
    idle = 1,
    /// The queue was lost, this is all or nothing. If a queue is lost, ALL queues are lost.
    ///
    /// Can happen when the driver loses the GPU (i.e it hangs)
    /// The only thing you can do after this happens is destroying and recreating the device as `mango` will
    /// try to reset the GPU to a known state; if that fails you're cooked.
    lost = 2,
};

pub const Fill = State(.fill, FillItem, backend.max_buffered_queue_items);
pub const Transfer = State(.transfer, TransferItem, backend.max_buffered_queue_items);
pub const Submit = State(.submit, SubmitItem, backend.max_buffered_queue_items);
pub const Presentation = backend.Queue.State(.present, PresentationItem, backend.max_present_queue_items);

pub fn State(comptime kind: Type, comptime T: type, comptime capacity: u16) type {
    return struct {
        const QueueState = @This();

        pub const Slot = struct {
            item: T,
            wait: SemaphoreOperation,
            signal: SemaphoreOperation,
        };

        type: Type = kind,
        device: *backend.Device,
        queue: backend.SingleProducerSingleConsumerBoundedQueue(Slot, capacity),

        pub fn init(device: *backend.Device) QueueState {
            return .{
                .device = device,
                .queue = .init_empty,
            };
        }

        /// Pushes new work and wakes the driver if needed.
        ///
        /// Not thread-safe, must be called from only one thread.
        pub fn wakePushFront(state: *QueueState, item: T, wait: SemaphoreOperation, signal: SemaphoreOperation) !void {
            defer state.device.wakeIdleQueue(kind);

            return state.queue.pushFront(.{
                .item = item,
                .wait = wait,
                .signal = signal,
            });
        }

        pub const PopResult = union(enum) {
            pub const Value = struct {
                value: T,
                signal: SemaphoreOperation,
            };

            empty,
            wait,
            work: Value,
        };

        /// Tries to pop new work to do.
        pub fn workPopBack(state: *QueueState) PopResult {
            if (state.queue.peekBack()) |slot| {
                if (slot.wait.sema) |sema| {
                    // NOTE: counterValue() is atomic
                    if (sema.counterValue() < slot.wait.value) {
                        return .wait;
                    }
                }

                _ = state.queue.popBack() orelse unreachable;

                return .{ .work = .{ .value = slot.item, .signal = slot.signal } };
            } else return .empty;
        }

        /// Completes the previous operation by signaling its semaphore (if it had).
        ///
        /// returns the item of the completed operation.
        pub fn complete(state: *QueueState) !T {
            defer state.completion = undefined;

            if (state.completion.signal) |sig_completion| {
                try state.device.signalSemaphore(.{
                    .semaphore = sig_completion.sema.toHandle(),
                    .value = sig_completion.value,
                });
            }

            return state.completion.item;
        }

        pub fn toHandle(state: *QueueState) Handle {
            return @enumFromInt(@intFromPtr(&state.type));
        }

        pub fn fromHandleMutable(handle: Handle) *QueueState {
            const handle_kind: *Type = @ptrFromInt(@intFromEnum(handle));
            std.debug.assert(handle_kind.* == kind);

            return @alignCast(@fieldParentPtr("type", handle_kind));
        }
    };
}

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;
