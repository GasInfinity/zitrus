//! Presentation Engine, a.k.a handles swapchains, presentation and their images
//! through GSP.

chain_created: std.enums.EnumArray(pica.Screen, std.atomic.Value(bool)),
chain_presents: std.enums.EnumArray(pica.Screen, std.atomic.Value(u8)),
chains: std.enums.EnumArray(pica.Screen, Swapchain),

pub fn init() PresentationEngine {
    return .{
        .chain_created = .initDefault(.init(false), .{}),
        .chain_presents = .initDefault(.init(0), .{}),
        .chains = .initUndefined(),
    };
}

pub fn initSwapchain(pe: *PresentationEngine, create_info: mango.SwapchainCreateInfo, allocator: std.mem.Allocator) !mango.Swapchain {
    _ = allocator;

    const screen: pica.Screen, const dimensions: [2]u16 = switch (create_info.surface) {
        .top_240x400 => .{ .top, .{ 240, 400 } },
        .bottom_240x320 => .{ .bottom, .{ 240, 320 } },
        .top_240x800 => .{ .top, .{ 240, 800 } },
        else => unreachable,
    };

    // TODO: Should this return an error instead?
    std.debug.assert(!pe.chain_created.getPtr(screen).load(.monotonic));
    std.debug.assert(create_info.image_array_layers == .@"1" or (create_info.image_array_layers == .@"2" and screen == .top));

    const chain = pe.chains.getPtr(screen);
    chain.* = .{
        .misc = .{
            .is_stereo = create_info.image_array_layers == .@"2",
            .present_mode = .pack(create_info.present_mode),
            .fmt = create_info.image_format.nativeColorFormat(),
            .width_minus_one = @intCast(dimensions[0] - 1),
            .height_minus_one = @intCast(dimensions[1] - 1),
            .id = 0,
        },
        .presentation = .{
            .new = switch (create_info.present_mode) {
                .fifo => .{ .fifo = .initEmpty },
                .mailbox => .{ .single = null },
            },
            .displayed = null,
        },
        .images = undefined,
        .image_count = create_info.image_count,
        .available = .initEmpty,
        .available_wake = .init(create_info.image_count),
    };

    for (0..create_info.image_count) |i| {
        const memory_info = create_info.image_memory_info[i];
        const b_memory: backend.DeviceMemory = .fromHandle(memory_info.memory);

        chain.images[i] = .{
            .memory_info = .init(b_memory, @intFromEnum(memory_info.memory_offset)),
            .info = .{
                .width_minus_one = @intCast(dimensions[0] - 1),
                .height_minus_one = @intCast(dimensions[1] - 1),
                .format = create_info.image_format,
                .optimally_tiled = false,
                .mutable_format = false,
                .cube_compatible = false,
                .layers_minus_one = @intCast(@intFromEnum(create_info.image_array_layers) - 1),
                .layer_size = dimensions[0] * @as(u22, dimensions[1]),
                .levels_minus_one = 0,
            },
        };

        chain.available.pushFrontAssumeCapacity(@intCast(i));
    }

    pe.chain_created.getPtr(screen).store(true, .release);
    return backend.Swapchain.toHandle(screen);
}

pub fn deinitSwapchain(pe: *PresentationEngine, gsp: GspGpu, gsp_owned: bool, swapchain: mango.Swapchain, allocator: std.mem.Allocator) void {
    _ = allocator;

    if (gsp_owned) gsp.sendSetLcdForceBlack(true) catch unreachable;

    const screen = backend.Swapchain.fromHandle(swapchain);
    std.debug.assert(pe.chain_created.getPtr(screen).load(.monotonic));
    std.debug.assert(pe.chain_presents.getPtr(screen).load(.monotonic) == 0);

    pe.chains.getPtr(screen).* = undefined;
    pe.chain_created.getPtr(screen).store(false, .release);
}

pub fn reacquire(pe: *PresentationEngine, gsp: GspGpu) mango.ReacquireDeviceError!void {
    for (std.enums.values(pica.Screen)) |screen| {
        if (!pe.chain_created.get(screen).load(.acquire)) return;
        if (!pe.chains.get(screen).misc.contents_available) return;
    }

    gsp.sendSetLcdForceBlack(false) catch unreachable;
}

pub fn getSwapchainImages(pe: *PresentationEngine, swapchain: mango.Swapchain, images: []mango.Image) u8 {
    const screen = backend.Swapchain.fromHandle(swapchain);
    std.debug.assert(pe.chain_created.getPtr(screen).load(.monotonic));

    const chain = pe.chains.getPtr(screen);
    std.debug.assert(images.len <= chain.image_count);

    for (images, 0..) |*img, i| {
        img.* = chain.images[i].toHandle();
    }

    return chain.image_count;
}

