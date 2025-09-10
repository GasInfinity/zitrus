pub const Framebuffer = @import("Graphics/Framebuffer.zig");

thread_index: u32,
interrupt_event: Event,
shared_memory_block: MemoryBlock,
shared_memory: *align(horizon.heap.page_size) GspGpu.Shared,

pub fn init(gsp: GspGpu) !Graphics {
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

    const shared_memory = std.mem.bytesAsValue(GspGpu.Shared, try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(@sizeOf(GspGpu.Shared), .fromByteUnits(4096)));

    try queue_result.response.gsp_memory.map(@ptrCast(shared_memory), .rw, .dont_care);

    return .{
        .thread_index = thread_index,
        .interrupt_event = interrupt_event,
        .shared_memory_block = shared_memory_block,
        .shared_memory = shared_memory,
    };
}

pub fn deinit(gfx: *Graphics, gsp: GspGpu) void {
    gfx.shared_memory_block.unmap(@ptrCast(@alignCast(gfx.shared_memory)));
    // TODO: change this when we find a solution to shared memory
    horizon.heap.non_thread_safe_shared_memory_address_allocator.free(std.mem.asBytes(gfx.shared_memory));

    gfx.shared_memory_block.close();

    gsp.sendUnregisterInterruptRelayQueue() catch unreachable;
    gsp.sendReleaseRight() catch unreachable;

    gfx.interrupt_event.close();
    gfx.* = undefined;
}

pub fn waitInterrupts(gfx: *Graphics) !GspGpu.Interrupt.Set {
    return (try gfx.waitInterruptsTimeout(-1)).?;
}

pub fn pollInterrupts(gfx: *Graphics) !?GspGpu.Interrupt.Set {
    return try gfx.waitInterruptsTimeout(0);
}

pub fn waitInterruptsTimeout(gfx: *Graphics, timeout_ns: i64) !?GspGpu.Interrupt.Set {
    const int_ev = gfx.interrupt_event;

    int_ev.wait(timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    };

    return gfx.shared_memory.interrupt_queue[gfx.thread_index].popBackAll();
}

pub fn initializeHardware(gsp: GspGpu) !void {
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
        .dma_size = .@"128",
        ._unknown1 = 1,
        ._unknown2 = 1,
        ._unknown3 = 8,
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
        .dma_size = .@"128",
        ._unknown1 = 1,
        ._unknown2 = 1,
        ._unknown3 = 8,
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

const Graphics = @This();
const GspGpu = horizon.services.GspGpu;

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
