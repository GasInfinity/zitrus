//! Definitions for all things PICA200.
//!
//! Info:
//! - LCD screens are physically rotated 90º CCW from how the devices are held (i.e: bottom is not 320x240, is 240x320)
//!
//! - NDC clipping volume:
//!     - X: [-W, W]
//!     - Y: [-W, W]
//!     - Z: [0, -W]
//!
//! - Framebuffer origin can be changed so `-1` in NDC could mean bottom-left (GL) or top-left (D3D, Metal, VK)

// Taken from / Credits:
// https://problemkaputt.de/gbatek.htm#3dsgpuinternalregisteroverview
// https://www.3dbrew.org/wiki/GPU/External_Registers
// https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const shader = @import("pica/shader.zig");
pub const cmd3d = @import("pica/cmd3d.zig");
pub const Framebuffer = @import("pica/Framebuffer.zig");

pub const F3_12 = zsflt.Float(3, 12);
pub const F7_12 = zsflt.Float(7, 12);
pub const F7_16 = zsflt.Float(7, 16);
pub const F7_23 = zsflt.Float(7, 23);

pub const U16x2 = packed struct(u32) { x: u16, y: u16 };
pub const I16x2 = packed struct(u32) { x: i16, y: i16 };

pub const F7_16x4 = extern struct {
    pub const Unpacked = struct { x: F7_16, y: F7_16, z: F7_16, w: F7_16 };

    data: [@divExact(@bitSizeOf(F7_16) * 4, @bitSizeOf(u32))]u32,

    pub fn pack(x: F7_16, y: F7_16, z: F7_16, w: F7_16) F7_16x4 {
        var vec: F7_16x4 = undefined;
        const vec_bytes = std.mem.asBytes(&vec.data);

        // TODO: 0.15 write the packed struct instead of bitcasting
        std.mem.writePackedInt(u24, vec_bytes, 0, @bitCast(x), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16), @bitCast(y), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 2, @bitCast(z), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 3, @bitCast(w), .little);
        std.mem.swap(u32, &vec.data[0], &vec.data[2]);

        return vec;
    }
};

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

pub const PixelSize = enum(u2) {
    @"16",
    @"24",
    @"32",
    _,

    pub inline fn is24(fill: PixelSize) bool {
        return switch (fill) {
            1, 3 => true,
            else => false,
        };
    }
};

pub const ColorFormat = enum(u3) {
    pub const Abgr8888 = extern struct { a: u8, b: u8, g: u8, r: u8 };
    pub const Bgr888 = extern struct { b: u8, g: u8, r: u8 };
    pub const Rgb565 = packed struct(u16) { b: u5, g: u6, r: u5 };
    pub const Rgba5551 = packed struct(u16) { a: u1, b: u5, g: u5, r: u5 };
    pub const Rgba4444 = packed struct(u16) { a: u4, b: u4, g: u4, r: u4 };

    /// 4 bytes, `A B G R`.
    abgr8888,
    /// 3 bytes, `B G R`.
    bgr888,
    /// Packed, 2 bytes, `RRRRRGGGGGGBBBBB`.
    rgb565,
    /// Packed, 2 bytes, `RRRRRGGGGGBBBBBA`.
    rgba5551,
    /// Packed, 2 bytes, `RRRRGGGGBBBBAAAA`.
    rgba4444,

    pub inline fn Pixel(comptime format: ColorFormat) type {
        return switch (format) {
            .abgr8888 => Abgr8888,
            .bgr888 => Bgr888,
            .rgb565 => Rgb565,
            .rgba5551 => Rgba5551,
            .rgba4444 => Rgba4444,
        };
    }

    pub inline fn pixelSize(format: ColorFormat) PixelSize {
        return switch (format.bytesPerPixel()) {
            2 => .@"16",
            3 => .@"24",
            4 => .@"32",
            else => unreachable,
        };
    }

    pub inline fn bytesPerPixel(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @sizeOf(f.Pixel()),
        };
    }

    pub inline fn components(format: ColorFormat) usize {
        return switch (format) {
            inline else => |f| @typeInfo(f.Pixel()).@"struct".fields.len,
        };
    }
};

/// Depth values are stored as normalized integers.
pub const DepthStencilFormat = enum(u2) {
    /// 2 bytes for depth, `0xDDDD`.
    d16,
    /// 3 bytes for depthm `0xDDDDDD`.
    d24 = 2,
    /// 3 bytes for depth and 1 byte for stencil `0xSSDDDDDD`.
    d24_s8,
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

pub const FramebufferFormat = packed struct(u32) {
    pub const Mode = enum {
        @"2d",
        @"3d",
        full_resolution,
    };

    color_format: ColorFormat,
    interlacing_mode: FramebufferInterlacingMode,
    alternative_pixel_output: bool,
    unknown0: u1 = 0,
    dma_size: DmaSize,
    unknown1: u7 = 0,
    unknown2: u16 = 0,

    pub inline fn mode(format: FramebufferFormat) Mode {
        return switch (format.interlacing_mode) {
            .enable => .@"3d",
            else => if (format.alternative_pixel_output) .@"2d" else .full_resolution,
        };
    }
};

/// The front face is always counter-clockwise and cannot be changed.
pub const CullMode = enum(u2) {
    /// No triangles are discarded.
    none,
    /// The front-facing triangles are culled where their front face is counter-clockwise.
    front_ccw,
    /// The back-facing triangles are culled where their front face is counter-clockwise.
    back_ccw,
};

pub const ScissorMode = enum(u2) {
    /// No pixels will be discarded.
    disable,
    /// The pixels outside the scissor area will be rendered.
    outside,
    /// The pixels inside the scissor area will be rendered.
    inside = 3,
};

pub const EarlyDepthCompareOperation = enum(u2) {
    ge,
    gt,
    le,
    lt,
};

pub const OutputMap = packed struct(u32) {
    pub const Semantic = enum(u5) {
        position_x,
        position_y,
        position_z,
        position_w,

        normal_quaternion_x,
        normal_quaternion_y,
        normal_quaternion_z,
        normal_quaternion_w,

        color_r,
        color_g,
        color_b,
        color_a,

        texture_coordinate_0_u,
        texture_coordinate_0_v,
        texture_coordinate_1_u,
        texture_coordinate_1_v,
        texture_coordinate_0_w,

        view_x = 0x12,
        view_y,
        view_z,

        texture_coordinate_2_u,
        texture_coordinate_2_v,

        unused = 0x1F,

        pub fn isNormalQuaternion(semantic: Semantic) bool {
            return switch (semantic) {
                .normal_quaternion_x, .normal_quaternion_y, .normal_quaternion_z, .normal_quaternion_w => true,
                else => false,
            };
        }

        pub fn isColor(semantic: Semantic) bool {
            return switch (semantic) {
                .color_r, .color_g, .color_b, .color_a => true,
                else => false,
            };
        }

        pub fn isTextureCoordinate0(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinate_0_u, .texture_coordinate_0_v => true,
                else => false,
            };
        }

        pub fn isTextureCoordinate1(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinate_1_u, .texture_coordinate_1_v => true,
                else => false,
            };
        }

        pub fn isTextureCoordinate2(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinate_2_u, .texture_coordinate_2_v => true,
                else => false,
            };
        }

        pub fn isView(semantic: Semantic) bool {
            return switch (semantic) {
                .view_x, .view_y, .view_z => true,
                else => false,
            };
        }
    };

    x: Semantic,
    _unusd0: u3 = 0,
    y: Semantic,
    _unusd1: u3 = 0,
    z: Semantic,
    _unusd2: u3 = 0,
    w: Semantic,
    _unusd3: u3 = 0,
};