pub fn acquireNextImage(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, swapchain: mango.Swapchain, timeout: u64) !u8 {
    const screen = backend.Swapchain.fromHandle(swapchain);
    std.debug.assert(pe.chain_created.getPtr(screen).load(.monotonic));

    const chain = pe.chains.getPtr(screen);
    return chain.acquireNextIndex(timeout, arbiter);
}

pub fn queueWork(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, gsp_framebuffers: *[2]GspGpu.FramebufferInfo, item: Queue.PresentationItem) void {
    const screen = item.misc.screen;

    std.debug.assert(pe.chain_created.getPtr(screen).load(.monotonic));
    const chain = pe.chains.getPtr(screen);
    const presents = pe.chain_presents.getPtr(screen);

    // NOTE: The swapchain present queue already handles memory order.
    _ = presents.fetchAdd(1, .monotonic);

    const slot: Swapchain.PresentSlot = .{
        .flags = .{
            .ignore_stereo = item.misc.ignore_stereo,
        },
        .index = item.index,
    };

    const is_next_present = chain.present(slot, arbiter);

    if (is_next_present) {
        // NOTE: The GSP DOES process presents at vblank but we MUST present BEFORE vblank!
        updateNextPresent(&gsp_framebuffers[@intFromEnum(screen)], screen, chain, slot);
    }
}

pub fn refresh(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, gsp: GspGpu, gsp_framebuffers: *[2]GspGpu.FramebufferInfo, screen: pica.Screen) void {
    const presents = pe.chain_presents.getPtr(screen);

    if (presents.load(.monotonic) == 0) {
        return;
    }

    _ = presents.fetchSub(1, .monotonic);

    const created = pe.chain_created.getPtr(screen).load(.acquire);
    std.debug.assert(created);

    const chain = pe.chains.getPtr(screen);
    const was_available = chain.misc.contents_available;

    // NOTE: We MUST have a present as we had a request!
    _ = chain.consumeNextPresent(arbiter) orelse unreachable;

    // This must be done as if, e.g: we're using a fifo with 3 images (triple buffering),
    // we must present the next queued present if available.
    if (chain.peekNextPresent()) |next_queued| {
        updateNextPresent(&gsp_framebuffers[@intFromEnum(screen)], screen, chain, next_queued);
    }

    if (!was_available) {
        @branchHint(.unlikely); // Yes, unlikely as it should only be hit in the first frame for each screen.

        const other_screen = screen.other();
        const other_created = pe.chain_created.get(other_screen).load(.acquire);
        const other_chain = pe.chains.getPtr(other_screen);

        if (other_created and other_chain.misc.contents_available) {
            gsp.sendSetLcdForceBlack(false) catch unreachable;
        }
    }
}

fn updateNextPresent(gsp_framebuffer: *GspGpu.FramebufferInfo, screen: pica.Screen, chain: *Swapchain, slot: Swapchain.PresentSlot) void {
    const b_image: *backend.Image = &chain.images[slot.index];
    std.debug.assert(!b_image.memory_info.isUnbound());

    // NOTE: Currently width is always 240 for any mode/screen.
    const stride = (240 * chain.misc.fmt.bytesPerPixel());
    std.debug.assert(b_image.info.width() == 240);

    const presented_stereo = chain.misc.is_stereo and !slot.flags.ignore_stereo;

    const left: [*]const u8 = b_image.memory_info.boundVirtualAddress();
    const right: [*]const u8 = if (!presented_stereo)
        left
    else
        (left + (stride * chain.misc.height()));

    // OK, GSP may tell us that the FB was dirty even when it wasn't. We don't care
    _ = gsp_framebuffer.update(.{
        .active = @enumFromInt(chain.misc.id),
        .left_vaddr = left,
        .right_vaddr = right,
        .stride = stride,
        .format = .{
            .color_format = chain.misc.fmt,
            .dma_size = .@"64",
            .interlacing_mode = if (presented_stereo) .enable else .none,

            // HACK: Hardcoded
            .alternative_pixel_output = screen == .top and !presented_stereo and chain.misc.height() != 800,
        },
        .select = chain.misc.id,
        .attribute = 0,
    });

    chain.misc.id +%= 1;
}

