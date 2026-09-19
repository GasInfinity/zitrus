//! Presentation Engine, a.k.a handles swapchains, presentation and their images
//! through GSP.

fcram_base_offset: u32,
display_configured: std.enums.EnumArray(pica.Screen, std.atomic.Value(bool)),
chain_presents: std.enums.EnumArray(pica.Screen, std.atomic.Value(u8)),
displays: std.enums.EnumArray(pica.Screen, Display),

pub fn init(fcram_base_offset: u32) PresentationEngine {
    return .{
        .fcram_base_offset = fcram_base_offset,
        .display_configured = .initDefault(.init(false), .{}),
        .chain_presents = .initDefault(.init(0), .{}),
        .displays = .initUndefined(),
    };
}

pub fn configureDisplay(pe: *PresentationEngine, display: mango.Display, configure_info: *const mango.DisplayConfigureInfo) mango.ConfigureDisplayError!void {
    const screen: pica.Screen = @enumFromInt(@intFromEnum(display));
    const display_data = pe.displays.getPtr(screen);

    std.debug.assert(!pe.display_configured.getPtr(screen).load(.monotonic));

    if (configure_info.image_count == 0 or @intFromEnum(configure_info.image_array_layers) == 0) return error.ValidationFailed;
    if (configure_info.image_count > 3) return error.Unsupported;
    if (configure_info.extent.width != 240) return error.Unsupported;

    switch (display) {
        .top => {
            if (configure_info.extent.height == 400 and @intFromEnum(configure_info.image_array_layers) > 2) return error.Unsupported;
            if (configure_info.extent.height == 800 and @intFromEnum(configure_info.image_array_layers) > 1) return error.Unsupported;
            if (configure_info.extent.height != 400 and configure_info.extent.height != 800) return error.Unsupported;
        },
        .bottom => if (configure_info.extent.height != 320 or @intFromEnum(configure_info.image_array_layers) > 1)
            return error.Unsupported,
    }

    display_data.* = .{
        .misc = .{
            .is_stereo = configure_info.image_array_layers == .@"2",
            .present_mode = .pack(configure_info.present_mode),
            .fmt = configure_info.image_format.nativeColorFormat(),
            .width_minus_one = @intCast(configure_info.extent.width - 1),
            .height_minus_one = @intCast(configure_info.extent.height - 1),
            .id = 0,
        },
        .presentation = .{
            .new = switch (configure_info.present_mode) {
                .fifo => .{ .fifo = .init_empty },
                .mailbox => .{ .single = null },
            },
            .displayed = null,
        },
        .images = undefined,
        .image_virt = undefined,
        .image_count = configure_info.image_count,
        .available = .init_empty,
        .available_wake = .init(configure_info.image_count),
    };

    for (0..configure_info.image_count) |i| {
        const memory_info = configure_info.image_memory[i];

        display_data.images[i] = .{
            .address = memory_info.address,
            .info = .{
                .width_minus_one = @intCast(configure_info.extent.width - 1),
                .height_minus_one = @intCast(configure_info.extent.height - 1),
                .format = configure_info.image_format,
                .optimally_tiled = false,
                .mutable_format = false,
                .cube_compatible = false,
                .layers_minus_one = @intCast(@intFromEnum(configure_info.image_array_layers) - 1),
                .layer_size = configure_info.extent.width * @as(u22, configure_info.extent.height),
                .levels_minus_one = 0,
            },
        };

        // Panic? The pointer 100% didn't come from `hostToDevice`!;
        display_data.image_virt[i] = horizon.memory.toVirtual(@intFromEnum(memory_info.address), pe.fcram_base_offset).?;
        display_data.available.pushFrontAssumeCapacity(@intCast(i));
    }

    pe.display_configured.getPtr(screen).store(true, .monotonic);
}

pub fn resetDisplay(pe: *PresentationEngine, gsp: Gpu, gsp_owned: bool, display: mango.Display) void {
    const screen: pica.Screen = @enumFromInt(@intFromEnum(display));

    if (!pe.display_configured.getPtr(screen).load(.monotonic)) return;

    std.debug.assert(pe.chain_presents.getPtr(screen).load(.monotonic) == 0);
    const other_configured = pe.display_configured.getPtr(screen.other()).load(.monotonic);
    if (other_configured and gsp_owned) gsp.sendSetLcdForceBlack(true) catch unreachable;

    pe.displays.getPtr(screen).* = undefined;
    pe.display_configured.getPtr(screen).store(false, .release);
}

pub fn reacquire(pe: *PresentationEngine, gsp: Gpu) mango.ReacquireDeviceError!void {
    for (std.enums.values(pica.Screen)) |screen| {
        if (!pe.display_configured.get(screen).load(.acquire)) return;
        if (!pe.displays.get(screen).misc.contents_available) return;
    }

    gsp.sendSetLcdForceBlack(false) catch unreachable;
}

pub fn getDisplayImages(pe: *PresentationEngine, display: mango.Display, images: []mango.Image) u8 {
    const screen: pica.Screen = @enumFromInt(@intFromEnum(display));
    std.debug.assert(pe.display_configured.getPtr(screen).load(.monotonic));

    const chain = pe.displays.getPtr(screen);
    std.debug.assert(images.len <= chain.image_count);

    for (images, 0..) |*img, i| {
        img.* = chain.images[i].toHandle();
    }

    return chain.image_count;
}

pub fn acquireNextImage(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, display: mango.Display, timeout: u64) !u8 {
    const screen: pica.Screen = @enumFromInt(@intFromEnum(display));
    std.debug.assert(pe.display_configured.getPtr(screen).load(.monotonic));

    const display_data = pe.displays.getPtr(screen);
    return display_data.acquireNextIndex(timeout, arbiter);
}

