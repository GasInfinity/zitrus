//! Definitions for MMIO `PICA200` registers.
//!
//! - LCD screens are physically rotated 90º CCW from how the devices are held (i.e: bottom is not 320x240, is 240x320)
//! - NDC clipping volume:
//!     - X: [-W, W]
//!     - Y: [-W, W]
//!     - Z: [0, -W]
//! - Framebuffer origin can be changed so `-1` in NDC could mean bottom-left (GL) or top-left (D3D, Metal, VK)
//!
//! WARNING: zitrus has opinionated register naming that suit better their usage!
//!
//! Based on the documentation found in GBATEK and 3dbrew:
//! - https://problemkaputt.de/gbatek.htm#3dsgpuinternalregisteroverview
//! - https://www.3dbrew.org/wiki/GPU/External_Registers
//! - https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const command = @import("pica/command.zig");
pub const shader = @import("pica/shader.zig");

pub const UQ0_11 = zsflt.Fixed(.unsigned, 0, 11);
pub const UQ0_12 = zsflt.Fixed(.unsigned, 0, 12);
pub const UQ0_23 = zsflt.Fixed(.unsigned, 0, 23);
pub const Q4_8 = zsflt.Fixed(.signed, 4, 8);
pub const Q0_11 = zsflt.Fixed(.signed, 0, 11);
pub const Q1_11 = zsflt.Fixed(.signed, 1, 11);

pub const F5_10 = zsflt.Float(5, 10);
pub const F3_12 = zsflt.Float(3, 12);
pub const F7_12 = zsflt.Float(7, 12);
pub const F7_16 = zsflt.Float(7, 16);
pub const F7_23 = zsflt.Float(7, 23);
pub const F8_23 = zsflt.Float(8, 23);

pub const Q1_11x2 = packed struct(u32) {
    x: Q1_11,
    _unused0: u3 = 0,
    y: Q1_11,
    _unused1: u3 = 0,

    pub fn init(x: Q1_11, y: Q1_11) Q1_11x2 {
        return .{ .x = x, .y = y };
    }
};

pub const F5_10x2 = packed struct(u32) {
    x: F5_10,
    y: F5_10,

    pub fn init(x: F5_10, y: F5_10) F5_10x2 {
        return .{ .x = x, .y = y };
    }
};

pub const F7_16x4 = extern struct {
    pub const Unpacked = struct { x: F7_16, y: F7_16, z: F7_16, w: F7_16 };

    data: [@divExact(@bitSizeOf(F7_16) * 4, @bitSizeOf(u32))]u32,

    pub fn pack(x: F7_16, y: F7_16, z: F7_16, w: F7_16) F7_16x4 {
        var vec: F7_16x4 = undefined;
        const vec_bytes = std.mem.asBytes(&vec.data);

        std.mem.writePackedInt(u24, vec_bytes, 0, @bitCast(x), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16), @bitCast(y), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 2, @bitCast(z), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 3, @bitCast(w), .little);
        std.mem.swap(u32, &vec.data[0], &vec.data[2]);

        return vec;
    }

    pub fn unpack(value: F7_16x4) [4]F7_16 {
        var unpacked: [3]u32 = value.data;
        std.mem.swap(u32, &unpacked[0], &unpacked[2]);

        return .{
            @bitCast(std.mem.readPackedInt(u24, @ptrCast(&unpacked), 0, .little)),
            @bitCast(std.mem.readPackedInt(u24, @ptrCast(&unpacked), @bitSizeOf(F7_16), .little)),
            @bitCast(std.mem.readPackedInt(u24, @ptrCast(&unpacked), @bitSizeOf(F7_16) * 2, .little)),
            @bitCast(std.mem.readPackedInt(u24, @ptrCast(&unpacked), @bitSizeOf(F7_16) * 3, .little)),
        };
    }
};

pub const morton = struct {
    /// Returns the morton/z-order coordinates for `value`
    pub fn toDimensions(comptime T: type, comptime dimensions: usize, value: T) [dimensions]std.meta.Int(.unsigned, @divExact(@bitSizeOf(T), dimensions)) {
        std.debug.assert(@typeInfo(T) == .int);
        const DecomposedInt = std.meta.Int(.unsigned, @divExact(@bitSizeOf(T), dimensions));

        // Basically bits are interleaved
        // 2-dimensional 8-bits example: yxyxyxyx
        var values: [dimensions]DecomposedInt = @splat(0);
        var current_value = value;
        inline for (0..@bitSizeOf(T)) |i| {
            const shift = i / dimensions;
            const set = &values[i % dimensions];

            set.* |= @intCast((current_value & 0b1) << shift);
            current_value >>= 1;
        }

        return values;
    }

    pub const Strategy = enum { tile, untile };

    pub fn convert(comptime strategy: Strategy, comptime tile_size: usize, width: usize, pixel_size: usize, dst_pixels: []u8, src_pixels: []const u8) void {
        std.debug.assert(dst_pixels.len == src_pixels.len);
        const max_tile_subindex = (tile_size * tile_size);
        const SubindexInt = std.math.IntFittingRange(0, max_tile_subindex - 1);

        const height = @divExact(@divExact(src_pixels.len, pixel_size), width);
        const width_tiles = @divExact(width, tile_size);
        const height_tiles = @divExact(height, tile_size);
        const stride = width * pixel_size;

        var i: usize = 0;
        for (0..height_tiles) |y_tile| {
            const y_start = y_tile * tile_size;

            for (0..width_tiles) |x_tile| {
                const x_start = x_tile * tile_size;

                for (0..max_tile_subindex) |tile| {
                    const x, const y = toDimensions(SubindexInt, 2, @intCast(tile));

                    const linear_index = i;
                    const morton_index = (y_start + y) * stride + (x_start + x) * pixel_size;

                    const src_pixel, const dst_pixel = switch (strategy) {
                        .tile => .{ src_pixels[morton_index..][0..pixel_size], dst_pixels[linear_index..][0..pixel_size] },
                        .untile => .{ src_pixels[linear_index..][0..pixel_size], dst_pixels[morton_index..][0..pixel_size] },
                    };

                    @memcpy(dst_pixel, src_pixel);
                    i += pixel_size;
                }
            }
        }
    }

    pub fn convertNibbles(comptime strategy: Strategy, comptime tile_size: usize, width: usize, dst_pixels: []u8, src_pixels: []const u8) void {
        std.debug.assert(dst_pixels.len == src_pixels.len);
        const max_tile_subindex = (tile_size * tile_size);
        const SubindexInt = std.math.IntFittingRange(0, max_tile_subindex - 1);

        const height = @divExact(src_pixels.len << 1, width);
        const width_tiles = @divExact(width, tile_size);
        const height_tiles = @divExact(height, tile_size);
        const stride = @divExact(width, 2);

        var i: usize = 0;
        for (0..height_tiles) |y_tile| {
            const y_start = y_tile * tile_size;

            for (0..width_tiles) |x_tile| {
                const x_start = x_tile * tile_size;

                for (0..max_tile_subindex) |tile| {
                    const x, const y = toDimensions(SubindexInt, 2, @intCast(tile));

                    const linear_index = i >> 1;
                    const second_linear_nibble = (i & 1) != 0; 

                    const morton_x = (x_start + x);
                    const morton_index = (y_start + y) * stride + (morton_x >> 1);
                    const second_morton_nibble = (morton_x & 1) != 0;
                    
                    const src_pixel, const dst_pixel, const second_src_nibble, const second_dst_nibble = switch (strategy) {
                        .tile => .{ &src_pixels[morton_index], &dst_pixels[linear_index], second_morton_nibble, second_linear_nibble },
                        .untile => .{ &src_pixels[linear_index], &dst_pixels[morton_index], second_linear_nibble, second_morton_nibble },
                    };

                    const src_nibble = if(second_src_nibble) (src_pixel.* >> 4) else (src_pixel.* & 0xF);
                    const last_dst_pixel = dst_pixel.*;

                    dst_pixel.* = if(second_dst_nibble) (last_dst_pixel & 0xF) | (src_nibble << 4) else (last_dst_pixel & 0xF0) | src_nibble;
                    i += 1;
                }
            }
        }
    }
};

