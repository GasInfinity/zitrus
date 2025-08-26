// XXX: I don't know why I started this if I cannot use it. I need synchronization primitives and -fno-single-threaded 😭
// The presentation engine will be something like this.
chains: std.enums.EnumMap(pica.Screen, Swapchain) = .init(.{}),

pub fn init() PresentationEngine {
    return .{
        .chains = .init(.{}),
    };
}

// TODO: Properly make this thread safe with Futexes or rmw's.
pub fn initSwapchain(pe: *PresentationEngine, create_info: mango.SwapchainCreateInfo, allocator: std.mem.Allocator) !mango.Swapchain {
    _ = allocator;

    const screen: pica.Screen, const dimensions: [2]u16 = switch (create_info.surface) {
        .top_240x400 => .{ .top, .{ 240, 400 } },
        .bottom_240x320 => .{ .bottom, .{ 240, 320 } },
        .top_240x800 => .{ .top, .{ 240, 800 } },
        else => unreachable,
    };

    // TODO: Should this return an error instead?
    std.debug.assert(pe.swapchains.getPtr(screen) == null);
    std.debug.assert(create_info.image_array_layers == 1 or (create_info.image_array_layers == 2 and screen == .top));

    pe.chains.putUninitialized(screen).* = .{
        .misc = .{
            .is_stereo = create_info.image_array_layers == 2,
            .present_mode = .pack(create_info.present_mode),
            .fmt = create_info,
            .width_minus_one = @intCast(dimensions[1] - 1),
            .height_minus_one = @intCast(dimensions[1] - 1),    
        },
        .presentation = .{
            .present_info = .{},
            .presented_index = 0,
            .presented_flags = .{},
        },
    };

    return backend.Swapchain.toHandle(screen);
}

pub fn deinitSwapchain(pe: *PresentationEngine, swapchain: mango.Swapchain, allocator: std.mem.Allocator) void {
    _ = allocator;

    const screen = backend.Swapchain.fromHandle(swapchain);
    std.debug.assert(pe.chains.contains(screen));
    
    pe.chains.remove(screen);
}

pub fn getSwapchainImages(pe: *PresentationEngine, swapchain: mango.Swapchain, images: []mango.Image) !void {
    const screen = backend.Swapchain.fromHandle(swapchain);
    const chain = pe.chains.getPtr(screen) orelse unreachable;
    const imgs = images orelse return chain.image_count;
    std.debug.assert(imgs.len == chain.image_count);

    for (imgs, 0..) |*img, i| {
        img.* = chain.images[i].toHandle();
    }
}

pub fn acquireNextImage(pe: *PresentationEngine, swapchain: mango.Swapchain) !u8 {
    const screen = backend.Swapchain.fromHandle(swapchain);
    const chain = pe.chains.getPtr(screen) orelse unreachable;
    
    return chain.acquireNextIndex() orelse return error.NotReady;
}

pub fn refresh(pe: PresentationEngine, gsp: *GspGpu, screen: pica.Screen) !void {
    if(pe.chains.getPtr(screen)) |swapchain| {
        const present_info = swapchain.presentation;
        const swapchain_new_presented = swapchain.acquireNextPresent() orelse return;

        const b_image: *backend.Image = &swapchain.images[swapchain_new_presented];
        std.debug.assert(!b_image.memory_info.isUnbound());

        // NOTE: Currently width is always 240 for any mode/screen.
        const stride = (240 * swapchain.misc.fmt.bytesPerPixel());
        std.debug.assert(b_image.info.width() == 240);

        const left: [*]const u8 = b_image.memory_info.boundVirtualAddress();
        const right: [*]const u8 = if(!swapchain.misc.is_stereo or present_info.presented_flags.ignore_stereoscopic)
            left
        else (left + (stride * swapchain.misc.width()));

        try gsp.writeFramebufferInfo(screen, .{
            .active = 0,
            .left_vaddr = left,
            .right_vaddr = if(present_info.last_presented_flags.ignore_stereoscopic) left else right,
            .stride = stride,
            .format = swapchain.misc.fmt,
            .select = 0,
            .attribute = 0,
        });
    }
}

pub fn present(pe: PresentationEngine, swapchains: []const mango.Swapchain, image_indices: []const u8, flags: mango.PresentInfo.Flags) void {
    for (swapchains, image_indices) |swapchain, image_index| {
        const screen = backend.Swapchain.fromHandle(swapchain);
        const swapchain_info = pe.chains.getPtr(screen) orelse unreachable;
        
        swapchain_info.present(.{
            .index = image_index,
            .flags = flags,
        });
    }
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
        width_minus_one: u10 = 0,
        height_minus_one: u10 = 0,
        _: u7 = 0,

        pub fn width(misc: Misc) usize {
            return @as(usize, misc.width_minus_one) + 1;
        }

        pub fn height(misc: Misc) usize {
            return @as(usize, misc.height_minus_one) + 1;
        }
    };

    pub const Presentation = struct {
        pub const State = union {
            fifo: Fifo(PresentSlot),
            single: ?PresentSlot,
        };

        new: State,
        current_index: u8,
    };

    misc: Misc,
    images: [3]backend.Image,
    image_count: u8,
    presentation: Presentation,
    available: Fifo(u8),

    pub fn present(chain: *Swapchain, slot: PresentSlot) void {
        switch (chain.misc.present_mode) {
            .fifo => chain.presentation.new.fifo.pushFront(slot),
            .mailbox => {
                defer chain.presentation.new.single = slot;
                
                if(chain.presentation.new.single) |last| {
                    chain.available.pushFront(last.index);
                }
            },
        }
    }

    pub fn acquireNextPresent(chain: *Swapchain) ?PresentSlot {
        const new= switch (chain.misc.present_mode) {
            .fifo => chain.presentation.new.fifo.popFront(),
            .mailbox => chain.presentation.new.single,
        } orelse return null;

        defer {
            chain.available.pushFront(chain.presentation.current_index);
            chain.presentation.current_index = new.index;
        }
        
        return new;
    }

    pub fn acquireNextIndex(chain: *Swapchain) ?u8 {
        return chain.available.popFront();
    }
};

const PresentSlot = struct {
    flags: mango.PresentInfo.Flags,
    index: u8,
};

fn Fifo(comptime T: type) type {
    return struct {
        const SmallFifo = @This();

        pub const Info = packed struct(u8) {
            head: u4 = 0,
            count: u4 = 0,
        };

        info : Info = .{},
        buffer: [2]T = @splat(undefined),

        pub fn pushFrontAssumeCapacity(fifo: *SmallFifo, value: T) void {
            if(fifo.data.head == 0) {
                fifo.data.head = fifo.indices.len;
            }

            fifo.data.head -= 1;
            fifo.buffer[fifo.data.head] = value; 
            fifo.data.count += 1;
        }

        pub fn popFront(fifo: *SmallFifo) ?T {
            if(fifo.data.count == 0) {
                return null;
            }

            defer {
                fifo.data.count -= 1;
                fifo.data.head = if(fifo.data.head >= fifo.buffer.len - 1) 0 else fifo.data.head + 1; 
            }

            return fifo.buffer[fifo.data.head];
        }
    };
}

const PresentationEngine = @This();
const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
const GspGpu = horizon.services.GspGpu;

const mango = zitrus.mango;
const pica = zitrus.pica;

const PhysicalAddress = zitrus.PhysicalAddress;
