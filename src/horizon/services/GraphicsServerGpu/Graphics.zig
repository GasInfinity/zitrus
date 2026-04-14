//! Mid-level abstraction around GSP state, useful for prototypes,
//! when using raw framebuffers or to see how things should be done.
//!
//! Use `mango` for more complex programs if needed.

pub const Software = @import("Graphics/Software.zig");
pub const Framebuffer = @import("Graphics/Framebuffer.zig");

thread_index: u32,
interrupt_event: Event,
shared_memory_block: MemoryBlock,
shared_memory: *align(horizon.heap.page_size) GraphicsServerGpu.Shared,
gsp_owned: bool,

pub fn init(gsp: GraphicsServerGpu) !Graphics {
    try gsp.sendAcquireRight(0x0);

    const interrupt_event = try Event.create(.oneshot);
    errdefer interrupt_event.close();

    // XXX: What does this flag mean?
    const queue_result = try gsp.sendRegisterInterruptRelayQueue(0x1, interrupt_event);
    errdefer gsp.sendUnregisterInterruptRelayQueue() catch unreachable;

    if (queue_result.first_initialization) {
        try initializeHardware(gsp);
    }

    const thread_index = queue_result.response.thread_index;
    const shared_memory_block = queue_result.response.gsp_memory;
    errdefer shared_memory_block.close();

    const shared_memory = std.mem.bytesAsValue(GraphicsServerGpu.Shared, horizon.heap.allocShared(@sizeOf(GraphicsServerGpu.Shared)));

    try queue_result.response.gsp_memory.map(@ptrCast(shared_memory), .rw, .dont_care);

    return .{
        .thread_index = thread_index,
        .interrupt_event = interrupt_event,
        .shared_memory_block = shared_memory_block,
        .shared_memory = shared_memory,
        .gsp_owned = true,
    };
}

pub fn deinit(gfx: *Graphics, gsp: GraphicsServerGpu) void {
    gfx.shared_memory_block.unmap(@ptrCast(@alignCast(gfx.shared_memory)));
    gfx.shared_memory_block.close();

    // XXX: azahar hits an assertion failed if we try to release gpu right and we do not own it.
    gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    if (gfx.gsp_owned) gsp.sendReleaseRight() catch unreachable;

    gfx.interrupt_event.close();
    gfx.* = undefined;
}

pub fn reacquire(gfx: *Graphics, gsp: GraphicsServerGpu) !void {
    try gsp.sendAcquireRight(0x0);
    try gsp.sendRestoreVRAMSysArea();
    gfx.gsp_owned = false;
}

pub fn release(gfx: *Graphics, gsp: GraphicsServerGpu) !GraphicsServerGpu.ScreenCapture {
    try gsp.sendSaveVRAMSysArea();
    const capture = try gsp.sendImportDisplayCaptureInfo();
    try gsp.sendReleaseRight();
    gfx.gsp_owned = true;
    return capture;
}

pub fn waitInterrupts(gfx: *Graphics) !GraphicsServerGpu.Interrupt.Set {
    return (try gfx.waitInterruptsTimeout(.none)).?;
}

pub fn pollInterrupts(gfx: *Graphics) !?GraphicsServerGpu.Interrupt.Set {
    return try gfx.waitInterruptsTimeout(.fromNanoseconds(0));
}

pub fn waitInterruptsTimeout(gfx: *Graphics, timeout: horizon.Timeout) !?GraphicsServerGpu.Interrupt.Set {
    const int_ev = gfx.interrupt_event;

    int_ev.wait(timeout) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    };

    return gfx.shared_memory.interrupt_queue[gfx.thread_index].popBackAll();
}

pub fn discardInterrupts(gfx: *Graphics) void {
    gfx.shared_memory.interrupt_queue[gfx.thread_index].clear();
}