pub const BlendOperation = enum(u3) {
    /// `src_factor * src + dst_factor * dst`
    add,
    /// `src_factor * src - dst_factor * dst`
    sub,
    /// `dst_factor * dst - src_factor * src`
    reverse_sub,
    /// `min(src_factor * src, dst_factor * dst)`
    min,
    /// `max(src_factor * src, dst_factor * dst)`
    max,
};

pub const BlendFactor = enum(u4) {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,
    constant_color,
    one_minus_constant_color,
    constant_alpha,
    one_minus_constant_alpha,
    src_alpha_saturate,
};

pub const LogicOperation = enum(u4) {
    clear,
    @"and",
    reverse_and,
    copy,
    set,
    copy_inverted,
    nop,
    invert,
    nand,
    @"or",
    nor,
    xor,
    equivalent,
    and_inverted,
    or_reverse,
    or_inverted,
};

pub const CompareOperation = enum(u3) {
    never,
    always,
    eq,
    neq,
    lt,
    le,
    gt,
    ge,
};

pub const StencilOperation = enum(u3) {
    /// Keep the current value.
    keep,
    /// Sets the value to `0`.
    zero,
    /// Sets the value to `reference`.
    replace,
    /// Increments the current value and clamps to the maximum representable unsigned value.
    increment,
    /// Decrements the current value and clamps to `0`.
    decrement,
    /// Bitwise-inverts the current value.
    invert,
    /// Increments the current value and clamps to `0` when the maximum value would have exceeded.
    increment_wrap,
    /// Decrements the current value and clamps to the maximum possible value when the value would go below `0`.
    decrement_wrap,
};

/// The PICA200 supports only triangle-based primitive topologies.
pub const PrimitiveTopology = enum(u2) {
    /// Specifies a series of separate triangle primitives.
    /// The number of primitives generated is `(vertexCount / 3)`
    triangle_list,
    /// Specifies a series of connected triangle primitives with consecutive triangles sharing an edge.
    /// The number of primitives generated is `max(0, vertexCount - 2)`
    triangle_strip,
    /// Specifies a series of connected triangle primitives with all triangles sharing a common vertex.
    /// The number of primitives generated is `max(0, vertexCount - 2)`
    triangle_fan,
    /// Specifies a series of triangle primitives which are to be defined by the geometry shader.
    /// The number of primitives generated depends on the shader implementation.
    geometry,
};

pub const AttributeFormat = packed struct(u4) {
    pub const Type = enum(u2) {
        i8,
        u8,
        i16,
        f32,

        pub fn byteSize(typ: Type) usize {
            return switch (typ) {
                .i8, .u8 => @sizeOf(u8),
                .i16 => @sizeOf(i16),
                .f32 => @sizeOf(f32),
            };
        }
    };

    pub const Size = enum(u2) { x, xy, xyz, xyzw };

    type: Type = .i8,
    size: Size = .x,

    pub fn byteSize(fmt: AttributeFormat) usize {
        return fmt.type.byteSize() * (@intFromEnum(fmt.size) + 1);
    }
};

pub const IndexFormat = enum(u1) {
    /// Specifies that indices are unsigned 8-bit numbers.
    u8,
    /// Specifies that indices are unsigned 16-bit numbers.
    u16,
};

pub const TextureCombinerSource = enum(u4) {
    primary_color,
    fragment_primary_color,
    fragment_secondary_color,
    texture_0,
    texture_1,
    texture_2,
    texture_3,
    previous_buffer = 0xD,
    constant,
    previous,
};

pub const TextureCombinerColorFactor = enum(u4) {
    src_color,
    one_minus_src_color,
    src_alpha,
    one_minus_src_alpha,
    src_red,
    one_minus_src_red,
    src_green = 8,
    one_minus_src_green,
    src_blue = 12,
    one_minus_src_blue,
};

pub const TextureCombinerAlphaFactor = enum(u3) {
    src_alpha,
    one_minus_src_alpha,
    src_red,
    one_minus_src_red,
    src_green,
    one_minus_src_green,
    src_blue,
    one_minus_src_blue,
};

pub const TextureCombinerOperation = enum(u4) {
    /// `src0`
    replace,
    /// `src0 * src1`
    modulate,
    /// `src0 + src1`
    add,
    /// `src0 + src1 - 0.5`
    add_signed,
    /// `src0 * src2 + src1 * (1 - src2)`
    interpolate,
    /// `src0 - src1`
    subtract,
    /// `4 * ((src0r − 0.5) * (src1r − 0.5) + (src0g − 0.5) * (src1g − 0.5) + (src0b − 0.5) * (src1b − 0.5))`
    dot3_rgb,
    /// `4 * ((src0r − 0.5) * (src1r − 0.5) + (src0g − 0.5) * (src1g − 0.5) + (src0b − 0.5) * (src1b − 0.5))`
    dot3_rgba,
    /// `src0 * src1 + src2` (?)
    multiply_add,
    /// `src0 + src1 * src2` (?)
    add_multiply,
};

pub const TextureCombinerScale = enum(u2) {
    @"1x",
    @"2x",
    @"3x",
};

pub const TextureCombinerBufferSource = enum(u1) { previous_buffer, previous };

pub const TextureCombinerFogMode = enum(u3) {
    disabled,
    fog = 5,
    gas = 7,
};

pub const TextureCombinerShadingDensity = enum(u1) {
    plain,
    depth,
};

pub const DepthMapMode = enum(u1) {
    /// Precision is evenly distributed.
    w_buffer,

    /// Precision is higher close to the near plane.
    z_buffer,
};