pub fn present(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, gsp_framebuffers: *[2]Gpu.FramebufferInfo, item: Queue.Presentation) void {
    const screen = item.misc.screen;

    std.debug.assert(pe.display_configured.getPtr(screen).load(.monotonic));
    const chain = pe.displays.getPtr(screen);
    const presents = pe.chain_presents.getPtr(screen);

    if (chain.presentation.displayed) |d| std.debug.assert(d != item.index); // We'll never give you an index which is currently being displayed

    const slot: Display.PresentSlot = .{
        .flags = .{
            .ignore_stereo = item.misc.ignore_stereo,
        },
        .index = item.index,
    };

    const is_next_present = chain.present(presents, slot, arbiter);

    if (is_next_present) {
        // NOTE: The GSP DOES process presents at vblank but we MUST present BEFORE vblank!
        updateNextPresent(&gsp_framebuffers[@intFromEnum(screen)], screen, chain, slot);
    }
}

pub fn refresh(pe: *PresentationEngine, arbiter: horizon.AddressArbiter, gsp: Gpu, gsp_framebuffers: *[2]Gpu.FramebufferInfo, screen: pica.Screen) void {
    const presents = pe.chain_presents.getPtr(screen);

    if (presents.load(.monotonic) == 0) {
        return;
    }

    _ = presents.fetchSub(1, .monotonic);

    const created = pe.display_configured.getPtr(screen).load(.acquire);
    std.debug.assert(created);

    const chain = pe.displays.getPtr(screen);
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
        const other_created = pe.display_configured.get(other_screen).load(.acquire);
        const other_chain = pe.displays.getPtr(other_screen);

        if (other_created and other_chain.misc.contents_available) {
            gsp.sendSetLcdForceBlack(false) catch unreachable;
        }
    }
}

fn updateNextPresent(gsp_framebuffer: *Gpu.FramebufferInfo, screen: pica.Screen, chain: *Display, slot: Display.PresentSlot) void {
    const b_image: *backend.Image = &chain.images[slot.index];
    const b_image_virt = chain.image_virt[slot.index];
    std.debug.assert(b_image.address != .zero);

    // NOTE: Currently width is always 240 for any mode/screen.
    const stride = (240 * chain.misc.fmt.bytesPerPixel());
    std.debug.assert(b_image.info.width() == 240);

    const presented_stereo = chain.misc.is_stereo and !slot.flags.ignore_stereo;

    const left: [*]const u8 = b_image_virt;
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
            .pixel_format = chain.misc.fmt,
            .dma_size = .@"64",
            .interlacing = if (presented_stereo) .enable else .none,

            // HACK: Hardcoded
            .half_rate = screen == .top and !presented_stereo and chain.misc.height() != 800,
        },
        .select = chain.misc.id,
        .attribute = 0,
    });

    chain.misc.id +%= 1;
}

const Display = struct {
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
    image_virt: [3][*]const u8,
    image_count: u8,
    presentation: Presentation,
    available: backend.SingleProducerSingleConsumerBoundedQueue(u8, 3),
    available_wake: std.atomic.Value(i32),

    /// Returns whether the presented slot is the next to be displayed after vblank.
    pub fn present(chain: *Display, presents: *std.atomic.Value(u8), slot: PresentSlot, arbiter: horizon.AddressArbiter) bool {
        const presentation = &chain.presentation;

        return switch (chain.misc.present_mode) {
            .fifo => blk: {
                std.debug.assert(presents.fetchAdd(1, .monotonic) < chain.image_count);

                const fifo_queue = &presentation.new.fifo;
                fifo_queue.pushFrontAssumeCapacity(slot);

                break :blk fifo_queue.header.raw.len == 1;
            },
            .mailbox => blk: {
                const single = &presentation.new.single;
                defer single.* = slot;

                if (chain.presentation.new.single) |last| {
                    std.debug.assert(last.index != slot.index); // Sanity
                    // We don't increment the amount of presents as we're making available again the last one (i.e a swap basically)
                    std.debug.assert(presents.load(.monotonic) > 0); // Sanity, if we're here we have a present already

                    chain.wakePushAvailable(last.index, arbiter);
                } else std.debug.assert(presents.fetchAdd(1, .monotonic) == 0); // Same logic as above applies here

                break :blk true;
            },
        };
    }

    /// Gets the next present in the queue if available.
    pub fn peekNextPresent(chain: *Display) ?PresentSlot {
        const presentation = &chain.presentation;

        return switch (chain.misc.present_mode) {
            .fifo => presentation.new.fifo.peekBack(),
            .mailbox => presentation.new.single,
        };
    }

    /// Consumes the next present in the queue, updating the currently displayed index if consumed.
    pub fn consumeNextPresent(chain: *Display, arbiter: horizon.AddressArbiter) ?PresentSlot {
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
    pub fn wakePushAvailable(chain: *Display, index: u8, arbiter: horizon.AddressArbiter) void {
        chain.available.pushFrontAssumeCapacity(index);

        if (chain.available_wake.fetchAdd(1, .monotonic) == 0) arbiter.arbitrate(&chain.available_wake.raw, .{ .signal = 1 }) catch unreachable;
    }

    fn tryAcquireNextIndex(chain: *Display) ?u8 {
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
    pub fn acquireNextIndex(chain: *Display, timeout: u64, arbiter: horizon.AddressArbiter) !u8 {
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
const Gpu = horizon.services.gsp.Gpu;

const mango = zitrus.mango;
const pica = zitrus.hardware.pica;
