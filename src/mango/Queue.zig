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

    pub fn copyBuffer(queue: Handle, src_buffer: mango.Buffer, dst_buffer: mango.Buffer, regions: []const mango.BufferCopy) void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        _ = transfer;
        _ = src_buffer;
        _ = dst_buffer;
        _ = regions;
        // const gsp = device.gsp;
        //
        // const b_src_buffer: backend.Buffer = .fromHandle(src_buffer);
        // const b_dst_buffer: backend.Buffer = .fromHandle(dst_buffer);
        //
        // const b_src_virt = b_src_buffer.memory_info.virtual();
        // const b_dst_virt = b_dst_buffer.memory_info.virtual();
        //
        // for (regions) |region| {
        //     const src = b_src_virt[region.src_offset..][0..region.size];
        //     const dst = b_dst_virt[region.dst_offset..][0..region.size];
        //
        //     // TODO: Errors?
        //     gsp.submitRequestDma(src, dst, .none, .none) catch unreachable;
        //
        // }
    }

    // TODO: Provide a software callback for directly using host memory (akin to VK_EXT_host_image_copy)
    pub fn copyBufferToImage(queue: Handle, info: mango.CopyBufferToImageInfo) !void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        const b_src_buffer: *backend.Buffer = .fromHandleMutable(info.src_buffer);
        const b_dst_image: *backend.Image = .fromHandleMutable(info.dst_image);

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

        try transfer.wakePushFront(.{
            .flags = .{
                .kind = .linear_tiled,
                .src_fmt = native_fmt,
                .dst_fmt = native_fmt,
            },
            .src = src_virt.ptr,
            .dst = dst_virt.ptr,
            .size = 0, // NOTE: Only used when copying data
            .input_gap_size = .{ @intCast(b_dst_image.info.width()), @intCast(b_dst_image.info.height()) },
            .output_gap_size = .{ @intCast(b_dst_image.info.width()), @intCast(b_dst_image.info.height()) },
        }, .initSemaphoreOperation(info.wait_semaphore), .initSemaphoreOperation(info.signal_semaphore));
    }

    pub fn copyImageToBuffer(queue: Handle) void {
        const transfer: *Transfer = .fromHandleMutable(queue);
        _ = transfer;
    }

    pub fn blitImage(queue: Handle, blit_image_info: mango.BlitImageInfo) !void {
        const transfer: *Transfer = .fromHandleMutable(queue);

        const b_src_image: *backend.Image = .fromHandleMutable(blit_image_info.src_image);
        const b_dst_image: *backend.Image = .fromHandleMutable(blit_image_info.dst_image);

        const b_src_virt = b_src_image.memory_info.boundVirtualAddress();
        const b_dst_virt = b_dst_image.memory_info.boundVirtualAddress();

        const b_src_color_format = b_src_image.format.nativeColorFormat();
        const b_dst_color_format = b_dst_image.format.nativeColorFormat();

        try transfer.wakePushFront(.{
            .flags = .{
                .kind = switch (b_src_image.info.optimally_tiled) {
                    false => switch (b_dst_image.info.optimally_tiled) {
                        false => unreachable, // TODO: Linear -> Linear (is just doing a memcpy)
                        true => .linear_tiled,
                    },
                    true => switch (b_dst_image.info.optimally_tiled) {
                        false => .tiled_linear,
                        true => .tiled_tiled,
                    },
                },
                .src_fmt = b_src_color_format,
                .dst_fmt = b_dst_color_format,
            },
            .src = b_src_virt,
            .dst = b_dst_virt,
            .size = 0, // NOTE: Only used when copying data
            .input_gap_size = .{ @intCast(b_src_image.info.width()), @intCast(b_src_image.info.height()) },
            .output_gap_size = .{ @intCast(b_dst_image.info.width()), @intCast(b_dst_image.info.height()) },
        }, .initSemaphoreOperation(blit_image_info.wait_semaphore), .initSemaphoreOperation(blit_image_info.signal_semaphore));
    }

    pub fn fillBuffer(queue: Handle, dst_buffer: mango.Buffer, dst_offset: usize, data: u32) !void {
        const fill: *Fill = .fromHandleMutable(queue);
        _ = fill;
        _ = dst_buffer;
        _ = dst_offset;
        _ = data;
        // const b_dst_buffer: backend.Buffer = .fromHandle(dst_buffer);
        //
        // std.debug.assert(dst_offset <= b_dst_buffer.size);
        //
        // const b_dst_virt = b_dst_buffer.memory_info.boundVirtualAddress() + dst_offset;
        // const dst_fill_size = b_dst_buffer.size - dst_offset;
        //
        // gsp.submitMemoryFill(.{ .init(@alignCast(b_dst_virt[0..dst_fill_size]), .fill32(data)), null }, .none) catch unreachable;
        //
    }

    pub fn clearColorImage(queue: Handle, clear_color_info: mango.ClearColorInfo) !void {
        const fill: *Fill = .fromHandleMutable(queue);
        const color = clear_color_info.color;
        const b_image: *backend.Image = .fromHandleMutable(clear_color_info.image);
        const bound_virtual = b_image.memory_info.boundVirtualAddress();

        const clear_slice, const clear_value: GspGpu.GxCommand.MemoryFill.Unit.Value = switch (b_image.format) {
            .a8b8g8r8_unorm => .{
                bound_virtual[0 .. b_image.info.width() * b_image.info.height() * @sizeOf(u32)],
                .fill32(@bitCast(pica.ColorFormat.Abgr8888{
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                    .a = color[3],
                })),
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

        return fill.wakePushFront(.{
            .data = @alignCast(clear_slice),
            .value = clear_value,
        }, .initSemaphoreOperation(clear_color_info.wait_semaphore), .initSemaphoreOperation(clear_color_info.signal_semaphore));
    }

    // TODO: Depth-stencil
    pub fn clearDepthStencilImage(queue: Handle, image: mango.Image, depth: f32, stencil: u8) void {
        const fill: *Fill = .fromHandleMutable(queue);
        _ = fill;
        _ = image;
        _ = depth;
        _ = stencil;
    }

    pub fn submit(queue: Handle, submit_info: mango.SubmitInfo) !void {
        const submt: *Submit = .fromHandleMutable(queue);
        const b_cmd: *backend.CommandBuffer = .fromHandleMutable(submit_info.command_buffer);
        b_cmd.notifyPending();

        return submt.wakePushFront(.{
            .cmd_buffer = b_cmd,
        }, .initSemaphoreOperation(submit_info.wait_semaphore), .initSemaphoreOperation(submit_info.signal_semaphore));
    }
};

pub const Type = enum {
    fill,
    transfer,
    submit,
    present,
};

pub const SemaOperation = struct {
    sema: *backend.Semaphore,
    value: u64,

    pub fn initSemaphoreOperation(maybe_op: ?*const mango.SemaphoreOperation) ?SemaOperation {
        return if (maybe_op) |op| .{
            .sema = .fromHandleMutable(op.semaphore),
            .value = op.value,
        } else null;
    }
};

pub const Fill = State(.fill, struct {
    data: []align(8) u8,
    value: GspGpu.GxCommand.MemoryFill.Unit.Value,
}, backend.max_buffered_queue_commands);

pub const Transfer = State(.transfer, struct {
    pub const Flags = packed struct(u32) {
        kind: Kind,
        src_fmt: pica.ColorFormat,
        dst_fmt: pica.ColorFormat,
        _: u24 = 0,
    };

    pub const Kind = enum(u2) {
        copy,
        linear_tiled,
        tiled_linear,
        tiled_tiled,
    };

    src: [*]const u8,
    dst: [*]u8,
    size: u32,
    input_gap_size: [2]u16,
    output_gap_size: [2]u16,
    flags: Flags,
}, backend.max_buffered_queue_commands);

pub const Submit = State(.submit, struct { cmd_buffer: *backend.CommandBuffer }, backend.max_buffered_queue_commands);

pub fn State(comptime kind: Type, comptime T: type, comptime capacity: u16) type {
    return struct {
        const QueueState = @This();

        pub const Slot = struct {
            item: T,
            wait: ?SemaOperation,
            signal: ?SemaOperation,
        };

        pub const CompletionSlot = struct {
            signal: ?SemaOperation,
            item: T,
        };

        type: Type = kind,
        device: *backend.Device,
        queue: backend.SingleProducerSingleConsumerBoundedQueue(Slot, capacity),
        completion: CompletionSlot,

        pub fn init(device: *backend.Device) QueueState {
            return .{
                .device = device,
                .queue = .initEmpty,
                .completion = .{ .signal = null, .item = undefined },
            };
        }

        /// Pushes new work and wakes the driver if needed.
        ///
        /// Not thread-safe, must be called from only one thread.
        pub fn wakePushFront(state: *QueueState, item: T, wait: ?SemaOperation, signal: ?SemaOperation) !void {
            defer state.device.driverWake(kind);
            return state.queue.pushFront(.{
                .item = item,
                .wait = wait,
                .signal = signal,
            });
        }

        pub const PopResult = union(enum) { empty, wait, work: T };

        /// Tries to pop new work to do.
        pub fn workPopBack(state: *QueueState) PopResult {
            if (state.queue.peekBack()) |slot| {
                if (slot.wait) |wait| {
                    // NOTE: counterValue() is atomic
                    if (wait.sema.counterValue() < wait.value) {
                        return .wait;
                    }
                }

                _ = state.queue.popBack();

                state.completion = .{ .item = slot.item, .signal = slot.signal };

                return .{ .work = slot.item };
            } else return .empty;
        }

        /// Completes the previous operation by signaling its semaphore (if it had).
        ///
        /// returns the item of the completed operation.
        pub fn complete(state: *QueueState) !T {
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

const PresentationEngine = backend.PresentationEngine;

const std = @import("std");
const zitrus = @import("zitrus");
const zalloc = @import("zalloc");

const horizon = zitrus.horizon;
const GspGpu = horizon.services.GspGpu;

const mango = zitrus.mango;
const pica = zitrus.pica;