pub const TextureUnitFilter = enum(u1) {
    nearest,
    linear,
};

pub const TextureUnitAddressMode = enum(u3) {
    clamp_to_edge,
    clamp_to_border,
    repeat,
    mirrored_repeat,
};

pub const TextureUnitType = enum(u3) {
    @"2d",
    cube_map,
    shadow_2d,
    projection,
    shadow_cube,
    disabled,
};

pub const TextureUnitFormat = enum(u4) {
    pub const Hilo88 = extern struct { g: u8, r: u8 };
    pub const I8 = packed struct(u8) { i: u8 };
    pub const A8 = packed struct(u8) { a: u8 };
    pub const Ia88 = packed struct(u16) { i: u8, a: u8 };
    pub const I4 = packed struct(u8) { i: u8 };
    pub const A4 = packed struct(u8) { i: u8 };
    pub const Ia44 = packed struct(u8) { i: u4, a: u4 };

    abgr8888,
    bgr888,
    rgba5551,
    rgb565,
    rgba4444,
    ia88,
    hilo88,
    i8,
    a8,
    ia44,
    i4,
    a4,
    etc1,
    etc1a4,
};

pub const TextureUnitTexture2Coordinates = enum(u1) {
    @"2",
    @"1",
};

pub const TextureUnitTexture3Coordinates = enum(u2) {
    @"0",
    @"1",
    @"2",
};

