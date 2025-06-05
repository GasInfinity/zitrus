pub const Screen = enum(u1) {
    top,
    bottom,

    pub inline fn width(_: Screen) usize {
        return 240;
    }

    pub inline fn height(screen: Screen) usize {
        return switch (screen) {
            .top => 400,
            .bottom => 320,
        };
    }
};

pub const Dimensions = packed struct(u32) { x: u16, y: u16 };

pub const ColorFormat = enum(u3) {
    pub const Abgr8 = extern struct { a: u8, b: u8, g: u8, r: u8 };
    pub const Bgr8 = extern struct { b: u8, g: u8, r: u8 };
    pub const Bgr565 = packed struct(u16) { b: u5, g: u6, r: u5 };
    pub const A1Bgr5 = packed struct(u16) { a: u1, b: u5, g: u5, r: u5 };
    pub const ABgr4 = packed struct(u16) { a: u4, b: u4, g: u4, r: u4 };

    abgr8,
    bgr8,
    bgr565,
    a1_bgr5,
    abgr4,

    pub inline fn PixelType(comptime format: ColorFormat) type {
        return switch (format) {
            .abgr8 => Abgr8,
            .bgr8 => Bgr8,
            .bgr565 => Bgr565,
            .a1_bgr5 => A1Bgr5,
            .abgr4 => ABgr4,
        };
    }

    pub inline fn bytesPerPixel(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @sizeOf(f.PixelType()),
        };
    }

    pub inline fn components(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @typeInfo(f.PixelType()).@"struct".fields.len,
        };
    }
};

pub const FramebufferInterlacingMode = enum(u2) {
    none,
    scanline_doubling,
    enable,
    enable_inverted,
};

pub const DmaSize = enum(u2) {
    @"32",
    @"64",
    @"128",
    vram,
};

pub const TopFramebufferMode = enum {
    @"2d",
    @"3d",
    full_resolution,
};

pub const FramebufferFormat = packed struct(u32) {
    color_format: ColorFormat,
    interlacing_mode: FramebufferInterlacingMode,
    alternative_pixel_output: bool,
    unknown0: u1 = 0,
    dma_size: DmaSize,
    unknown1: u7 = 0,
    unknown2: u16 = 0,

    pub inline fn mode(format: FramebufferFormat) TopFramebufferMode {
        return switch (format.interlacing_mode) {
            .enable => .@"3d",
            else => if (format.alternative_pixel_output) .@"2d" else .full_resolution,
        };
    }
};

pub const DmaTransferData = extern struct {
    pub const Scaling = enum(u2) { none, @"2x1", @"2x2" };

    pub const Flags = packed struct(u32) {
        flip_vertically: bool = false,
        align_width: bool = false,
        texture_copy: bool = false,
        _reserved0: u1 = 0,
        input_color_format: ColorFormat,
        _reserved1: u1 = 0,
        output_color_format: ColorFormat,
        _reserved2: u1 = 0,
        use_large_tiling: bool = false,
        _reserved3: u6 = 0,
        box_scale_down: Scaling = .none,
        _reserved: u6 = 0,
    };

    input_physical_address: u32,
    output_physical_address: u32,
    output: Dimensions,
    input: Dimensions,
    flags: Flags,
};

pub const Pdc = extern struct {
    pub const Timing = extern struct {
        total: u32,
        start: u32,
        border: u32,
        front_porch: u32,
        sync: u32,
        back_porch: u32,
        border_end: u32,
        interrupt: u32,
    };

    pub const Control = packed struct(u32) {
        enable: bool,
        _unused0: u7 = 0,
        disable_hblank_irq: bool,
        disable_vblank_irq: bool,
        disable_error_irq: bool,
        _unused1: u5 = 0,
        enable_output: bool,
        _unused2: u15 = 0,
    };

    horizontal: Timing,
    _unknown0: u32 = 0,

    vertical: Timing,
    _unknown1: u32 = 0,

    disable_sync: packed struct(u32) {
        horizontal: bool,
        _unwritable0: u7 = 0,
        vertical: bool,
        _unwritable1: u23 = 0,
    },
    border_color: packed struct(u32) {
        _unused: u8 = 0,
        r: u8,
        g: u8,
        b: u8,
    },
    hcount: u32,
    vcount: u32,
    _unknown2: u32 = 0,
    pixel_dimensions: Dimensions,
    horizontal_border: Dimensions,
    vertical_border: Dimensions,
    framebuffer_a_first: usize,
    framebuffer_a_second: usize,
    framebuffer_format: FramebufferFormat,
    control: Control,
    swap: packed struct(u32) {
        next: u1,
        _unused0: u3 = 0,
        displaying: bool,
        _unused1: u3 = 0,
        reset_fifo: bool,
        _unused2: u7 = 0,
        hblank_ack: bool,
        vblank_ack: bool,
        error_ack: bool,
        _unused3: u13 = 0,
    },
    _unknown3: u32 = 0,
    color_lookup_table: packed struct(u32) {
        index: u8,
        _unused: u24 = 0,
    },
    color_lookup_table_data: packed struct(u32) {
        _unused: u8 = 0,
        r: u8,
        g: u8,
        b: u8,
    },
    _unknown4: [2]u32 = @splat(0),
    framebuffer_stride: usize,
    framebuffer_b_first: usize,
    framebuffer_b_second: usize,
    _unknown5: u32 = 0,
    _unknown6: [24]u32 = @splat(0),
};