pub const Screen = enum(u1) {
    pub const width_po2 = 256;

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

    pub fn bytesPerPixel(format: DepthStencilFormat) usize {
        return switch (format) {
            .d16 => @sizeOf(u16),
            .d24 => 3,
            .d24_s8 => @sizeOf(u32),
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

pub const FramebufferFormat = packed struct(u32) {
    pub const Mode = enum(u2) {
        @"2d",
        @"3d",
        full_resolution,
    };

    color_format: ColorFormat,
    _unknown0: u1 = 0,
    interlacing_mode: FramebufferInterlacingMode,
    alternative_pixel_output: bool,
    _unknown1: u1 = 0,
    dma_size: DmaSize,
    _unknown2: u6 = 0,
    _unknown3: u16 = 0,

    pub inline fn mode(format: FramebufferFormat) Mode {
        return switch (format.interlacing_mode) {
            .enable => .@"3d",
            else => if (format.alternative_pixel_output) .@"2d" else .full_resolution,
        };
    }
};

pub const TextureUnit = enum(u2) {
    pub const main: TextureUnit = .@"0";
    pub const procedural: TextureUnit = .@"3";

    @"0",
    @"1",
    @"2",
    @"3",
};

/// The front face is always counter-clockwise and cannot be changed.
pub const CullMode = enum(u2) {
    /// No triangles are discarded.
    none,
    /// Triangles with a counter-clockwise winding order are culled.
    ccw,
    /// Triangles with a clockwise winding order are culled.
    cw,
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

        texture_coordinates_0_u,
        texture_coordinates_0_v,
        texture_coordinates_1_u,
        texture_coordinates_1_v,
        texture_coordinates_0_w,

        view_x = 0x12,
        view_y,
        view_z,

        texture_coordinates_2_u,
        texture_coordinates_2_v,

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

        pub fn isTextureCoordinates0(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinates_0_u, .texture_coordinates_0_v, .texture_coordinates_0_w => true,
                else => false,
            };
        }

        pub fn isTextureCoordinates1(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinates_1_u, .texture_coordinates_1_v => true,
                else => false,
            };
        }

        pub fn isTextureCoordinates2(semantic: Semantic) bool {
            return switch (semantic) {
                .texture_coordinates_2_u, .texture_coordinates_2_v => true,
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

    /// Another PICA200 classic. For `drawIndexed` (`drawElements` as GL people call it) you set
    /// the primitive topology to `geometry`.
    ///
    /// Why? Ask the DMP engineers
    pub fn indexedTopology(topology: PrimitiveTopology) PrimitiveTopology {
        return switch (topology) {
            .triangle_list => .geometry,
            else => |topo| topo,
        };
    }
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

    pub fn scale(format: TextureUnitFormat, size: usize) usize {
        return switch (format) {
            .abgr8888 => size << 2,
            .bgr888 => size * 3,
            .rgba5551, .rgb565, .rgba4444, .ia88, .hilo88 => size << 1,
            .i8, .a8, .ia44, .etc1a4 => size,
            .i4, .a4, .etc1 => size >> 1,
        };
    }
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
    output_dimensions: [2]u16,
    input_dimensions: [2]u16,
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
    texture_input_width_gap: [2]u16,
    texture_output_width_gap: [2]u16,
};

pub const Graphics = extern struct {
    pub const AttributeIndex = enum(u4) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };
    pub const ArrayComponentIndex = enum(u4) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };

    pub const Interrupt = extern struct {
        pub const Mask = extern struct {
            disabled_low: BitpackedArray(bool, 32),
            disabled_high: BitpackedArray(bool, 32),
        };

        pub const Stat = extern struct {
            match_low: BitpackedArray(bool, 32),
            match_high: BitpackedArray(bool, 32),
        };

        ack: [64]u8,
        req: [64]u8,
        cmp: [64]u8,
        mask: Mask,
        stat: Stat,
        autostop: LsbRegister(bool),
        fixed_0x00010002: u32,
    };

    pub const Rasterizer = extern struct {
        pub const Mode = enum(u2) { normal, interlace, wireframe, normal_2 };
        pub const ClippingPlane = extern struct {
            /// Enable the clipping plane
            enable: LsbRegister(bool),
            /// Coefficients of the clipping plane.
            coefficients: [4]LsbRegister(F7_16),
        };

        pub const Status = extern struct {
            vertices_received: u32,
            triangles_received: u32,
            triangles_displayed: u32,
        };

        pub const Scissor = extern struct {
            mode: LsbRegister(ScissorMode),
            /// The start of the scissor region, origin bottom-left.
            start: [2]u16,
            /// The end of the scissor region (inclusive), origin bottom-left.
            end: [2]u16,
        };

        pub const OutputAttributeMode = packed struct(u32) {
            use_texture_coordinates: bool = false,
            _: u31 = 0,
        };

        pub const OutputAttributeClock = packed struct(u32) {
            position_z_present: bool = false,
            color_present: bool = false,
            _unused0: u6 = 0,
            texture_coordinates_present: BitpackedArray(bool, 3) = .splat(false),
            _unused1: u5 = 0,
            texture_coordinates_0_w_present: bool = false,
            _unused2: u7 = 0,
            normal_view_present: bool = false,
            _unused3: u7 = 0,
        };

        pub const DepthMap = extern struct {
            pub const Mode = enum(u1) {
                /// Precision is evenly distributed.
                w,
                /// Precision is higher close to the near plane.
                z,
            };

            /// Scale to map depth from [0, -1] to [0, 1].
            scale: LsbRegister(F7_16),
            /// Bias to map depth from [0, -1] to [0, 1].
            bias: LsbRegister(F7_16),
        };

        pub const UndocumentedConfig0 = packed struct(u32) {
            _unknown0: bool = false,
            _unused0: u7 = 0,
            /// Sometimes interlaces, sometimes skips pixels.
            /// Depends on how the GPU feels that day.
            dirty_interlace_skip: bool = false,
            /// Weird, it "enables" some sort of wireframe in the rasterizer,
            /// it does NOT convert triangles to lines as clipped triangles will
            /// be correctly splitted, is purely a rasterizer thing.
            dirty_wireframe: bool,
            _unused1: u22 = 0,
        };

        cull_config: LsbRegister(CullMode),
        /// `Width / 2.0`, used for scaling vertex coordinates.
        viewport_h_scale: LsbRegister(F7_16),
        /// `2.0 / Width`, supposedly used for stepping colors and texture coordinates.
        viewport_h_step: MsbRegister(F7_23),
        /// `Height / 2.0`, used for scaling vertex coordinates.
        viewport_v_scale: LsbRegister(F7_16),
        /// `2.0 / Height`, supposedly used for stepping colors and texture coordinates.
        viewport_v_step: MsbRegister(F7_23),
        _unknown0: [2]u32,
        /// Extra user-defined clipping plane.
        extra_clipping_plane: ClippingPlane,
        _unknown1: [1]u32,
        /// Maps depth from NDC [0, -1] to framebuffer [0, 1].
        depth_map: DepthMap,
        shader_output_map_total: LsbRegister(u3),
        shader_output_map_output: [7]OutputMap,
        _unknown2: u32,
        shader_output_map_qualifiers: u32, // According to GBATEK this allows you to use the flat qualifier in output colors.
        _unknown3: u32,
        status: Status,
        _unknown4: [3]u32,
        config: UndocumentedConfig0,
        /// So early depth somehow has a separate internal buffer that must be cleared.
        /// From tests it looks like it has MUCH LESS precision and literally breaks with anything,
        /// 32x32 is needed. Overall, is it really needed?
        ///
        /// I don't know what engineers were smoking but it has too many false fails, discarding lots of fragments.
        /// XXX: No more can be said, this is vaulted until new info comes out.
        early_depth_function: LsbRegister(EarlyDepthCompareOperation),
        early_depth_test_enable: LsbRegister(bool),
        early_depth_clear: LsbRegister(Trigger),
        shader_output_attribute_mode: OutputAttributeMode,
        scissor: Scissor,
        /// Viewport origin, origin is bottom-left.
        viewport_xy: [2]u16,
        _unknown8: u32,
        early_depth_data: LsbRegister(u24),
        _unknown9: [2]u32,
        depth_map_mode: LsbRegister(DepthMap.Mode),
        /// Does not seem to have an effect but it's still documented like this
        _unused_render_buffer_dimensions: u32, // XXX: Why would the rasterizer need output dimensions?
        shader_output_attribute_clock: OutputAttributeClock,
    };

    pub const TextureUnits = extern struct {
        pub const Config = packed struct(u32) {
            texture_enabled: BitpackedArray(bool, 3),
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

        pub const Parameters = packed struct(u32) {
            pub const Etc1Flag = enum(u2) { none, etc1 = 2 };

            _unknown0: u1 = 0,
            mag_filter: TextureUnitFilter,
            min_filter: TextureUnitFilter,
            _unknown1: u1 = 0,
            etc1: Etc1Flag,
            _unknown2: u2 = 0,
            address_mode_v: TextureUnitAddressMode,
            _unknown3: u1 = 0,
            address_mode_u: TextureUnitAddressMode,
            _unknown4: u5 = 0,
            is_shadow: bool,
            _unknown5: u3 = 0,
            mip_filter: TextureUnitFilter,
            _unused0: u3 = 0,
            type: TextureUnitType,
            _unused1: u1 = 0,
        };

        pub const LevelOfDetail = packed struct(u32) {
            bias: Q4_8,
            _unknown0: u3 = 0,
            max_level_of_detail: u4,
            _unknown1: u4 = 0,
            min_level_of_detail: u4,
            _unused0: u4 = 0,
        };

        pub const Shadow = packed struct(u32) {
            orthogonal: bool,
            // XXX: Documented as "the higher 23-bits of an UQ0.24": Bro, thats just an UQ0.23?
            z_bias: UQ0_23,
            _unknown0: u8 = 0,
        };

        pub const Primary = extern struct {
            border_color: [4]u8,
            dimensions: [2]u16,
            parameters: Parameters,
            lod: LevelOfDetail,
            address: [6]AlignedPhysicalAddress(.@"8", .@"8"),
            shadow: Shadow,
            _unknown0: u32,
            _unknown1: u32,
            format: LsbRegister(TextureUnitFormat),
        };

        pub const Secondary = extern struct {
            border_color: [4]u8,
            dimensions: [2]u16,
            /// WARNING: Type is ignored in secondary texture units, they're always 2d according to 3dbrew.
            parameters: Parameters,
            lod: LevelOfDetail,
            address: AlignedPhysicalAddress(.@"8", .@"8"),
            format: LsbRegister(TextureUnitFormat),
        };

        config: Config,
        @"0": Primary,
        lighting_enable: LsbRegister(bool),
        _unknown0: u32,
        @"1": Secondary,
        _unknown1: [2]u32,
        @"2": Secondary,
    };

    pub const ProceduralTextureUnit = extern struct {
        pub const Main = extern struct {
            procedural_texture: [5]u32,
            procedural_texture_5_low: u32,
            procedural_texture_5_high: u32,
        };

        @"3": Main,
        lut_index: u32,
        lut_data: [8]u32,
    };

    pub const TextureCombiners = extern struct {
        pub const FogMode = enum(u3) { disabled, fog = 5, gas = 7 };
        pub const ShadingDensity = enum(u1) { plain, depth };
        pub const BufferSource = enum(u1) { previous_buffer, previous };
        pub const Multiplier = enum(u2) { @"1x", @"2x", @"4x" };
        pub const Source = enum(u4) {
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

        pub const ColorFactor = enum(u4) {
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

        pub const AlphaFactor = enum(u3) {
            src_alpha,
            one_minus_src_alpha,
            src_red,
            one_minus_src_red,
            src_green,
            one_minus_src_green,
            src_blue,
            one_minus_src_blue,
        };

        pub const Operation = enum(u4) {
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

        pub const Config = packed struct(u32) {
            fog_mode: FogMode,
            shading_density_source: ShadingDensity,
            _unused0: u4 = 0,
            combiner_color_buffer_src: BitpackedArray(BufferSource, 4),
            combiner_alpha_buffer_src: BitpackedArray(BufferSource, 4),
            z_flip: bool,
            _unused1: u7 = 0,
            _unknown0: u2 = 0,
            _unused2: u6 = 0,

            pub const BufferIndex = enum(u3) { @"1", @"2", @"3", @"4" };

            pub fn setColorBufferSource(update_buffer: *Config, index: BufferIndex, buffer_src: BufferSource) void {
                std.mem.writePackedIntNative(u1, std.mem.asBytes(update_buffer), @as(usize, @bitOffsetOf(Config, "combiner_color_buffer_src")) + @intFromEnum(index), @intFromEnum(buffer_src));
            }

            pub fn setAlphaBufferSource(update_buffer: *Config, index: BufferIndex, buffer_src: BufferSource) void {
                std.mem.writePackedIntNative(u1, std.mem.asBytes(update_buffer), @as(usize, @bitOffsetOf(Config, "combiner_alpha_buffer_src")) + @intFromEnum(index), @intFromEnum(buffer_src));
            }
        };

        pub const Unit = extern struct {
            pub const Sources = packed struct(u32) {
                color_src: BitpackedArray(Source, 3),
                _unused0: u4 = 0,
                alpha_src: BitpackedArray(Source, 3),
                _unused1: u4 = 0,
            };

            pub const Factors = packed struct(u32) {
                color_factor: BitpackedArray(ColorFactor, 3),
                alpha_factor: BitpackedArray(AlphaFactor, 3),
                _unused0: u11 = 0,
            };

            pub const Operations = packed struct(u32) {
                color_op: Operation,
                _unused0: u12 = 0,
                alpha_op: Operation,
                _unused1: u12 = 0,
            };

            pub const Scales = packed struct(u32) {
                color_scale: Multiplier,
                _unused0: u14 = 0,
                alpha_scale: Multiplier,
                _unused1: u14 = 0,
            };

            sources: Sources,
            factors: Factors,
            operations: Operations,
            color: [4]u8,
            scales: Scales,
        };

        pub const FogLutValue = packed struct(u24) {
            next_difference: Q1_11,
            value: UQ0_11,
        };

        @"0": Unit,
        _unknown0: [3]u32,
        @"1": Unit,
        _unknown1: [3]u32,
        @"2": Unit,
        _unknown2: [3]u32,
        @"3": Unit,
        _unknown3: [3]u32,
        config: Config,
        fog_color: [4]u8,
        _unknown4: [2]u32,
        gas_attenuation: LsbRegister(F5_10),
        gas_accumulation_max: LsbRegister(F5_10),
        fog_lut_index: LsbRegister(u16),
        _unknown5: u32,
        fog_lut_data: [8]LsbRegister(FogLutValue),
        @"4": Unit,
        _unknown6: [3]u32,
        @"5": Unit,
        buffer_color: [4]u8,
    };

    pub const OutputMerger = extern struct {
        pub const Blend = enum(u1) { logic, blend };
        pub const Mode = enum(u2) { default, gas, shadow = 3 };
        pub const Interlace = enum(u1) { disable, even };
        pub const BlockSize = enum(u1) { @"8x8", @"32x32" };

        pub const Config = packed struct(u32) {
            mode: Mode,
            _unused0: u6 = 0,

            blend: Blend,
            _unused1: u7 = 0,
            _unknown0: u8 = 0xE4, // (?) Not setting this doesn't have an effect visually (?)
            /// Isn't this similar to interlace? I mean rendering each 2nd line is literally that. There should be something for odd lines maybe?
            interlace: Interlace = .disable,
            /// Can this be some sort of primitive discard or is literally render nothing?
            disable_rendering: bool = false,
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

        pub const AlphaTest = packed struct(u32) {
            enable: bool,
            _unused0: u3 = 0,
            op: CompareOperation,
            _unused1: u1 = 0,
            reference: u8,
            _unused3: u16 = 0,
        };

        pub const StencilTest = extern struct {
            pub const Config = packed struct(u32) {
                enable: bool,
                _unused0: u3 = 0,
                op: CompareOperation,
                _unused1: u1 = 0,
                compare_mask: u8,
                reference: u8,
                write_mask: u8,
            };

            pub const Operation = packed struct(u32) {
                fail_op: StencilOperation,
                _unused0: u1 = 0,
                depth_fail_op: StencilOperation,
                _unused1: u1 = 0,
                pass_op: StencilOperation,
                _unused2: u21 = 0,
            };

            config: StencilTest.Config,
            operation: Operation,
        };

        pub const DepthTestColorConfig = packed struct(u32) {
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

        pub const ColorAccess = enum(u4) { disable, all = 0xF };
        pub const DepthStencilAccess = enum(u2) { disable, stencil, depth, all };

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

        config: Config,
        blend_config: BlendConfig,
        logic_config: LsbRegister(LogicOperation),
        blend_color: [4]u8,
        alpha_test: AlphaTest,
        stencil_test: StencilTest,
        depth_color_config: DepthTestColorConfig,
        _unknown0: [8]u32,
        invalidate: LsbRegister(Trigger),
        flush: LsbRegister(Trigger),
        color_read: LsbRegister(ColorAccess),
        color_write: LsbRegister(ColorAccess),
        depth_read: LsbRegister(DepthStencilAccess),
        depth_write: LsbRegister(DepthStencilAccess),
        depth_format: LsbRegister(DepthStencilFormat),
        color_format: ColorBufferFormat,
        early_depth_test_enable: LsbRegister(bool),
        _unknown1: [2]u32,
        block_size: LsbRegister(BlockSize),
        depth_location: AlignedPhysicalAddress(.@"64", .@"8"),
        color_location: AlignedPhysicalAddress(.@"64", .@"8"),
        dimensions: RenderBufferDimensions,
        _unknown2: u32,
        gas_light_xy: u32,
        gas_light_z: u32,
        gas_light_z_color: u32,
        gas_lut_index: u32,
        gas_lut_data: u32,
        _unknown3: u32,
        gas_delta_z_depth: u32,
        _unknown4: [9]u32,
        fragment_operation_shadow: u32,
        _unknown5: [15]u32,
    };

    /// Fragment lighting in the PICA200 is done primarily through 1D lookup tables and quaternion interpolation.
    ///
    /// The vertex shader (or geometry if used) must output a Quaternion representing the rotation from the z-axis
    /// to the normal. This can be done in different ways, with the standard RotationFromTo(.{0, 0, 1}, Normal) or
    /// the approach in the 'Shading by Quaternion Interpolation' paper.
    ///
    /// It must also output a View position that is optionally used for positional lights to calculate the
    /// light vector, as directional lights are not affected by it.
    ///
    /// There are 22 `LookupTable`s available:
    ///     - 2 distribution tables for specular: D0 and D1
    ///     - 1 fresnel table: Fr
    ///     - 3 reflection tables for each color channel for reflection (D1): Rr, Rg and Rb
    ///     - 8 spotlight tables: Sp0 to Sp7
    ///     - 8 distance attenuation tables: Da0 to Da7
    ///
    /// The relevant lighting formulas are these (sources below):
    ///     Cp -> primary color, also called diffuse / Cs -> secondary color, also called specular
    ///
    /// Cp = ambient + foreach light ( Da*i*(*sd*) * Sp*i*(*in*) * H * (ambient*i* + diffuse*i* * f(L * N)) )
    ///
    /// Cs = foreach light ( Da*i*(*sd*) * Sp*i*(*in*) * H * (specular*i*0**x** * D0(*in*) * G + specular*i*1**x** * R**x**(*in*) * D1(*in*) * G) )
    ///
    /// where:
    ///     - H -> shadow attenuation factor
    ///     - *i* -> For light *i*
    ///     - **x** -> Color channel (r, g or b)
    ///     - *sd* -> Scaled distance, clip(`bias`*i* + `scale`*i* * distance, 0, 1)
    ///     - *in* -> One of the `LookupTable.Input`s
    ///     - G -> Geometric factor, when enabled is `(L * N) / lengthSqr(L + N)`, `1.0` otherwise
    ///
    /// Lookup tables (except Da) can have an input domain of [-1.0, 1.0] or [0.0, 1.0] depending on the `LookupTable.Absolute` flags.
    /// Da always has an input domain of [0.0, 1.0]. The mapping of input to index is:
    /// - [0.0, 1.0] -> [0, 255]
    /// - [-1.0, 1.0] -> [0.0, 1.0] is [0, 127] and [-1.0, 0.0] is [128, 255]
    ///
    ///
    /// With all of that, the PICA200 can do both PBR and NPBR, for example a Blinn-Phong shading model can be done with:
    /// - D0 enabled (absolute) with input N * H where each entry is `(N * H)^s` and `s` is the *shininess* of the surface.
    ///
    /// Sources:
    /// - 3dbrew
    /// - 'Primitive Processing and Advanced Shading Architecture for Embedded Space' by Max Kazakov & Eisaku Ohbuchi.
    ///     - Both slides and paper are useful!
    /// - 'A Real-Time Configurable Shader Based on Lookup Tables' by Eisaku Ohbuchi & Hiroshi Unno.
    ///     - Warning: Paywalled, you must pay or access it through an institution (e.g: university)
    /// - 'Shading by Quaternion Interpolation' by Anders Hast.
    pub const FragmentLighting = extern struct {
        pub const Color = packed struct(u32) {
            b: u8,
            _unused0: u2 = 0,
            g: u8,
            _unused1: u2 = 0,
            r: u8,
            _unused2: u4 = 0,

            pub fn init(r: u8, g: u8, b: u8) Color {
                return .{ .r = r, .g = g, .b = b };
            }

            pub fn initBuffer(rgb: [3]u8) Color {
                return .init(rgb[0], rgb[1], rgb[2]);
            }

            pub fn splat(v: u8) Color {
                return .init(v, v, v);
            }
        };

        pub const FresnelSelector = enum(u2) { none, primary, secondary, both };
        pub const LookupTable = enum(u5) {
            pub const Enabled = enum(u4) {
                d0_rr_sp_da,
                fr_rr_sp_da,
                d0_d1_rr_da,
                d0_d1_fr_da,
                d0_d1_rx_sp_da,
                d0_fr_rx_sp_da,
                d0_d1_fr_rr_sp_da,
                all = 8,
            };

            pub const Index = packed struct(u32) {
                index: u8,
                table: LookupTable,
                _unused0: u19 = 0,

                pub fn init(table: LookupTable, index: u8) Index {
                    return .{ .table = table, .index = index };
                }
            };

            pub const Absolute = packed struct(u32) {
                _unused0: u1 = 0,
                disable_d0: bool = false,
                _unused1: u3 = 0,
                disable_d1: bool = false,
                _unused2: u3 = 0,
                disable_sp: bool = false,
                _unused3: u3 = 0,
                disable_fr: bool = false,
                _unused4: u3 = 0,
                disable_rb: bool = false,
                _unused5: u3 = 0,
                disable_rg: bool = false,
                _unused6: u3 = 0,
                disable_rr: bool = false,
                _unused7: u6 = 0,
            };

            pub const Input = enum(u3) { @"N * H", @"V * H", @"N * V", @"L * N", @"-L * P", @"cos(phi)" };
            pub const Select = packed struct(u32) {
                d0: Input = .@"N * H",
                _unused0: u1 = 0,
                d1: Input = .@"N * H",
                _unused1: u1 = 0,
                sp: Input = .@"N * H",
                _unused2: u1 = 0,
                fr: Input = .@"N * H",
                _unused3: u1 = 0,
                rb: Input = .@"N * H",
                _unused4: u1 = 0,
                rg: Input = .@"N * H",
                _unused5: u1 = 0,
                rr: Input = .@"N * H",
                _unused6: u5 = 0,
            };

            pub const Multiplier = enum(u3) { @"1x", @"2x", @"4x", @"8x", @"0.25x" = 6, @"0.5x" };
            pub const Scale = packed struct(u32) {
                d0: Multiplier = .@"1x",
                _unused0: u1 = 0,
                d1: Multiplier = .@"1x",
                _unused1: u1 = 0,
                sp: Multiplier = .@"1x",
                _unused2: u1 = 0,
                fr: Multiplier = .@"1x",
                _unused3: u1 = 0,
                rb: Multiplier = .@"1x",
                _unused4: u1 = 0,
                rg: Multiplier = .@"1x",
                _unused5: u1 = 0,
                rr: Multiplier = .@"1x",
                _unused6: u5 = 0,
            };

            pub const Data = packed struct(u32) {
                entry: UQ0_12,
                next_absolute_difference: Q0_11,
                _unused0: u8 = 0,

                // TODO: initBuffer

                pub fn initContext(
                    context: anytype,
                    absolute: bool,
                ) [256]Data {
                    var lut: [256]Data = undefined;

                    const absolute_unit: f32 = @floatFromInt(@intFromBool(absolute));
                    const negated_unit = 1 - absolute_unit;

                    const msb_multiplier: f32 = (absolute_unit * 2 - 1) * 128;
                    const max = 256.0 - (negated_unit * 128.0);

                    var last: f32 = context.value(0.0);
                    for (1..lut.len) |i| {
                        const input = (@as(f32, @floatFromInt(i & 0x7F)) + @as(f32, @floatFromInt((i >> 7) & 0b1)) * msb_multiplier) / max;

                        const current: f32 = context.value(input);
                        defer last = current;

                        lut[i - 1] = .{
                            .entry = .ofSaturating(last),
                            .next_absolute_difference = .ofSaturating(@abs(current - last)),
                        };
                    }

                    lut[255] = .{ .entry = .ofSaturating(last), .next_absolute_difference = .ofSaturating(context.value(absolute_unit) - last) };
                    return lut;
                }
            };

            // zig fmt: off
            d0, d1,
            fr = 3,
            rb, rg, rr,
            sp0 = 8, sp1, sp2, sp3, sp4, sp5, sp6, sp7,
            da0, da1, da2, da3, da4, da5, da6, da7,
            // zig fmt: on
        };

        pub const BumpMode = enum(u2) { none, bump, tangent };

        pub const Control = extern struct {
            pub const Environment = packed struct(u32) {
                enable_shadow_factor: bool,
                _unused0: u1 = 0,
                fresnel: FresnelSelector,
                enabled_lookup_tables: LookupTable.Enabled,
                _unknown0: u4 = 0x4,
                _unused1: u4 = 0,
                apply_shadow_attenuation_to_primary_color: bool,
                apply_shadow_attenuation_to_secondary_color: bool,
                invert_shadow_attenuation: bool,
                apply_shadow_attenuation_to_alpha: bool,
                _unused2: u2 = 0,
                bump_map_unit: TextureUnit,
                /// BIG BRAIN TIME, lets configure the shadow map unit........
                /// Only unit 0 supports them?
                shadow_map_unit: TextureUnit,
                _unused3: u1 = 0,
                clamp_highlights: bool,
                bump_mode: BumpMode,
                disable_bump_recalculation: bool,
                _unknown1: u1 = 0x1,
            };

            pub const Lights = packed struct(u32) {
                shadows_disabled: BitpackedArray(bool, 8),
                spotlight_disabled: BitpackedArray(bool, 8),
                disable_d0: bool,
                disable_d1: bool,
                _unknown0: u1 = 0x1,
                disable_fr: bool,
                disable_rb: bool,
                disable_rg: bool,
                disable_rr: bool,
                _unknown1: u1 = 0x1,
                distance_attenuation_disabled: BitpackedArray(bool, 8),
            };

            environment: Environment,
            lights: Lights,
        };

        pub const Light = extern struct {
            pub const Id = enum(u4) {
                _,

                pub fn init(value: u3) Id {
                    return @enumFromInt(value);
                }
            };

            pub const Type = enum(u1) { positional, directional };
            pub const DiffuseSides = enum(u1) { one, both };

            pub const Factors = extern struct {
                specular: [2]Color,
                diffuse: Color,
                ambient: Color,
            };

            pub const Parameters = extern struct {
                /// Its `xy` position if positional, otherwise its `xy` direction (unitary).
                ///
                /// If it is a directional light, the direction vector is Object -> Light,
                xy: F5_10x2,
                /// Its `z` position if positional, otherwise its `z` direction (unitary).
                z: LsbRegister(F5_10),
                /// Its `xy` spot (for spotlights) direction (unitary).
                spot_xy: Q1_11x2,
                /// Its `z` spot (for spotlights) direction (unitary).
                spot_z: LsbRegister(Q1_11),
            };

            pub const Config = packed struct(u32) {
                type: Type,
                diffuse_sides: DiffuseSides,
                geometric_factor_enable: BitpackedArray(bool, 2),
                _unused0: u28 = 0,
            };

            pub const Attenuation = extern struct {
                bias: LsbRegister(F7_12),
                scale: LsbRegister(F7_12),
            };

            /// Color factors for primary and secondary colors.
            factors: Factors,
            parameters: Parameters,
            _unknown0: u32,
            config: Config,
            /// Distance attenuation coefficients for the lookup input:
            ///
            /// `DA(clamp(distance * scale + bias, 0.0, 1.0))`
            attenuation: Attenuation,
        };

        light: [8]Light,
        _unknown0: [32]u32,
        /// Scene/Global ambient color.
        ambient: Color,
        _unknown1: u32,
        /// Number of active lights minus one.
        num_lights_min_one: LsbRegister(u3),
        control: Control,
        lut_index: LookupTable.Index,
        disable: LsbRegister(bool),
        _unknown2: u32,
        lut_data: [8]LookupTable.Data,
        lut_input_absolute: LookupTable.Absolute,
        lut_input_select: LookupTable.Select,
        lut_input_scale: LookupTable.Scale,
        _unknown3: [6]u32,
        /// Maps enabled light index to its configuration. e.g: you can have 3 lights enabled but have those 3 lights be 0, 4 and 7 for example.
        light_permutation: BitpackedArray(Light.Id, 8),
    };

    pub const PrimitiveEngine = extern struct {
        pub const Mode = enum(u1) { drawing, config };

        pub const PrimitiveConfig = packed struct(u32) {
            total_vertex_outputs: u4,
            _unused0: u4 = 0,
            topology: PrimitiveTopology,
            _unused1: u6 = 0,
            _unknown0: u1 = 0,
            _unused2: u15 = 0,
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
            variable_geometry: bool = false,
        };

        pub const PipelineConfig2 = packed struct(u32) {
            inputting_vertices_or_draw_arrays: bool = false,
            _unused0: u7 = 0,
            drawing_triangles: bool = false,
            _unused1: u23 = 0,
        };

        pub const GeometryShader = packed struct(u32) {
            pub const Mode = enum(u2) { point, variable, fixed };

            mode: GeometryShader.Mode,
            _unused0: u6 = 0,
            fixed_vertices_minus_one: u4,
            vertices_minus_one: u4,
            uniform_start: u8,
            flag: bool,
            _unused1: u7 = 0,
        };

        pub const Attribute = extern struct {
            pub const Config = extern struct {
                pub const Flags = enum(u1) { array, fixed };

                pub const Low = packed struct(u32) { attributes: BitpackedArray(AttributeFormat, 8) = .splat(.{}) };
                pub const High = packed struct(u32) {
                    remaining_attributes: BitpackedArray(AttributeFormat, 4) = .splat(.{}),
                    flags: BitpackedArray(Flags, 12) = .splat(.array),
                    attributes_end: u4,
                };

                low: Low,
                high: High,

                pub fn setAttribute(config: *Config, index: AttributeIndex, value: AttributeFormat) void {
                    std.mem.writePackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(AttributeFormat), @bitCast(value));
                }

                pub fn getAttribute(config: *Config, index: AttributeIndex) void {
                    return @bitCast(std.mem.readPackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(AttributeFormat)));
                }

                pub fn setFlag(config: *Config, index: AttributeIndex, value: Flags) void {
                    std.mem.writePackedIntNative(u1, std.mem.asBytes(config), (12 * @bitSizeOf(AttributeFormat)) + @intFromEnum(index) * @bitSizeOf(Flags), @bitCast(value));
                }

                pub fn getFlag(config: *Config, index: AttributeIndex) void {
                    return @bitCast(std.mem.readPackedIntNative(u1, std.mem.asBytes(config), (12 * @bitSizeOf(AttributeFormat)) + @intFromEnum(index) * @bitSizeOf(Flags)));
                }
            };

            pub const VertexBuffer = extern struct {
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
                        components: BitpackedArray(ArrayComponent, 8) = .init(.{
                            .attribute_0,
                            .attribute_1,
                            .attribute_2,
                            .attribute_3,
                            .attribute_4,
                            .attribute_5,
                            .attribute_6,
                            .attribute_7,
                        }),
                    };

                    pub const High = packed struct(u32) {
                        components: BitpackedArray(ArrayComponent, 4) = .init(.{
                            .attribute_8,
                            .attribute_9,
                            .attribute_10,
                            .attribute_11,
                        }),

                        bytes_per_vertex: u8,
                        _unused0: u4 = 0,
                        num_components: u4,
                    };

                    low: Low,
                    high: High,

                    pub fn setComponent(config: *VertexBuffer.Config, index: ArrayComponentIndex, value: ArrayComponent) void {
                        std.mem.writePackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(ArrayComponent), @intFromEnum(value));
                    }

                    pub fn getComponent(config: *VertexBuffer.Config, index: ArrayComponentIndex) ArrayComponent {
                        return @enumFromInt(std.mem.readPackedIntNative(u4, std.mem.asBytes(config), @intFromEnum(index) * @bitSizeOf(ArrayComponent)));
                    }
                };

                offset: LsbRegister(u28),
                config: VertexBuffer.Config,
            };

            pub const IndexBuffer = packed struct(u32) {
                offset: u28,
                _unused0: u3 = 0,
                format: IndexFormat,

                pub fn init(base_offset: u28, format: IndexFormat) IndexBuffer {
                    return .{ .offset = base_offset, .format = format };
                }
            };

            base: AlignedPhysicalAddress(.@"16", .@"8"),
            config: Config,
            vertex_buffers: [12]VertexBuffer,
            index_buffer: IndexBuffer,
        };

        pub const FixedAttribute = extern struct {
            pub const Index = packed struct(u32) {
                /// Begin immediate submission of vertex attributes.
                pub const immediate: Index = .{ .index = 0xF };

                index: u4,
                _: u28 = 0,

                pub fn register(input: u4) Index {
                    std.debug.assert(input < 12);
                    return .{ .index = input };
                }
            };

            /// If `Index.immediate` the written `value`s will begin filling shader inputs
            /// and drawing primitives. Otherwise it is an index representing the attribute
            /// whose `value` will be set.
            index: Index,

            /// The value to write to a shader input or attribute.
            value: F7_16x4,
        };

        pub const CommandBuffer = extern struct {
            /// Shifted to the left by 3.
            size: [2]LsbRegister(u20),
            address: [2]AlignedPhysicalAddress(.@"16", .@"8"),
            jump: [2]LsbRegister(Trigger),
        };

        /// Attribute info used when issuing drawcalls via `draw` or `draw_indexed`.
        attributes: Attribute,
        /// The amount of vertices that will be processed by a drawcall.
        draw_vertex_count: u32,
        config: PipelineConfig,
        /// The first index used by drawcalls. Only used in `draw`, ignored by `draw_indexed`.
        draw_first_index: u32,
        _unknown0: [2]u32,
        post_vertex_cache: LsbRegister(u8),
        /// Triggers a non-indexed drawcall, will begin reading from `draw_first_index`
        /// until `draw_vertex_count` vertices are processed.
        draw: LsbRegister(Trigger),
        /// Triggers an indexed drawcall,
        draw_indexed: LsbRegister(Trigger),
        _unknown1: u32,
        clear_post_vertex_cache: LsbRegister(Trigger),
        fixed_attribute: FixedAttribute,
        _unknown2: [2]u32,
        command_buffer: CommandBuffer,
        _unknown3: [4]u32,
        vertex_shader_input_attributes: LsbRegister(u4),
        _unknown4: u32,
        enable_geometry_shader_configuration: LsbRegister(bool),
        mode: LsbRegister(Mode),
        _unknown5: [4]u32,
        vertex_shader_output_map_total_2: LsbRegister(u4),
        _unknown6: [6]u32,
        vertex_shader_output_map_total_1: LsbRegister(u4),
        geometry_shader: GeometryShader,
        config_2: PipelineConfig2,
        geometry_shader_full_vertices_minus_one: LsbRegister(u5),
        _unknown7: u32,
        _unknown8: [8]u32,
        primitive_config: PrimitiveConfig,
        restart_primitive: LsbRegister(Trigger),
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
            output_enabled: BitpackedArray(bool, 16) = .splat(false),
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
                attributes: BitpackedArray(InputRegister, 8) = .init(.{ .v0, .v1, .v2, .v3, .v4, .v5, .v6, .v7 }),
            };

            pub const High = packed struct(u32) {
                remaining_attribute: BitpackedArray(InputRegister, 8) = .init(.{ .v8, .v9, .v10, .v11, .v12, .v13, .v14, .v15 }),
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
            mask: BitpackedArray(bool, 16),
            _unused0: u16 = 0x7FFF,

            pub fn init(mask: BitpackedArray(bool, 16)) BooleanUniformMask {
                return .{ .mask = mask };
            }
        };

        bool_uniforms: BooleanUniformMask,
        int_uniforms: [4][4]u8,
        _unused0: [4]u32,
        input_buffer_config: InputBufferConfig,
        entrypoint: Entry,
        attribute_permutation: AttributePermutation,
        output_map_mask: OutputMask,
        _unused1: u32,
        code_transfer_end: LsbRegister(Trigger),
        float_uniform_index: FloatUniformConfig,
        float_uniform_data: [8]u32,
        _unused2: [2]u32,
        code_transfer_index: LsbRegister(u12),
        code_transfer_data: [8]Instruction,
        _unused3: u32,
        operand_descriptors_index: LsbRegister(u7),
        operand_descriptors_data: [8]OperandDescriptor,
    };

    irq: Interrupt,
    _unused0: [40]u8,
    rasterizer: Rasterizer,
    _unused1: [64]u8,
    texture_units: TextureUnits,
    _unused2: [36]u8,
    procedural_texture_unit: ProceduralTextureUnit,
    _unused3: [32]u8,
    texture_combiners: TextureCombiners,
    _unused4: [8]u8,
    output_merger: OutputMerger,
    fragment_lighting: FragmentLighting,
    _unused5: [152]u8,
    primitive_engine: PrimitiveEngine,
    _unused6: [128]u8,
    geometry_shader: Shader,
    _unused7: [8]u8,
    vertex_shader: Shader,

    comptime {
        std.debug.assert(@offsetOf(Graphics, "irq") == 0x0000);
        std.debug.assert(@offsetOf(Graphics, "rasterizer") == 0x100);
        std.debug.assert(@offsetOf(Graphics, "texture_units") == 0x200);
        std.debug.assert(@offsetOf(Graphics, "procedural_texture_unit") == 0x2A0);
        std.debug.assert(@offsetOf(Graphics, "texture_combiners") == 0x300);
        std.debug.assert(@offsetOf(Graphics, "output_merger") == 0x400);
        std.debug.assert(@offsetOf(Graphics, "fragment_lighting") == 0x500);
        std.debug.assert(@offsetOf(Graphics, "primitive_engine") == 0x800);
        std.debug.assert(@offsetOf(Graphics, "geometry_shader") == 0xA00);
        std.debug.assert(@offsetOf(Graphics, "vertex_shader") == 0xAC0);
    }
};

// TODO: Properly finish this
pub const Registers = extern struct {
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
        pixel_dimensions: [2]u16,
        horizontal_border: [2]u16,
        vertical_border: [2]u16,
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
    ppf: MemoryCopy,
    _unknown8: [0xF5]u32 = @splat(0),
    p3d: Graphics,

    comptime {
        if (builtin.cpu.arch.isArm()) {
            if (@offsetOf(Registers, "timing_control") != 0x50) @compileError(std.fmt.comptimePrint("found 0x{X}", .{@offsetOf(Registers, "timing_control")}));
            if (@offsetOf(Registers, "traffic") != 0x70) @compileError(std.fmt.comptimePrint("found 0x{X}", .{@offsetOf(Registers, "traffic")}));
            if (@offsetOf(Registers, "pdc") != 0x400) @compileError(std.fmt.comptimePrint("found 0x{X}", .{@offsetOf(Registers, "pdc")}));
            if (@offsetOf(Registers, "ppf") != 0xC00) @compileError(std.fmt.comptimePrint("found 0x{X}", .{@offsetOf(Registers, "ppf")}));
            if (@offsetOf(Registers, "p3d") != 0x1000) @compileError(std.fmt.comptimePrint("found 0x{X}", .{@offsetOf(Registers, "p3d")}));
        }
    }
};

comptime {
    if (@sizeOf(Registers.Pdc) != 0x100)
        @compileError(std.fmt.comptimePrint("(@sizeOf(Pdc) == 0x{X}) and 0x{X} != 0x100!", .{ @sizeOf(Registers.Pdc), @sizeOf(Registers.Pdc) }));

    if (@sizeOf(MemoryFill) != 0x10)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryFill) == 0x{X}) and 0x{X} != 0x10!", .{ @sizeOf(MemoryFill), @sizeOf(MemoryFill) }));

    if (@sizeOf(MemoryCopy) != 0x2C)
        @compileError(std.fmt.comptimePrint("(@sizeOf(MemoryCopy) == 0x{X}) and 0x{X} != 0x2C!", .{ @sizeOf(MemoryCopy), @sizeOf(MemoryCopy) }));

    _ = shader;
}

const builtin = @import("builtin");

const std = @import("std");
const zsflt = @import("zsflt");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const Trigger = hardware.Trigger;
const LsbRegister = hardware.LsbRegister;
const MsbRegister = hardware.MsbRegister;
const BitpackedArray = hardware.BitpackedArray;
const AlignedPhysicalAddress = hardware.AlignedPhysicalAddress;
const PhysicalAddress = hardware.PhysicalAddress;

const OperandDescriptor = shader.encoding.OperandDescriptor;
const Instruction = shader.encoding.Instruction;
const FloatConstantRegister = shader.register.Source.Constant;
const InputRegister = shader.register.Source.Input;