// TODO: Properly finish this
pub const Registers = struct {
    pub const VRamPower = packed struct(u32) {
        _unknown0: u8,
        power_off_a_low: bool,
        power_off_a_high: bool,
        power_off_b_low: bool,
        power_off_b_high: bool,
        _unknown1: u20,
    };

    pub const InterruptFlags = packed struct(u32) {
        _unknown0: bool,
        _unknown1: bool,
        _unused0: u24 = 0,
        psc0: bool,
        psc1: bool,
        pdc0: bool,
        pdc1: bool,
        ppf: bool,
        p3d: bool,
    };

    pub const BusyFlags = packed struct(u32) {
        _unused0: u10,
        _unknown1: bool,
        _unused1: u6,
        _unknown_vram_power_0: bool,
        _unknown_vram_power_1: bool,
        memory_fill_busy: bool,
        memory_copy_busy: bool,
        _unused2: u11,
    };

    pub const TrafficStatus = extern struct {
        total_non_vram_reads: u32,
        total_non_vram_writes: u32,
        total_vram_a_reads: u32,
        total_vram_a_writes: u32,
        total_vram_b_reads: u32,
        total_vram_b_writes: u32,
        polygon_array_reads: u32,
        polygon_texture_reads: u32,
        polygon_depth_buffer_reads: u32,
        polygon_depth_buffer_writes: u32,
        polygon_color_buffer_reads: u32,
        polygon_color_buffer_writes: u32,
        lcd_upper_screen_reads: u32,
        lcd_lower_screen_reads: u32,
        memory_copy_src_reads: u32,
        memory_copy_dst_writes: u32,
        memory_fill_dst_writes: [2]u32,
        cpu_reads_from_vram_a_b: u32,
        cpu_writes_to_vram_a_b: u32,
    };

    // XXX: Proper field names and structures
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
        pixel_dimensions: U16x2,
        horizontal_border: U16x2,
        vertical_border: U16x2,
        framebuffer_a_first: u32,
        framebuffer_a_second: u32,
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
        framebuffer_stride: u32,
        framebuffer_b_first: u32,
        framebuffer_b_second: u32,
        _unknown5: u32 = 0,
        _unknown6: [24]u32 = @splat(0),
    };

    pub const MemoryFill = extern struct {
        pub const Control = packed struct(u16) {
            pub const none: Control = .{ .busy = false, .width = .@"16" };

            busy: bool,
            finished: bool = false,
            _unused0: u6 = 0,
            width: PixelSize,
            _unused1: u6 = 0,

            pub fn init(width: PixelSize) Control {
                return .{ .busy = true, .width = width };
            }
        };

        start: AlignedPhysicalAddress(.@"16", .@"8"),
        end: AlignedPhysicalAddress(.@"16", .@"8"),
        value: u32,
        control: Control,
        _padding0: u16 = 0,
    };

    pub const MemoryCopy = extern struct {
        pub const Flags = packed struct(u32) {
            pub const Downscale = enum(u2) { none, @"2x1", @"2x2" };

            flip_v: bool,
            linear_tiled: bool,
            output_width_less_than_input: bool,
            texture_copy_mode: bool,
            _unwritable0: u1 = 0,
            tiled_tiled: bool,
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

        input: AlignedPhysicalAddress(.@"16", .@"8"),
        output: AlignedPhysicalAddress(.@"16", .@"8"),
        output_dimensions: U16x2,
        input_dimensions: U16x2,
        flags: Flags,
        write_0_before_display_transfer: u32,
        control: packed struct(u32) {
            start: bool,
            _unused0: u7 = 0,
            finished: bool,
            _unused1: u23 = 0,
        },
        _unknown0: u32 = 0,
        texture_size: u32,
        texture_src_dimensions: U16x2,
        texture_dst_dimensions: U16x2,
    };

    // FIXME: Remove usages of @Vector() in packed structs!
    pub const Internal = extern struct {
        pub const Trigger = enum(u1) { trigger = 1 };

        pub fn RightPaddedRegister(comptime T: type) type {
            std.debug.assert(@bitSizeOf(T) < @bitSizeOf(u32));

            return packed struct(u32) {
                const Rpr = @This();

                value: T,
                _: std.meta.Int(.unsigned, @bitSizeOf(u32) - @bitSizeOf(T)) = 0,

                pub fn init(value: T) Rpr {
                    return .{ .value = value };
                }
            };
        }

        pub fn LeftPaddedRegister(comptime T: type) type {
            std.debug.assert(@bitSizeOf(T) < @bitSizeOf(u32));

            return packed struct(u32) {
                const Lpr = @This();

                _: std.meta.Int(.unsigned, @bitSizeOf(u32) - @bitSizeOf(T)) = 0,
                value: T,

                pub fn init(value: T) Lpr {
                    return .{ .value = value };
                }
            };
        }

        pub const AttributeIndex = enum(u4) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };
        pub const ArrayComponentIndex = enum(u4) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };

        pub const Interrupt = extern struct {
            pub const Mask = packed struct(u64) { disabled: @Vector(64, bool) };
            pub const Stat = packed struct(u64) { match: @Vector(64, bool) };
            pub const AutoStop = packed struct(u32) {
                stop_command_list: bool,
                _unused0: u31 = 0,
            };

            ack: [64]u8,
            req: [64]u8,
            cmp: [64]u8,
            mask: Mask align(@alignOf(u32)),
            stat: Stat align(@alignOf(u32)),
            autostop: AutoStop,
            fixed_0x00010002: u32,
        };

        pub const Rasterizer = extern struct {
            pub const OutputAttributeMode = packed struct(u32) {
                use_texture_coordinates: bool = false,
                _: u31 = 0,
            };

            pub const OutputAttributeClock = packed struct(u32) {
                position_z_present: bool = false,
                color_present: bool = false,
                _unused0: u6 = 0,
                texture_coordinates_0_present: bool = false,
                texture_coordinates_1_present: bool = false,
                texture_coordinates_2_present: bool = false,
                _unknown0: u4 = 0,
                texture_coordinates_0_w_present: bool = false,
                _unknown1: u1 = 0,
                _unused1: u6 = 0,
                normal_quaternion_or_view_present: bool = false,
                _unused2: u8 = 0,
            };

            faceculling_config: RightPaddedRegister(CullMode),
            viewport_h_scale: RightPaddedRegister(F7_16),
            viewport_h_step: LeftPaddedRegister(F7_23),
            viewport_v_scale: RightPaddedRegister(F7_16),
            viewport_v_step: LeftPaddedRegister(F7_23),
            _unknown0: u32,
            _unknown1: u32,
            fragment_operation_clip: RightPaddedRegister(bool),
            fragment_operation_clip_data: [4]RightPaddedRegister(F7_16),
            _unknown2: u32,
            depth_map_scale: RightPaddedRegister(F7_16),
            depth_map_offset: RightPaddedRegister(F7_16),
            shader_output_map_total: RightPaddedRegister(u3),
            shader_output_map_output: [7]OutputMap,
            _unknown3: u32,
            _unknown4: u32,
            _unknown5: u32,
            status_num_vertices_received: u32,
            status_num_triangles_received: u32,
            status_num_triangles_displayed: u32,
            _unknown6: [3]u32,
            _unknown7: u32,
            early_depth_function: packed struct(u32) { function: EarlyDepthCompareOperation, _: u30 = 0 },
            early_depth_test_enable_1: RightPaddedRegister(bool),
            early_depth_clear: RightPaddedRegister(Trigger),
            shader_output_attribute_mode: OutputAttributeMode,
            scissor_config: RightPaddedRegister(ScissorMode),
            scissor_start: U16x2,
            scissor_end: U16x2,
            viewport_xy: U16x2,
            _unknown8: u32,
            early_depth_data: u32,
            _unknown9: u32,
            _unknown10: u32,
            depth_map_mode: RightPaddedRegister(DepthMapMode),
            /// Does not seem to have an effect but it's still documented like this
            _unused_render_buffer_dimensions: u32,
            shader_output_attribute_clock: OutputAttributeClock,
        };

        pub const TextureUnits = extern struct {
            pub const Config = packed struct(u32) {
                texture_0_enabled: bool,
                texture_1_enabled: bool,
                texture_2_enabled: bool,
                _unused0: u5 = 0,
                texture_3_coordinates: TextureUnitTexture3Coordinates,
                texture_3_enabled: bool,
                _unused1: u1 = 0,
                _unused2: u1 = 1,
                texture_2_coordinates: TextureUnitTexture2Coordinates,
                _unused3: u2 = 0,
                clear_texture_cache: bool,
                _unused4: u15 = 0,
            };

            pub const TextureDimensions = packed struct(u32) {
                height: u11,
                _unused0: u5 = 0,
                width: u11 = 0,
                _unused1: u5 = 0,
            };

            pub const TextureParameters = packed struct(u32) {
                pub const Etc1Flag = enum(u2) { none, etc1 = 2 };

                _unknown0: u1 = 0,
                mag_filter: TextureUnitFilter,
                min_filter: TextureUnitFilter,
                _unknown1: u1 = 0,
                etc1: Etc1Flag,
                _unknown2: u2 = 0,
                wrap_t: TextureUnitAddressMode,
                _unknown3: u1 = 0,
                wrap_s: TextureUnitAddressMode,
                _unknown4: u5 = 0,
                is_shadow: bool,
                _unknown5: u3 = 0,
                mip_filter: TextureUnitFilter,
                _unused0: u3 = 0,
                type: TextureUnitType,
                _unused1: u1 = 0,
            };

            pub const TextureLevelOfDetail = packed struct(u32) {
                // TODO: Fixed point numbers (this is a fixed1.4.8)
                bias: u13,
                _unknown0: u3 = 0,
                max_level_of_detail: u4,
                _unknown1: u4 = 0,
                min_level_of_detail: u4,
                _unused0: u4 = 0,
            };

            pub const TextureShadow = packed struct(u32) {
                orthogonal: bool,
                z_bias: u24,
                _unknown0: u7 = 0,
            };

            pub const Main = extern struct {
                border_color: [4]u8,
                dimensions: TextureDimensions,
                parameters: TextureParameters,
                lod: TextureLevelOfDetail,
                address: [6]zitrus.AlignedPhysicalAddress(.@"8", .@"8"),
                shadow: u32,
                _unknown0: u32,
                _unknown1: u32,
                format: RightPaddedRegister(TextureUnitFormat),
            };

            pub const Sub = extern struct {
                border_color: [4]u8,
                dimensions: TextureDimensions,
                parameters: TextureParameters,
                lod: TextureLevelOfDetail,
                address: zitrus.AlignedPhysicalAddress(.@"8", .@"8"),
                format: RightPaddedRegister(TextureUnitFormat),
            };

            config: Config,
            texture_0: Main,
            lighting_enable: RightPaddedRegister(bool),
            _unknown0: u32,
            texture_1: Sub,
            _unknown1: [2]u32,
            texture_2: Sub,
        };

        pub const ProceduralTextureUnit = extern struct {
            pub const Main = extern struct {
                procedural_texture: [5]u32,
                procedural_texture_5_low: u32,
                procedural_texture_5_high: u32,
            };

            texture_3: Main,
            lut_index: u32,
            lut_data: [8]u32,
        };

        pub const TextureCombiners = extern struct {
            pub const Combiner = extern struct {
                pub const Sources = packed struct(u32) {
                    color_src_0: TextureCombinerSource,
                    color_src_1: TextureCombinerSource,
                    color_src_2: TextureCombinerSource,
                    _unused0: u4 = 0,
                    alpha_src_0: TextureCombinerSource,
                    alpha_src_1: TextureCombinerSource,
                    alpha_src_2: TextureCombinerSource,
                    _unused1: u4 = 0,
                };

                pub const Factors = packed struct(u32) {
                    color_factor_0: TextureCombinerColorFactor,
                    color_factor_1: TextureCombinerColorFactor,
                    color_factor_2: TextureCombinerColorFactor,
                    alpha_factor_0: TextureCombinerAlphaFactor,
                    alpha_factor_1: TextureCombinerAlphaFactor,
                    alpha_factor_2: TextureCombinerAlphaFactor,
                    _unused0: u11 = 0,
                };

                pub const Operations = packed struct(u32) {
                    color_op: TextureCombinerOperation,
                    _unused0: u12 = 0,
                    alpha_op: TextureCombinerOperation,
                    _unused1: u12 = 0,
                };

                pub const Scales = packed struct(u32) {
                    color_scale: TextureCombinerScale,
                    _unused0: u14 = 0,
                    alpha_scale: TextureCombinerScale,
                    _unused1: u14 = 0,
                };

                sources: Sources,
                factors: Factors,
                operations: Operations,
                color: [4]u8,
                scales: Scales,
            };

            pub const UpdateBuffer = packed struct(u32) {
                fog_mode: TextureCombinerFogMode,
                shading_density_source: TextureCombinerShadingDensity,
                _unused0: u4 = 0,
                tex_combiner_1_color_buffer_src: TextureCombinerBufferSource,
                tex_combiner_2_color_buffer_src: TextureCombinerBufferSource,
                tex_combiner_3_color_buffer_src: TextureCombinerBufferSource,
                tex_combiner_4_color_buffer_src: TextureCombinerBufferSource,
                tex_combiner_1_alpha_buffer_src: TextureCombinerBufferSource,
                tex_combiner_2_alpha_buffer_src: TextureCombinerBufferSource,
                tex_combiner_3_alpha_buffer_src: TextureCombinerBufferSource,
                tex_combiner_4_alpha_buffer_src: TextureCombinerBufferSource,
                z_flip: bool,
                _unused1: u7 = 0,
                _unknown0: u2 = 0,
                _unused2: u6 = 0,

                pub const TextureCombinerBufferIndex = enum(u3) { @"1", @"2", @"3", @"4" };

                pub fn setColorBufferSource(update_buffer: *UpdateBuffer, index: TextureCombinerBufferIndex, buffer_src: TextureCombinerBufferSource) void {
                    std.mem.writePackedIntNative(u1, std.mem.asBytes(update_buffer), @as(usize, 8) + @intFromEnum(index), @intFromEnum(buffer_src));
                }

                pub fn setAlphaBufferSource(update_buffer: *UpdateBuffer, index: TextureCombinerBufferIndex, buffer_src: TextureCombinerBufferSource) void {
                    std.mem.writePackedIntNative(u1, std.mem.asBytes(update_buffer), @as(usize, 12) + @intFromEnum(index), @intFromEnum(buffer_src));
                }
            };

            texture_combiner_0: Combiner,
            _unknown0: [3]u32,
            texture_combiner_1: Combiner,
            _unknown1: [3]u32,
            texture_combiner_2: Combiner,
            _unknown2: [3]u32,
            texture_combiner_3: Combiner,
            _unknown3: [3]u32,
            update_buffer: UpdateBuffer,
            fog_color: [4]u8,
            _unknown4: u32,
            _unknown5: u32,
            gas_attenuation: u32,
            gas_accumulation_max: u32,
            fog_lut_index: u32,
            _unknown6: u32,
            fog_lut_data: [8]u32,
            texture_combiner_4: Combiner,
            _unknown7: [3]u32,
            texture_combiner_5: Combiner,
            buffer_color: [4]u8,
        };

        pub const Framebuffer = extern struct {
            pub const ColorOperation = packed struct(u32) {
                pub const FragmentOperation = enum(u2) { default, gas, shadow = 3 };
                pub const BlendMode = enum(u1) { logic, blend };
                pub const RenderLines = enum(u1) { all, even };

                fragment_operation: FragmentOperation,
                _unused0: u6 = 0,

                mode: BlendMode,
                _unused1: u7 = 0,
                _unknown0: u8 = 0,
                render_lines: RenderLines = .all,
                render_nothing: bool = false,
                _unused2: u6 = 0,
            };

            pub const BlendConfig = packed struct(u32) {
                color_op: BlendOperation,
                _unused0: u5 = 0,
                alpha_op: BlendOperation,
                _unused1: u5 = 0,
                src_color_factor: BlendFactor,
                dst_color_factor: BlendFactor,
                src_alpha_factor: BlendFactor,
                dst_alpha_factor: BlendFactor,
            };

            pub const AlphaTestConfig = packed struct(u32) {
                enable: bool,
                _unused0: u3 = 0,
                op: CompareOperation,
                _unused1: u1 = 0,
                reference: u8,
                _unused3: u16 = 0,
            };

            pub const StencilTestConfig = packed struct(u32) {
                enable: bool,
                _unused0: u3 = 0,
                op: CompareOperation,
                _unused1: u1 = 0,
                compare_mask: u8,
                reference: u8,
                write_mask: u8,
            };

            pub const StencilOperationConfig = packed struct(u32) {
                fail_op: StencilOperation,
                _unused0: u1 = 0,
                depth_fail_op: StencilOperation,
                _unused1: u1 = 0,
                pass_op: StencilOperation,
                _unused2: u21 = 0,
            };

            pub const DepthColorMaskConfig = packed struct(u32) {
                enable_depth_test: bool,
                _unused0: u3 = 0,
                depth_op: CompareOperation,
                _unused1: u1 = 0,
                r_write_enable: bool,
                g_write_enable: bool,
                b_write_enable: bool,
                a_write_enable: bool,
                depth_write_enable: bool,
                _unused2: u19 = 0,
            };

            pub const ColorRwMask = packed struct(u32) {
                pub const disable: ColorRwMask = .{};
                pub const enable: ColorRwMask = .{ .enable_all = 0xF };

                // NOTE: really weird that it doesn't trigger separate r g b a?
                enable_all: u4 = 0,
                _unused0: u28 = 0,
            };

            pub const DepthStencilRwMask = packed struct(u32) {
                pub const disable: DepthStencilRwMask = .{};
                pub const enable: DepthStencilRwMask = .{ .depth_enable = true, .stencil_enable = true };

                stencil_enable: bool = false,
                depth_enable: bool = false,
                _unused0: u30 = 0,
            };

            pub const RenderBufferDimensions = packed struct(u32) {
                width: u11,
                _unused0: u1 = 0,
                height_end: u10,
                _unused1: u2 = 0,
                flip_vertically: bool = false,
                _unused2: u7 = 0,

                pub fn init(width: u11, height: u10, flip_vertically: bool) RenderBufferDimensions {
                    return .{ .width = width, .height_end = height - 1, .flip_vertically = flip_vertically };
                }
            };

            pub const ColorBufferFormat = packed struct(u32) {
                pixel_size: PixelSize,
                _unused0: u14 = 0,
                format: ColorFormat,
                _unused1: u13 = 0,

                pub fn init(format: ColorFormat) ColorBufferFormat {
                    return .{
                        .pixel_size = format.pixelSize(),
                        .format = format,
                    };
                }
            };

            pub const RenderBufferBlockSize = enum(u1) {
                @"8x8",
                @"32x32",
            };

            color_operation: ColorOperation,
            blend_config: BlendConfig,
            logic_operation: RightPaddedRegister(LogicOperation),
            blend_color: [4]u8,
            alpha_test: AlphaTestConfig,
            stencil_test: StencilTestConfig,
            stencil_operation: StencilOperationConfig,
            depth_color_mask: DepthColorMaskConfig,
            _unknown0: [5]u32,
            _unknown1: u32,
            _unknown2: u32,
            _unknown3: u32,
            render_buffer_invalidate: RightPaddedRegister(Trigger),
            render_buffer_flush: RightPaddedRegister(Trigger),
            color_buffer_reading: ColorRwMask,
            color_buffer_writing: ColorRwMask,
            depth_buffer_reading: DepthStencilRwMask,
            depth_buffer_writing: DepthStencilRwMask,
            depth_buffer_format: RightPaddedRegister(DepthStencilFormat),
            color_buffer_format: ColorBufferFormat,
            early_depth_test_enable_2: RightPaddedRegister(bool),
            _unknown4: u32,
            _unknown5: u32,
            render_buffer_block_size: packed struct(u32) { mode: RenderBufferBlockSize, _: u31 = 0 },
            depth_buffer_location: AlignedPhysicalAddress(.@"64", .@"8"),
            color_buffer_location: AlignedPhysicalAddress(.@"64", .@"8"),
            render_buffer_dimensions: RenderBufferDimensions,
            _unknown6: u32,
            gas_light_xy: u32,
            gas_light_z: u32,
            gas_light_z_color: u32,
            gas_lut_index: u32,
            gas_lut_data: u32,
            _unknown7: u32,
            gas_delta_z_depth: u32,
            _unknown8: [9]u32,
            fragment_operation_shadow: u32,
            _unknown9: [14]u32,
            _unknown10: u32,
        };

        pub const FragmentLighting = extern struct {
            pub const Light = extern struct {
                specular: [2]u32,
                diffuse: u32,
                ambient: u32,
                vector_low: u32,
                vector_high: u32,
                spot_direction_low: u32,
                spot_direction_high: u32,
                _unknown0: u32,
                config: u32,
                attenuation_bias: u32,
                attenuation_scale: u32,
            };

            light: [8]Light,
            _unknown0: [32]u32,
            ambient: u32,
            num_lights: u32,
            config_0: u32,
            config_1: u32,
            lut_index: u32,
            disable: RightPaddedRegister(bool),
            lut_data: [8]u32,
            lut_input_absolute: u32,
            lut_input_select: u32,
            lut_input_scale: u32,
            _unknown1: [30]u8,
            light_permutation: u32,
        };

        pub const GeometryPipeline = extern struct {
            pub const PrimitiveConfig = packed struct(u32) {
                total_vertex_outputs: u4,
                _unused0: u4 = 0,
                topology: PrimitiveTopology,
                _unused1: u6 = 0,
                _unknown0: u1 = 0,
                _unused2: u15 = 0,
            };

            pub const AttributeConfig = extern struct {
                pub const Flags = enum(u1) { array, fixed };

                pub const Low = packed struct(u32) {
                    attribute_0: AttributeFormat = .{},
                    attribute_1: AttributeFormat = .{},
                    attribute_2: AttributeFormat = .{},
                    attribute_3: AttributeFormat = .{},
                    attribute_4: AttributeFormat = .{},
                    attribute_5: AttributeFormat = .{},
                    attribute_6: AttributeFormat = .{},
                    attribute_7: AttributeFormat = .{},
                };

                pub const High = packed struct(u32) {
                    attribute_8: AttributeFormat = .{},
                    attribute_9: AttributeFormat = .{},
                    attribute_10: AttributeFormat = .{},
                    attribute_11: AttributeFormat = .{},

                    flags_0: Flags = .array,
                    flags_1: Flags = .array,
                    flags_2: Flags = .array,
                    flags_3: Flags = .array,
                    flags_4: Flags = .array,
                    flags_5: Flags = .array,
                    flags_6: Flags = .array,
                    flags_7: Flags = .array,
                    flags_8: Flags = .array,
                    flags_9: Flags = .array,
                    flags_10: Flags = .array,
                    flags_11: Flags = .array,

                    attributes_end: u4,
                };

                low: Low,
                high: High,

                pub fn setAttribute(config: *AttributeConfig, index: AttributeIndex, value: AttributeFormat) void {
                    std.mem.writePackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(AttributeFormat), @bitCast(value));
                }

                pub fn getAttribute(config: *AttributeConfig, index: AttributeIndex) void {
                    return @bitCast(std.mem.readPackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(AttributeFormat)));
                }

                pub fn setFlag(config: *AttributeConfig, index: AttributeIndex, value: Flags) void {
                    std.mem.writePackedIntNative(u1, std.mem.asBytes(config), (12 * @bitSizeOf(AttributeFormat)) + @intFromEnum(index) * @bitSizeOf(Flags), @bitCast(value));
                }

                pub fn getFlag(config: *AttributeConfig, index: AttributeIndex) void {
                    return @bitCast(std.mem.readPackedIntNative(u1, std.mem.asBytes(config), (12 * @bitSizeOf(AttributeFormat)) + @intFromEnum(index) * @bitSizeOf(Flags)));
                }
            };

            pub const AttributeBuffer = extern struct {
                pub const Config = extern struct {
                    pub const ArrayComponent = enum(u4) {
                        attribute_0,
                        attribute_1,
                        attribute_2,
                        attribute_3,
                        attribute_4,
                        attribute_5,
                        attribute_6,
                        attribute_7,
                        attribute_8,
                        attribute_9,
                        attribute_10,
                        attribute_11,

                        padding_4,
                        padding_8,
                        padding_12,
                        padding_16,
                    };

                    pub const Low = packed struct(u32) {
                        component_0: ArrayComponent = .attribute_0,
                        component_1: ArrayComponent = .attribute_1,
                        component_2: ArrayComponent = .attribute_2,
                        component_3: ArrayComponent = .attribute_3,
                        component_4: ArrayComponent = .attribute_4,
                        component_5: ArrayComponent = .attribute_5,
                        component_6: ArrayComponent = .attribute_6,
                        component_7: ArrayComponent = .attribute_7,
                    };

                    pub const High = packed struct(u32) {
                        component_8: ArrayComponent = .attribute_8,
                        component_9: ArrayComponent = .attribute_9,
                        component_10: ArrayComponent = .attribute_10,
                        component_11: ArrayComponent = .attribute_11,

                        bytes_per_vertex: u8,
                        _unused0: u4 = 0,
                        num_components: u4,
                    };

                    low: Low,
                    high: High,

                    pub fn setComponent(config: *AttributeBuffer.Config, index: ArrayComponentIndex, value: ArrayComponent) void {
                        std.mem.writePackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(ArrayComponent), @intFromEnum(value));
                    }

                    pub fn getComponent(config: *AttributeBuffer.Config, index: ArrayComponentIndex) ArrayComponent {
                        return @enumFromInt(std.mem.readPackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(ArrayComponent)));
                    }
                };

                offset: u32,
                config: AttributeBuffer.Config,
            };

            pub const AttributeIndexBuffer = packed struct(u32) {
                base_offset: u28,
                _unused0: u3 = 0,
                format: IndexFormat,
            };

            pub const DrawFunction = packed struct(u32) {
                pub const drawing: DrawFunction = .{ .mode = .drawing };
                pub const config: DrawFunction = .{ .mode = .config };
                pub const Mode = enum(u1) { drawing, config };

                mode: Mode,
                _: u31 = 0,
            };

            pub const FixedAttributeIndex = packed struct(u32) {
                pub const immediate_mode: FixedAttributeIndex = .{ .index = 0xF };

                index: u4,
                _unused0: u28 = 0,

                pub fn initIndex(index: u4) FixedAttributeIndex {
                    std.debug.assert(index <= 11);
                    return .{ .index = index };
                }
            };

            pub const PipelineConfig = packed struct(u32) {
                pub const GeometryUsage = enum(u2) { disabled, enabled = 2 };

                geometry_shader_usage: GeometryUsage = .disabled,
                _unused0: u6 = 0,
                drawing_triangles: bool = false,
                _unknown0: u1 = 0,
                _unused1: u6 = 0,
                _unknown1: u4 = 0,
                _unused2: u11 = 0,
                use_reserved_geometry_subdivision: bool = false,
            };

            pub const PipelineConfig2 = packed struct(u32) {
                inputting_vertices_or_draw_arrays: bool = false,
                _unused0: u7 = 0,
                drawing_triangles: bool = false,
                _unused1: u23 = 0,
            };

            pub const GeometryShaderConfig = packed struct(u32) {
                mode: u2,
                _unused0: u6 = 0,
                fixed_vertices_minus_one: u4,
                stride_minus_one: u4,
                fixed_vertices_start: u8,
                _unused1: u8 = 0,
            };

            attribute_buffer_base: AlignedPhysicalAddress(.@"16", .@"8"),
            attribute_config: AttributeConfig,
            attribute_buffer: [12]AttributeBuffer,
            attribute_buffer_index_buffer: AttributeIndexBuffer,
            attribute_buffer_num_vertices: u32,
            config: PipelineConfig,
            attribute_buffer_first_index: u32,
            _unknown0: [2]u32,
            post_vertex_cache_num: u32,
            attribute_buffer_draw_arrays: RightPaddedRegister(Trigger),
            attribute_buffer_draw_elements: RightPaddedRegister(Trigger),
            _unknown1: u32,
            clear_post_vertex_cache: RightPaddedRegister(Trigger),
            fixed_attribute_index: FixedAttributeIndex,
            fixed_attribute_data: F7_16x4,
            _unknown2: [2]u32,
            command_buffer_size: [2]u32,
            command_buffer_address: [2]u32,
            command_buffer_jump: [2]u32,
            _unknown3: [4]u32,
            vertex_shader_input_attributes: RightPaddedRegister(u4),
            _unknown4: u32,
            enable_geometry_shader_configuration: RightPaddedRegister(bool),
            start_draw_function: DrawFunction,
            _unknown5: [4]u32,
            vertex_shader_output_map_total_2: RightPaddedRegister(u4),
            _unknown6: [6]u32,
            vertex_shader_output_map_total_1: RightPaddedRegister(u4),
            geometry_shader_misc0: GeometryShaderConfig,
            config_2: PipelineConfig2,
            geometry_shader_misc1: u32,
            _unknown7: u32,
            _unknown8: [8]u32,
            primitive_config: PrimitiveConfig,
            restart_primitive: RightPaddedRegister(Trigger),
        };

        pub const Shader = extern struct {
            pub const Entry = packed struct(u32) {
                entry: u16,
                _: u16 = 0x7FFF,

                pub fn initEntry(entry: u16) Entry {
                    return .{ .entry = entry };
                }
            };

            pub const InputBufferConfig = packed struct(u32) {
                num_input_attributes: u4,
                _unused0: u4 = 0,
                use_geometry_shader_subdivision: bool = false,
                _unused1: u18 = 0,
                enabled_for_geometry_0: bool = false,
                _unknown0: u1 = 0,
                enabled_for_vertex_0: bool = false,
                _unused2: u1 = 0,
                enabled_for_vertex_1: bool = false,
            };

            pub const OutputMask = packed struct(u32) {
                o0_enabled: bool = false,
                o1_enabled: bool = false,
                o2_enabled: bool = false,
                o3_enabled: bool = false,
                o4_enabled: bool = false,
                o5_enabled: bool = false,
                o6_enabled: bool = false,
                o7_enabled: bool = false,
                o8_enabled: bool = false,
                o9_enabled: bool = false,
                o10_enabled: bool = false,
                o11_enabled: bool = false,
                o12_enabled: bool = false,
                o13_enabled: bool = false,
                o14_enabled: bool = false,
                o15_enabled: bool = false,
                _unknown0: u16 = 0,

                pub fn set(out_mask: *OutputMask, reg: shader.register.Destination.Output, value: bool) void {
                    std.mem.writePackedInt(u1, std.mem.asBytes(out_mask), @intFromEnum(reg), @intFromBool(value), .little);
                }
            };

            pub const FloatUniformConfig = packed struct(u32) {
                pub const Mode = enum(u1) { f7_16, f8_23 };

                index: FloatConstantRegister,
                _unused0: u24 = 0,
                mode: Mode,
            };

            pub const AttributePermutation = extern struct {
                pub const Low = packed struct(u32) {
                    attribute_0: InputRegister = .v0,
                    attribute_1: InputRegister = .v1,
                    attribute_2: InputRegister = .v2,
                    attribute_3: InputRegister = .v3,
                    attribute_4: InputRegister = .v4,
                    attribute_5: InputRegister = .v5,
                    attribute_6: InputRegister = .v6,
                    attribute_7: InputRegister = .v7,
                };

                pub const High = packed struct(u32) {
                    attribute_8: InputRegister = .v8,
                    attribute_9: InputRegister = .v9,
                    attribute_10: InputRegister = .v10,
                    attribute_11: InputRegister = .v11,
                    attribute_12: InputRegister = .v12,
                    attribute_13: InputRegister = .v13,
                    attribute_14: InputRegister = .v14,
                    attribute_15: InputRegister = .v15,
                };

                low: Low = .{},
                high: High = .{},

                pub fn setAttribute(config: *AttributePermutation, index: AttributeIndex, value: InputRegister) void {
                    std.mem.writePackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(InputRegister), @intFromEnum(value));
                }

                pub fn getAttribute(config: *AttributePermutation, index: AttributeIndex) InputRegister {
                    return @bitCast(std.mem.readPackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(InputRegister)));
                }
            };

            pub const BooleanUniformMask = packed struct(u32) {
                b0: bool,
                b1: bool,
                b2: bool,
                b3: bool,
                b4: bool,
                b5: bool,
                b6: bool,
                b7: bool,
                b8: bool,
                b9: bool,
                b10: bool,
                b11: bool,
                b12: bool,
                b13: bool,
                b14: bool,
                b15: bool,
                _unused0: u16 = 0x7FFF,
            };

            bool_uniform: BooleanUniformMask,
            int_uniform: [4][4]i8,
            _unused0: [4]u32,
            input_buffer_config: InputBufferConfig,
            entrypoint: Entry,
            attribute_permutation: AttributePermutation,
            output_map_mask: OutputMask,
            _unused1: u32,
            code_transfer_end: RightPaddedRegister(Trigger),
            float_uniform_index: FloatUniformConfig,
            float_uniform_data: [8]u32,
            _unused2: [2]u32,
            code_transfer_index: RightPaddedRegister(u12),
            code_transfer_data: [8]Instruction,
            _unused3: u32,
            operand_descriptors_index: RightPaddedRegister(u7),
            operand_descriptors_data: [8]OperandDescriptor,
        };

        irq: Interrupt,
        _unused0: [40]u8,
        rasterizer: Rasterizer,
        _unused1: [64]u8,
        texturing: TextureUnits,
        _unused2: [36]u8,
        texturing_procedural: ProceduralTextureUnit,
        _unused3: [32]u8,
        texture_combiners: TextureCombiners,
        _unused4: [8]u8,
        framebuffer: Internal.Framebuffer,
        fragment_lighting: FragmentLighting,
        _unused5: [152]u8,
        geometry_pipeline: GeometryPipeline,
        _unused6: [128]u8,
        geometry_shader: Shader,
        _unused7: [8]u8,
        vertex_shader: Shader,

        comptime {
            std.debug.assert(@offsetOf(Internal, "irq") == 0x0000);
            std.debug.assert(@offsetOf(Internal, "rasterizer") == 0x100);
            std.debug.assert(@offsetOf(Internal, "texturing") == 0x200);
            std.debug.assert(@offsetOf(Internal, "texturing_procedural") == 0x2A0);
            std.debug.assert(@offsetOf(Internal, "texture_combiners") == 0x300);
            std.debug.assert(@offsetOf(Internal, "framebuffer") == 0x400);
            std.debug.assert(@offsetOf(Internal, "fragment_lighting") == 0x500);
            std.debug.assert(@offsetOf(Internal, "geometry_pipeline") == 0x800);
            std.debug.assert(@offsetOf(Internal, "geometry_shader") == 0xA00);
            std.debug.assert(@offsetOf(Internal, "vertex_shader") == 0xAC0);
        }
    };

    hardware_id: u32,
    clock: u32,
    _unknown0: u32,
    _unused0: u32,
    psc: [2]MemoryFill,
    vram_power: VRamPower,
    irq: InterruptFlags,
    _something: u32,
    _make_something: u32,
    _backlight_or_so_0: u32,
    _unknown1: u32,
    _unknown2: u32,
    _unused1: u32,
    timing_control: [2]u32,
    stat_busy_flags: BusyFlags,
    _unknown3: u32,
    _unknown4: u32,
    _unknown5: u32,
    _unknown6: u32,
    _unused2: u32,
    traffic: TrafficStatus,
    _backlight_or_so_1: u32,
    vram_a_base_address: [*]u8,
    vram_b_base_address: [*]u8,
    _backlight_or_so_2: u32,
    _unknown7: u32,
    _unused3: [0x2C]u8,
    _unused4: [0x300]u8,
    pdc: [2]Pdc,
    _unused5: [0x600]u8 = @splat(0),
    dma: MemoryCopy,
    _unknown8: [0xF5]u32 = @splat(0),
    internal: Internal,
};