pub fn initializeHardware(gsp: GraphicsServerGpu) !void {
    const DisplayController = pica.DisplayController;
    const gpu: *volatile pica.Registers = memory.gpu_registers;

    try gsp.writeRegisters([4]u8, gpu.p3d.irq.ack[0..4], @splat(0));
    try gsp.writeRegisters([4]u8, gpu.p3d.irq.cmp[0..4], .{ 0x78, 0x56, 0x34, 0x12 });
    try gsp.writeRegisters(pica.Graphics.Interrupt.Mask, &gpu.p3d.irq.mask, .{
        .disabled_low = BitpackedArray(bool, 32).splat(true).copyWith(0, false).copyWith(1, false).copyWith(2, false).copyWith(3, false),
        .disabled_high = .splat(true),
    });
    try gsp.writeRegisters(LsbRegister(bool), &gpu.p3d.irq.autostop, .init(true));
    try gsp.writeRegisters([2]u32, &gpu.timing_control, .{ 0x22221200, 0xFF2 });
    try gsp.writeRegisters(pica.PictureFormatter.Control, &gpu.ppf.control, .{
        .start = false,
        .finished = false,
    });
    try gsp.writeRegistersMasked(pica.MemoryFill.Control, &gpu.psc[0].control, .{
        .busy = false,
        .width = .@"16",
    }, &.{0xFF});
    try gsp.writeRegistersMasked(pica.MemoryFill.Control, &gpu.psc[1].control, .{
        .busy = false,
        .width = .@"16",
    }, &.{0xFF});

    // See `DisplayController` for more info
    //
    // Values were initially taken from libctru but now are taken from GSP.
    const presets: []const DisplayController.Preset = &.{
        .@"top_240x400@60Hz",
        .@"bottom_240x320@60Hz",
    };

    for (std.enums.values(Screen), &gpu.pdc, presets) |screen, *pdc, preset| {
        // This shouldn't matter
        try gsp.writeRegisters(DisplayController.Color, &pdc.border_color, .{ .r = 0, .g = 0, .b = 0 });

        try gsp.writeRegisters(DisplayController.SynchronizationPolarity, &pdc.synchronization_polarity, .{
            .horizontal_active_high = screen == .bottom,
            .vertical_active_high = screen == .bottom,
        });

        try gsp.writeRegisters(DisplayController.Timing, &pdc.horizontal_timing, preset.horizontal_timing);
        try gsp.writeRegisters(DisplayController.Timing.Display, &pdc.horizontal_display_timing, preset.horizontal_display_timing);
        try gsp.writeRegisters(DisplayController.Timing, &pdc.vertical_timing, preset.vertical_timing);
        try gsp.writeRegisters(DisplayController.Timing.Display, &pdc.vertical_display_timing, preset.vertical_display_timing);
        try gsp.writeRegisters(DisplayController.DisplaySize, &pdc.display_size, preset.display_size);

        // NOTE: GBATEK has different value for vertical (402?)
        try gsp.writeRegisters(DisplayController.LatchingPoint, &pdc.latching_point, .{ .horizontal = 0, .vertical = 0 });

        try gsp.writeRegisters(DisplayController.Framebuffer.Format, &pdc.framebuffer.format, .{
            .pixel_format = .abgr8888,
            .interlacing = .none,
            .half_rate = screen == .top,
            .dma_size = .@"128",
            .unknown0 = 8,
        });

        try gsp.writeRegisters([2]hardware.AlignedPhysicalAddress(.@"16", .@"1"), &pdc.framebuffer.left_address, @splat(.fromAddress(zitrus.memory.vram_b_begin)));
        try gsp.writeRegisters([2]hardware.AlignedPhysicalAddress(.@"16", .@"1"), &pdc.framebuffer.right_address, @splat(.fromAddress(zitrus.memory.vram_b_begin)));
        try gsp.writeRegisters(DisplayController.Framebuffer.Select, &pdc.framebuffer.select, std.mem.zeroes(DisplayController.Framebuffer.Select));
        try gsp.writeRegisters(DisplayController.Framebuffer.Control, &pdc.framebuffer.control, .{
            .enable = true,
            .disable_horizontal_sync_irq = true,
            .disable_vertical_sync_irq = false,
            .disable_error_irq = true,
            .maybe_output_enable = true,
        });
    }
}

const Graphics = @This();
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const pica = hardware.pica;
const BitpackedArray = hardware.BitpackedArray;
const LsbRegister = hardware.LsbRegister;

const horizon = zitrus.horizon;
const memory = horizon.memory;

const Screen = pica.Screen;

const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;