const Swapchain = struct {
    pub const Misc = packed struct(u32) {
        pub const PresentMode = enum(u1) {
            mailbox,
            fifo,

            pub fn pack(present_mode: mango.PresentMode) PresentMode {
                return switch (present_mode) {
                    .mailbox => .mailbox,
                    .fifo => .fifo,
                };
            }
        };

        is_stereo: bool,
        present_mode: PresentMode,
        fmt: pica.ColorFormat,
        width_minus_one: u10,
        height_minus_one: u10,
        id: u1 = 0,
        contents_available: bool = false,
        _: u5 = 0,

        pub fn width(misc: Misc) usize {
            return @as(usize, misc.width_minus_one) + 1;
        }

        pub fn height(misc: Misc) usize {
            return @as(usize, misc.height_minus_one) + 1;
        }
    };

    const PresentSlot = struct {
        pub const Flags = packed struct(u8) {
            ignore_stereo: bool,
            _: u7 = 0,
        };

        flags: Flags,
        index: u8,
    };

    pub const Presentation = struct {
        pub const State = union {
            // XXX: This doesn't need to be thread-safe, its only accessed by the driver thread!
            fifo: backend.SingleProducerSingleConsumerBoundedQueue(PresentSlot, 3),
            single: ?PresentSlot,
        };

        new: State,
        displayed: ?u8,
    };

    misc: Misc,
    images: [3]backend.Image,
    image_count: u8,
    presentation: Presentation,
    available: backend.SingleProducerSingleConsumerBoundedQueue(u8, 3),
    available_wake: std.atomic.Value(i32),

    /// Returns whether the presented slot is the next to be displayed after vblank.
    pub fn present(chain: *Swapchain, slot: PresentSlot, arbiter: horizon.AddressArbiter) bool {
        const presentation = &chain.presentation;

        return switch (chain.misc.present_mode) {
            .fifo => blk: {
                const fifo_queue = &presentation.new.fifo;
                fifo_queue.pushFrontAssumeCapacity(slot);

                break :blk fifo_queue.header.raw.len == 1;
            },
            .mailbox => blk: {
                const single = &presentation.new.single;
                defer single.* = slot;

                if (chain.presentation.new.single) |last| {
                    chain.wakePushAvailable(last.index, arbiter);
                }

                break :blk true;
            },
        };
    }

    /// Gets the next present in the queue if available.
    pub fn peekNextPresent(chain: *Swapchain) ?PresentSlot {
        const presentation = &chain.presentation;

        return switch (chain.misc.present_mode) {
            .fifo => presentation.new.fifo.peekBack(),
            .mailbox => presentation.new.single,
        };
    }

    /// Consumes the next present in the queue, updating the currently displayed index if consumed.
    pub fn consumeNextPresent(chain: *Swapchain, arbiter: horizon.AddressArbiter) ?PresentSlot {
        const presentation = &chain.presentation;

        const new = switch (chain.misc.present_mode) {
            .fifo => presentation.new.fifo.popBack(),
            .mailbox => blk: {
                defer presentation.new.single = null;
                break :blk presentation.new.single;
            },
        } orelse return null;

        defer {
            if (presentation.displayed) |displayed| {
                chain.wakePushAvailable(displayed, arbiter);
            }

            presentation.displayed = new.index;
        }

        chain.misc.contents_available = true;
        return new;
    }

    /// Can only be called by driver code.
    pub fn wakePushAvailable(chain: *Swapchain, index: u8, arbiter: horizon.AddressArbiter) void {
        chain.available.pushFrontAssumeCapacity(index);

        if (chain.available_wake.fetchAdd(1, .monotonic) == 0) arbiter.arbitrate(&chain.available_wake.raw, .{ .signal = 1 }) catch unreachable;
    }

    fn tryAcquireNextIndex(chain: *Swapchain) ?u8 {
        const maybe_next = chain.available.popBack();

        if (maybe_next) |next| {
            _ = chain.available_wake.fetchSub(1, .monotonic);
            return next;
        }

        return null;
    }

    /// Can only be called by client code, the driver NEVER acquires indices.
    ///
    /// Externally synchronized
    pub fn acquireNextIndex(chain: *Swapchain, timeout: u64, arbiter: horizon.AddressArbiter) !u8 {
        const h_timeout: horizon.Timeout = if (timeout > std.math.maxInt(u63)) .none else .fromNanoseconds(@intCast(timeout));

        while (true) {
            if (chain.tryAcquireNextIndex()) |idx| return idx;

            // Either:
            //   1 - The driver pushes a new index and this doesn't wait
            //   2 - We wait and we're signaled, we'll get the new index in the next iteration.
            //   3 - We wait and we get a Timeout, in that case we have to check again if we have an index available (we may get a Timeout before waking up)
            arbiter.waitTimeout(i32, &chain.available_wake.raw, 1, h_timeout) catch {
                // XXX: Azahar does not have the same behavior as ofw, this somehow becomes a timeout even if timeout == -1. Worked around directly in AddressArbiter
                // Try to acquire again before erroring if somehow we got a Timeout before the driver called wake.
                return if (chain.tryAcquireNextIndex()) |idx| idx else error.Timeout;
            };
        }
    }
};

const testing = std.testing;

const PresentationEngine = @This();
const Queue = backend.Queue;

const backend = @import("../../backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
const GspGpu = horizon.services.GspGpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;