pub const MemoryFill = extern struct {
    pub const FillWidth = enum(u2) {
        @"16",
        @"24",
        @"32",
    };

    physical_address_start: usize,
    physical_address_end: usize,
    value: u32,
    control: packed struct(u32) {
        busy: bool,
        finished: bool,
        _unused0: u6 = 0,
        fill_width: FillWidth,
        _unused1: u22 = 0,
    },
};

pub const TransferEngine = extern struct {
    pub const Flags = packed struct(u32) {
        pub const Downscale = enum(u2) { none, @"2x1", @"2x2" };

        flip_v: bool,
        tiled: bool,
        output_width_less_than_input: bool,
        texturecopy_mode: bool,
        _unwritable0: u1 = 0,
        dont_convert: bool,
        _unwritable1: u2 = 0,
        input_format: ColorFormat,
        _unwritable2: u1 = 0,
        output_format: ColorFormat,
        _unwritable3: u1 = 0,
        use_32x32_tiles: bool,
        _unwritable4: u7 = 0,
        downscale: Downscale,
        _unwritable5: u6 = 0,
    };

    input_physical_address: usize,
    output_physical_address: usize,
    output_dimensions: Dimensions,
    input_dimensions: Dimensions,
    flags: Flags,
    write_0_before_display_transfer: u32,
    control: packed struct(u32) {
        start: bool,
        _unused0: u7 = 0,
        finished: bool,
        _unused1: u23 = 0,
    },
    _unknown0: u32 = 0,
    texturecopy_data_length: usize,
    texturecopy_input_line: Dimensions,
    texturecopy_output_line: Dimensions,
};

pub const CommandList = extern struct {
    pub const Control = packed struct(u32) {
        executing: bool,
        _unused0: u31 = 0,
    };

    size: [2]usize,
    physical_address: [2]usize,
    control: [2]Control,
};

pub const Registers = struct {
    pub const Internal = extern struct {
        write_0_on_init_or_cmd: u32,
        _unknown0: [31]u32 = @splat(0),
        write_0x12345678_on_init: u32,
        _unknown1: [15]u32 = @splat(0),
        write_0xFFFFFFF0_on_init: u32,
        _unknown2: [3]u32 = @splat(0),
        write_1_on_init: u32,
        _unknown3: [515]u32 = @splat(0),
        p3d: CommandList,
        _unknown4: [194]u32 = @splat(0),
    };

    hardware_id: u32,
    clock: u32,
    _unknown0: [2]u32 = @splat(0),
    psc: [2]MemoryFill,
    vram_bank_control: packed struct(u32) {
        _unused0: u8 = 0,
        disable: u4,
        _unused1: u20 = 0,
    },
    busy: packed struct(u32) {
        _unused0: u26 = 0,
        psc0: bool,
        psc1: bool,
        _unused1: u2 = 0,
        ppf: bool,
        p3d: bool,
    },
    _unknown1: [0x6]u32 = @splat(0),
    write_0x22221200_on_init: u32,
    write_0xFF2_on_init: u32,
    _unknown2: [0x1A]u32 = @splat(0),
    backlight_control: u32,
    _unknown3: [0xCF]u32 = @splat(0),
    pdc: [2]Pdc,
    _unknown4: [0x180]u32 = @splat(0),
    dma: TransferEngine,
    _unknown5: [0xF5]u32 = @splat(0),
    internal_registers: Internal,
};

comptime {
    if (@sizeOf(Pdc) != 0x100)
        @compileError(std.fmt.comptimePrint("(@sizeOf(Pdc) == 0x{X}) and 0x{X} != 0x100!", .{ @sizeOf(Pdc), @sizeOf(Pdc) }));

    if (@sizeOf(MemoryFill) != 0x10)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryFill) == 0x{X}) and 0x{X} != 0x10!", .{ @sizeOf(MemoryFill), @sizeOf(MemoryFill) }));

    if (@sizeOf(TransferEngine) != 0x2C)
        @compileError(std.fmt.comptimePrint("(@sizeOf(TransferEngine) == 0x{X}) and 0x{X} != 0x2C!", .{ @sizeOf(TransferEngine), @sizeOf(TransferEngine) }));
}

pub const Framebuffer = @import("gpu/Framebuffer.zig");

const std = @import("std");
const zitrus = @import("zitrus");