comptime {
    if (@sizeOf(Registers.Pdc) != 0x100)
        @compileError(std.fmt.comptimePrint("(@sizeOf(Pdc) == 0x{X}) and 0x{X} != 0x100!", .{ @sizeOf(Registers.Pdc), @sizeOf(Registers.Pdc) }));

    if (@sizeOf(Registers.MemoryFill) != 0x10)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryFill) == 0x{X}) and 0x{X} != 0x10!", .{ @sizeOf(Registers.MemoryFill), @sizeOf(Registers.MemoryFill) }));

    if (@sizeOf(Registers.MemoryCopy) != 0x2C)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryCopy) == 0x{X}) and 0x{X} != 0x2C!", .{ @sizeOf(Registers.MemoryCopy), @sizeOf(Registers.MemoryCopy) }));

    _ = shader;
}

const std = @import("std");
const zsflt = @import("zsflt");
const zitrus = @import("zitrus");

const OperandDescriptor = shader.encoding.OperandDescriptor;
const Instruction = shader.encoding.Instruction;
const FloatConstantRegister = shader.register.Source.Constant;
const InputRegister = shader.register.Source.Input;

const AlignedPhysicalAddress = zitrus.AlignedPhysicalAddress;
const PhysicalAddress = zitrus.PhysicalAddress;
