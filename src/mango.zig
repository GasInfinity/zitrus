//! mango is a Vulkan-like abstraction around the PICA200.
//!
//! It is designed to be as lightweight as possible while abstracting all possibly useful hardware features, it means:
//!     - No state caching, static pipeline state is pre-encoded in a hardware command buffer.
//!
//!       This also implies that the application is responsible for proper pipeline usage by minimizing binds and
//!       using dynamic state when possible (which is also NOT cached) thus making the driver as lightweight
//!       as possible.
//!
//!
//! It has a **Zig** and a **C** API, to make the **C** API as painless as possible,
//! structs and enums must be extern-compatible.
//!
//! For more info see the top-level comments of each resource.

// TODO: Have validation-layer behaviour with a toggle at the expense of more checks and more memory usage.
// TODO: Move to a Handle based API. Internal implementation MUST not be exposed as it could be misused.

pub const DeviceSize = enum(u32) {
    whole_size = std.math.maxInt(u32),
    _,

    pub fn size(value: u32) DeviceSize {
        return @enumFromInt(value);
    }
};

pub const Offset2D = extern struct { x: u16, y: u16 };
pub const Extent2D = extern struct { width: u16, height: u16 };
pub const Rect2D = extern struct { offset: Offset2D, extent: Extent2D };
pub const ColorComponentFlags = packed struct(u8) {
    pub const rgba: ColorComponentFlags = .{ .r_enable = true, .g_enable = true, .b_enable = true, .a_enable = true };
    pub const rgb: ColorComponentFlags = .{ .r_enable = true, .g_enable = true, .b_enable = true };
    pub const rg: ColorComponentFlags = .{ .r_enable = true, .g_enable = true };
    pub const r: ColorComponentFlags = .{ .r_enable = true };

    r_enable: bool = false,
    g_enable: bool = false,
    b_enable: bool = false,
    a_enable: bool = false,
    _: u4 = 0,
};

pub const PresentMode = enum(u8) {
    mailbox,
    fifo,
};

/// The 3DS always has 3 heaps.
///     - FCRAM
///     - VRAM (A, 3MiB always)
///     - VRAM (B, 3MiB always)
pub const MemoryHeap = extern struct {
    pub const Flags = packed struct(u8) {
        /// Access of this memory by the GPU *will* be faster
        device_local: bool,
        _: u7 = false,
    };

    size: DeviceSize,
    flags: Flags,
};

pub const MemoryHeapIndex = enum(u8) {
    fcram,
    vram_a,
    vram_b,
};

pub const MemoryType = extern struct {
    pub const Flags = packed struct(u8) {
        /// The memory is the most efficient to be accessed by the GPU. Set if and only if the heap is `device_local`.
        device_local: bool,
        /// The memory can be accessed by the host via `mapMemory` and `unmapMemory`.
        host_visible: bool,
        /// The memory must be flushed and invalidated via `flushMappedMemoryRanges` and `invalidateMappedMemoryRanges`.
        host_cached: bool,
        /// NOTE: Seems it's not supported by the Horizon kernel unless specified in the exheader, see https://github.com/LumaTeam/Luma3DS/issues/2166.
        /// 3DSX homebrew loaded by Luma will have RO (coherent it seems?) VRAM access
        host_coherent: bool,
        _: u4 = 0,
    };

    heap_index: MemoryHeapIndex,
    flags: Flags,
};

pub const MemoryAllocateInfo = extern struct {
    allocation_size: DeviceSize,
    memory_type: u8,
};

pub const MappedMemoryRange = extern struct {
    memory: DeviceMemory,
    offset: DeviceSize,
    size: DeviceSize,
};

pub const Format = enum(u8) {
    undefined,

    r5g6b5_unorm_pack16,
    r5g5b5a1_unorm_pack16,
    r4g4b4a4_unorm_pack16,

    r8_uscaled,
    r8_sscaled,
    r16_sscaled,
    r32_sfloat,

    r8g8_uscaled,
    r8g8_sscaled,
    r16g16_sscaled,
    r32g32_sfloat,

    r8g8b8_uscaled,
    r8g8b8_sscaled,
    r16g16b16_sscaled,
    r32g32b32_sfloat,

    r8g8b8a8_uscaled,
    r8g8b8a8_sscaled,
    r16g16b16a16_sscaled,
    r32g32b32a32_sfloat,

    g8r8_unorm,
    b8g8r8_unorm,
    a8b8g8r8_unorm,

    d16_unorm,
    d24_unorm,
    d24_unorm_s8_uint,
    d24_unorm_i8_unorm,

    i4_unorm,
    a4_unorm,
    i4a4_unorm,

    i8_unorm,
    a8_unorm,
    i8a8_unorm,

    etc1_unorm,
    etc1a4_unorm,

    pub fn nativeColorFormat(fmt: Format) pica.ColorFormat {
        return switch (fmt) {
            .a8b8g8r8_unorm => .abgr8888,
            .b8g8r8_unorm => .bgr888,
            .r5g6b5_unorm_pack16 => .rgb565,
            .r5g5b5a1_unorm_pack16 => .rgba5551,
            .r4g4b4a4_unorm_pack16 => .rgba4444,
            else => unreachable,
        };
    }

    pub fn nativeDepthStencilFormat(fmt: Format) pica.DepthStencilFormat {
        return switch (fmt) {
            .d16_unorm => .d16,
            .d24_unorm => .d24,
            .d24_unorm_s8_uint => .d24_s8,
            else => unreachable,
        };
    }

    pub fn nativeVertexFormat(fmt: Format) pica.AttributeFormat {
        return switch (fmt) {
            .r8_sscaled => .{ .type = .i8, .size = .x },
            .r8_uscaled => .{ .type = .u8, .size = .x },
            .r16_sscaled => .{ .type = .i16, .size = .x },
            .r32_sfloat => .{ .type = .f32, .size = .x },

            .r8g8_sscaled => .{ .type = .i8, .size = .xy },
            .r8g8_uscaled => .{ .type = .u8, .size = .xy },
            .r16g16_sscaled => .{ .type = .i16, .size = .xy },
            .r32g32_sfloat => .{ .type = .f32, .size = .xy },

            .r8g8b8_sscaled => .{ .type = .i8, .size = .xyz },
            .r8g8b8_uscaled => .{ .type = .u8, .size = .xyz },
            .r16g16b16_sscaled => .{ .type = .i16, .size = .xyz },
            .r32g32b32_sfloat => .{ .type = .f32, .size = .xyz },

            .r8g8b8a8_sscaled => .{ .type = .i8, .size = .xyzw },
            .r8g8b8a8_uscaled => .{ .type = .u8, .size = .xyzw },
            .r16g16b16a16_sscaled => .{ .type = .i16, .size = .xyzw },
            .r32g32b32a32_sfloat => .{ .type = .f32, .size = .xyzw },
            else => unreachable,
        };
    }

    pub fn nativeTextureUnitFormat(fmt: Format) pica.TextureUnitFormat {
        return switch (fmt) {
            .g8r8_unorm => .hilo88,
            .a8b8g8r8_unorm => .abgr8888,
            .b8g8r8_unorm => .bgr888,
            .r5g6b5_unorm_pack16 => .rgb565,
            .r5g5b5a1_unorm_pack16 => .rgba5551,
            .r4g4b4a4_unorm_pack16 => .rgba4444,
            .i4_unorm => .i4,
            .a4_unorm => .a4,
            .i4a4_unorm => .ia44,
            .i8_unorm => .i8,
            .a8_unorm => .a8,
            .i8a8_unorm => .ia88,
            .etc1_unorm => .etc1,
            .etc1a4_unorm => .etc1a4,
            else => unreachable,
        };
    }
};

pub const PrimitiveTopology = enum(u8) {
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

    pub fn native(topology: PrimitiveTopology) pica.PrimitiveTopology {
        return switch (topology) {
            .triangle_list => .triangle_list,
            .triangle_strip => .triangle_strip,
            .triangle_fan => .triangle_fan,
            .geometry => .geometry,
        };
    }
};

pub const IndexType = enum(u8) {
    /// Specifies that indices are unsigned 8-bit numbers.
    u8,
    /// Specifies that indices are unsigned 16-bit numbers.
    u16,

    pub fn native(fmt: IndexType) pica.IndexFormat {
        return switch (fmt) {
            .u8 => .u8,
            .u16 => .u16,
        };
    }
};

// TODO: Don't @enumFromInt(@intFromEnum()), use a function.

pub const CompareOperation = enum(u8) {
    never,
    always,
    eq,
    neq,
    lt,
    le,
    gt,
    ge,

    pub fn native(op: CompareOperation) pica.CompareOperation {
        return switch (op) {
            .never => .never,
            .always => .always,
            .eq => .eq,
            .neq => .neq,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
        };
    }
};

pub const StencilOperation = enum(u8) {
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

    pub fn native(op: StencilOperation) pica.StencilOperation {
        return switch (op) {
            .keep => .keep,
            .zero => .zero,
            .replace => .replace,
            .increment => .increment,
            .decrement => .decrement,
            .invert => .invert,
            .increment_wrap => .increment_wrap,
            .decrement_wrap => .decrement_wrap,
        };
    }
};

pub const LogicOperation = enum(u8) {
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

    pub fn native(op: LogicOperation) pica.LogicOperation {
        return switch (op) {
            .clear => .clear,
            .@"and" => .@"and",
            .reverse_and => .reverse_and,
            .copy => .copy,
            .set => .set,
            .copy_inverted => .copy_inverted,
            .nop => .nop,
            .invert => .invert,
            .nand => .nand,
            .@"or" => .@"or",
            .nor => .nor,
            .xor => .xor,
            .equivalent => .equivalent,
            .and_inverted => .and_inverted,
            .or_reverse => .or_reverse,
            .or_inverted => .or_inverted,
        };
    }
};

pub const DepthMode = enum(u8) {
    /// Precision is evenly distributed.
    w_buffer,

    /// Precision is higher close to the near plane.
    z_buffer,

    pub fn native(mode: DepthMode) pica.DepthMapMode {
        return switch (mode) {
            .w_buffer => .w_buffer,
            .z_buffer => .z_buffer,
        };
    }
};

pub const BlendOperation = enum(u8) {
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

    pub fn native(op: BlendOperation) pica.BlendOperation {
        return switch (op) {
            .add => .add,
            .sub => .sub,
            .reverse_sub => .reverse_sub,
            .min => .min,
            .max => .max,
        };
    }
};

pub const BlendFactor = enum(u8) {
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

    pub fn native(factor: BlendFactor) pica.BlendFactor {
        return switch (factor) {
            .zero => .zero,
            .one => .one,
            .src_color => .src_color,
            .one_minus_src_color => .one_minus_src_color,
            .dst_color => .dst_color,
            .one_minus_dst_color => .one_minus_dst_color,
            .src_alpha => .src_alpha,
            .one_minus_src_alpha => .one_minus_src_alpha,
            .dst_alpha => .dst_alpha,
            .one_minus_dst_alpha => .one_minus_dst_alpha,
            .constant_color => .constant_color,
            .one_minus_constant_color => .one_minus_constant_color,
            .constant_alpha => .constant_alpha,
            .one_minus_constant_alpha => .one_minus_constant_alpha,
            .src_alpha_saturate => .src_alpha_saturate,
        };
    }
};

pub const ColorBlendEquation = extern struct {
    src_color_factor: BlendFactor,
    dst_color_factor: BlendFactor,
    color_op: BlendOperation,
    src_alpha_factor: BlendFactor,
    dst_alpha_factor: BlendFactor,
    alpha_op: BlendOperation,

    pub fn native(equation: ColorBlendEquation) pica.Registers.Internal.Framebuffer.BlendConfig {
        return .{
            .color_op = equation.color_op.native(),
            .alpha_op = equation.alpha_op.native(),
            .src_color_factor = equation.src_color_factor.native(),
            .dst_color_factor = equation.dst_color_factor.native(),
            .src_alpha_factor = equation.src_alpha_factor.native(),
            .dst_alpha_factor = equation.dst_alpha_factor.native(),
        };
    }
};

pub const TextureCombinerSource = enum(u8) {
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

    pub fn native(src: TextureCombinerSource) pica.TextureCombinerSource {
        return switch (src) {
            .primary_color => .primary_color,
            .fragment_primary_color => .fragment_primary_color,
            .fragment_secondary_color => .fragment_secondary_color,
            .texture_0 => .texture_0,
            .texture_1 => .texture_1,
            .texture_2 => .texture_2,
            .texture_3 => .texture_3,
            .previous_buffer => .previous_buffer,
            .constant => .constant,
            .previous => .previous,
        };
    }
};

pub const TextureCombinerColorFactor = enum(u8) {
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

    pub fn native(factor: TextureCombinerColorFactor) pica.TextureCombinerColorFactor {
        return switch (factor) {
            .src_color => .src_color,
            .one_minus_src_color => .one_minus_src_color,
            .src_alpha => .src_alpha,
            .one_minus_src_alpha => .one_minus_src_alpha,
            .src_red => .src_red,
            .one_minus_src_red => .one_minus_src_red,
            .src_green => .src_green,
            .one_minus_src_green => .one_minus_src_green,
            .src_blue => .src_blue,
            .one_minus_src_blue => .one_minus_src_blue,
        };
    }
};

pub const TextureCombinerAlphaFactor = enum(u8) {
    src_alpha,
    one_minus_src_alpha,
    src_red,
    one_minus_src_red,
    src_green,
    one_minus_src_green,
    src_blue,
    one_minus_src_blue,

    pub fn native(factor: TextureCombinerAlphaFactor) pica.TextureCombinerAlphaFactor {
        return switch (factor) {
            .src_alpha => .src_alpha,
            .one_minus_src_alpha => .one_minus_src_alpha,
            .src_red => .src_red,
            .one_minus_src_red => .one_minus_src_red,
            .src_green => .src_green,
            .one_minus_src_green => .one_minus_src_green,
            .src_blue => .src_blue,
            .one_minus_src_blue => .one_minus_src_blue,
        };
    }
};

pub const TextureCombinerOperation = enum(u8) {
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

    pub fn native(op: TextureCombinerOperation) pica.TextureCombinerOperation {
        return switch (op) {
            .replace => .replace,
            .modulate => .modulate,
            .add => .add,
            .add_signed => .add_signed,
            .interpolate => .interpolate,
            .subtract => .subtract,
            .dot3_rgb => .dot3_rgb,
            .dot3_rgba => .dot3_rgba,
            .multiply_add => .multiply_add,
            .add_multiply => .add_multiply,
        };
    }
};

pub const TextureCombinerScale = enum(u8) {
    @"1x",
    @"2x",
    @"3x",

    pub fn native(scale: TextureCombinerScale) pica.TextureCombinerScale {
        return switch (scale) {
            .@"1x" => .@"1x",
            .@"2x" => .@"2x",
            .@"3x" => .@"3x",
        };
    }
};

pub const TextureCombinerBufferSource = enum(u8) {
    /// Use previous combiner buffer output as this combiner's buffer input
    previous_buffer,
    /// Use previous combiner output as this combiner's buffer input
    previous,

    pub fn native(buffer_source: TextureCombinerBufferSource) pica.TextureCombinerBufferSource {
        return switch (buffer_source) {
            .previous_buffer => .previous_buffer,
            .previous => .previous,
        };
    }
};

pub const FrontFace = enum(u8) {
    /// Triangles with a positive area are considered to be front-facing.
    ccw,
    /// Triangles with a negative area are considered to be front-facing.
    cw,
};

pub const CullMode = enum(u8) {
    /// No triangles are discarded.
    none,
    /// The front-facing triangles are culled.
    front,
    /// The back-facing triangles are culled.
    back,

    pub fn native(mode: CullMode, front: FrontFace) pica.CullMode {
        return switch (mode) {
            .none => .none,
            .front => switch (front) {
                .ccw => .front_ccw,
                .cw => .back_ccw,
            },
            .back => switch (front) {
                .ccw => .back_ccw,
                .cw => .front_ccw,
            },
        };
    }
};

pub const PipelineBindPoint = enum(u8) {
    graphics,
};

pub const SwapchainCreateInfo = extern struct {
    pub const ImageMemoryInfo = extern struct {
        memory: DeviceMemory,
        memory_offset: DeviceMemory, 
    };

    surface: Surface,
    present_mode: PresentMode,
    image_format: Format,
    image_array_layers: u8,
    image_count: u8,
    image_memory_info: [*]const ImageMemoryInfo,
};

pub const SemaphoreCreateInfo = extern struct {
    initial_value: u64,
};

pub const CommandPoolCreateInfo = extern struct {
    // TODO: Preheat info
};

pub const CommandBufferAllocateInfo = extern struct {
    pool: CommandPool,
    command_buffer_count: u32,
};

pub const BufferCreateInfo = extern struct {
    pub const Usage = packed struct(u8) {
        /// Specifies that the buffer can be used as the source of a transfer operation.
        transfer_src: bool = false,
        /// Specifies that the buffer can be used as the destination of a transfer operation.
        transfer_dst: bool = false,
        /// Specifies that the buffer can be used as an index buffer.
        index_buffer: bool = false,
        /// Specifies that the buffer can be used as a vertex buffer.
        vertex_buffer: bool = false,
        _: u4 = 0,
    };

    size: DeviceSize,
    usage: Usage,
};

pub const ImageCreateInfo = extern struct {
    pub const Type = enum(u8) {
        @"2d",
    };

    pub const Tiling = enum(u8) {
        /// The images are tiled in a PICA200 specific format (8x8 or 32x32 tiles).
        optimal,
        /// The images are linearly stored.
        linear,
    };

    pub const Usage = packed struct(u8) {
        /// Specifies that the image can be used as the source of a transfer operation.
        transfer_src: bool = false,
        /// Specifies that the image can be used as the destination of a transfer operation.
        transfer_dst: bool = false,
        /// Specifies that the image can be used to create an ImageView suitable for binding with a sampler.
        sampled: bool = false,
        /// Specifies that the image can be used to create an ImageView suitable for use as a color attachment.
        color_attachment: bool = false,
        /// Specifies that the image can be used to create an ImageView suitable for use as a depth-stencil attachment.
        depth_stencil_attachment: bool = false,
        /// Specifies that the image can be used to create an ImageView suitable for use as a shadow attachment.
        shadow_attachment: bool = false,
        _: u2 = 0,
    };

    pub const Flags = packed struct(u8) {
        /// Specifies that the image can be used to create an ImageView with a different format from the image.
        mutable_format: bool = false,
        /// Specifies that the image can be used to create an ImageView of type `cube`
        cube_compatible: bool = false,
        _: u6 = 0,
    };

    flags: Flags,
    type: Type,
    tiling: Tiling,
    usage: Usage,
    extent: Extent2D,
    format: Format,
    mip_levels: u8,
    array_layers: u8,
};

pub const ImageViewCreateInfo = extern struct {
    pub const Type = enum(u8) {
        @"2d",
        cube,
    };

    type: Type,
    format: Format,
    image: Image,
    // TODO: subresource range with the mip levels and array layers (for cubemaps)
};

pub const AddressMode = enum(u8) {
    clamp_to_edge,
    clamp_to_border,
    repeat,
    mirrored_repeat,

    pub fn native(address_mode: AddressMode) pica.TextureUnitAddressMode {
        return switch (address_mode) {
            .clamp_to_edge => .clamp_to_edge,
            .clamp_to_border => .clamp_to_border,
            .repeat => .repeat,
            .mirrored_repeat => .mirrored_repeat,
        };
    }
};

pub const Filter = enum(u8) {
    nearest,
    linear,

    pub fn native(filter: Filter) pica.TextureUnitFilter {
        return switch (filter) {
            .nearest => .nearest,
            .linear => .linear,
        };
    }
};

pub const SamplerCreateInfo = extern struct {
    mag_filter: Filter,
    min_filter: Filter,
    mip_filter: Filter,
    address_mode_u: AddressMode,
    address_mode_v: AddressMode,
    lod_bias: f32,
    min_lod: u8,
    max_lod: u8,
    border_color: [4]u8,
};

pub const GraphicsPipelineCreateInfo = extern struct {
    pub const FormatRenderingInfo = extern struct {
        color_attachment_format: Format,
        depth_stencil_attachment_format: Format,
    };

    pub const VertexInputState = extern struct {
        bindings: [*]const VertexInputBindingDescription,
        attributes: [*]const VertexInputAttributeDescription,
        fixed_attributes: [*]const VertexInputFixedAttributeDescription,

        bindings_len: u32,
        attributes_len: u32,
        fixed_attributes_len: u32,

        pub fn init(bindings: []const VertexInputBindingDescription, attributes: []const VertexInputAttributeDescription, fixed_attributes: []const VertexInputFixedAttributeDescription) VertexInputState {
            return .{
                .bindings = bindings.ptr,
                .attributes = attributes.ptr,
                .fixed_attributes = fixed_attributes.ptr,

                .bindings_len = bindings.len,
                .attributes_len = attributes.len,
                .fixed_attributes_len = fixed_attributes.len,
            };
        }
    };

    pub const ShaderStageState = extern struct {
        code: [*]const u8,
        code_len: u32,

        name: [*]const u8,
        name_len: u32,

        pub fn init(code: []const u8, name: []const u8) ShaderStageState {
            return .{
                .code = code.ptr,
                .code_len = code.len,

                .name = name.ptr,
                .name_len = name.len,
            };
        }
    };

    pub const InputAssemblyState = extern struct {
        topology: PrimitiveTopology,
    };

    pub const ViewportState = extern struct {
        scissor: ?*const Scissor,
        viewport: ?*const Viewport,
    };

    pub const RasterizationState = extern struct {
        front_face: FrontFace,
        cull_mode: CullMode,

        depth_mode: DepthMode,
        depth_bias_constant: f32,
    };

    pub const TextureSamplingState = extern struct {
        texture_enable: [4]bool,

        /// Only texture coordinates 2 and 1 are supported
        texture_2_coordinates: TextureCoordinateSource,
        texture_3_coordinates: TextureCoordinateSource,
    };

    pub const LightingState = extern struct {};

    pub const TextureCombinerState = extern struct {
        texture_combiners: [*]const TextureCombiner,
        texture_combiners_len: usize,

        texture_combiner_buffer_sources: [*]const TextureCombiner.BufferSources,
        texture_combiner_buffer_sources_len: usize,

        pub fn init(texture_combiners: []const TextureCombiner, texture_combiner_buffer_sources: []const TextureCombiner.BufferSources) TextureCombinerState {
            return .{
                .texture_combiners = texture_combiners.ptr,
                .texture_combiners_len = texture_combiners.len,

                .texture_combiner_buffer_sources = texture_combiner_buffer_sources.ptr,
                .texture_combiner_buffer_sources_len = texture_combiner_buffer_sources.len,
            };
        }
    };

    pub const AlphaDepthStencilState = extern struct {
        pub const StencilOperationState = extern struct {
            fail_op: StencilOperation,
            pass_op: StencilOperation,
            depth_fail_op: StencilOperation,
            compare_op: CompareOperation,
            compare_mask: u8,
            write_mask: u8,
            reference: u8,
        };

        alpha_test_enable: bool,
        alpha_test_compare_op: CompareOperation,
        alpha_test_reference: u8,

        depth_test_enable: bool,
        depth_write_enable: bool,
        depth_compare_op: CompareOperation,

        stencil_test_enable: bool,
        back_front: StencilOperationState,
    };

    pub const ColorBlendState = extern struct {
        pub const Attachment = extern struct {
            blend_equation: ColorBlendEquation,
            color_write_mask: ColorComponentFlags,
        };

        logic_op_enable: bool,
        logic_op: LogicOperation,

        attachment: Attachment,
        blend_constants: [4]u8,
    };

    pub const DynamicState = packed struct(u32) {
        viewport: bool = false,
        scissor: bool = false,

        depth_mode: bool = false,
        depth_bias_constant: bool = false,

        cull_mode: bool = false,
        front_face: bool = false,

        depth_test_enable: bool = false,
        depth_write_enable: bool = false,
        depth_compare_op: bool = false,

        stencil_compare_mask: bool = false,
        stencil_write_mask: bool = false,
        stencil_reference: bool = false,
        stencil_test_enable: bool = false,
        stencil_test_operation: bool = false,

        logic_op_enable: bool = false,
        logic_op: bool = false,

        blend_equation: bool = false,
        blend_constants: bool = false,

        alpha_test_enable: bool = false,
        alpha_test_compare_op: bool = false,
        alpha_test_reference: bool = false,

        color_write_mask: bool = false,
        primitive_topology: bool = false,

        texture_combiner: bool = false,
        texture_config: bool = false,

        vertex_input: bool = false,
        _: u6 = 0,
    };

    rendering_info: *const FormatRenderingInfo,
    vertex_shader_state: *const ShaderStageState,
    geometry_shader_state: ?*const ShaderStageState,

    vertex_input_state: ?*const VertexInputState,
    input_assembly_state: ?*const InputAssemblyState,
    viewport_state: ?*const ViewportState,
    rasterization_state: ?*const RasterizationState,
    alpha_depth_stencil_state: ?*const AlphaDepthStencilState,
    texture_sampling_state: ?*const TextureSamplingState,
    lighting_state: ?*const LightingState,
    texture_combiner_state: ?*const TextureCombinerState,
    color_blend_state: ?*const ColorBlendState,
    dynamic_state: DynamicState,
};

pub const TextureCoordinateSource = enum(u8) {
    @"0",
    @"1",
    @"2",

    pub fn nativeTexture2(src: TextureCoordinateSource) pica.TextureUnitTexture2Coordinates {
        return switch (src) {
            .@"0" => unreachable,
            .@"1" => .@"1",
            .@"2" => .@"2",
        };
    }

    pub fn nativeTexture3(src: TextureCoordinateSource) pica.TextureUnitTexture3Coordinates {
        return switch (src) {
            .@"0" => .@"0",
            .@"1" => .@"1",
            .@"2" => .@"2",
        };
    }
};

pub const ShaderStage = enum(u8) {
    vertex,
    geometry,
};

pub const Scissor = extern struct {
    pub const Mode = enum(u8) {
        /// The pixels outside the scissor area will be rendered.
        outside,
        /// The pixels inside the scissor area will be rendered.
        inside,

        pub fn native(mode: Mode) pica.ScissorMode {
            return switch (mode) {
                .outside => .outside,
                .inside => .inside,
            };
        }
    };

    rect: Rect2D,
    mode: Mode,

    pub fn outside(rect: Rect2D) Scissor {
        return .{ .rect = rect, .mode = .outside };
    }

    pub fn inside(rect: Rect2D) Scissor {
        return .{ .rect = rect, .mode = .inside };
    }

    pub fn write(scissor: Scissor, queue: *cmd3d.Queue) void {
        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.scissor_config,
            &internal_regs.rasterizer.scissor_start,
            &internal_regs.rasterizer.scissor_end,
        }, .{
            .init(scissor.mode.native()),
            @bitCast(scissor.rect.offset),
            .{ .x = scissor.rect.offset.x + scissor.rect.extent.width - 1, .y = scissor.rect.offset.y + scissor.rect.extent.height - 1 },
        });
    }
};

pub const Viewport = extern struct {
    rect: Rect2D,
    min_depth: f32,
    max_depth: f32,

    pub fn writeViewportParameters(viewport: Viewport, queue: *cmd3d.Queue) void {
        const flt_width: f32 = @floatFromInt(viewport.rect.extent.width);
        const flt_height: f32 = @floatFromInt(viewport.rect.extent.height);

        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.viewport_h_scale,
            &internal_regs.rasterizer.viewport_h_step,
            &internal_regs.rasterizer.viewport_v_scale,
            &internal_regs.rasterizer.viewport_v_step,
        }, .{
            .init(.of(flt_width / 2.0)),
            .init(.of(2.0 / flt_width)),
            .init(.of(flt_height / 2.0)),
            .init(.of(2.0 / flt_height)),
        });

        queue.add(internal_regs, &internal_regs.rasterizer.viewport_xy, .{
            .x = viewport.rect.offset.x,
            .y = viewport.rect.offset.y,
        });
    }
};

pub const VertexAttributeBinding = enum(u8) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };
pub const VertexAttributeLocation = enum(u8) { v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 };

pub const VertexInputFixedAttributeDescription = extern struct {
    value: [4]f32,
    location: VertexAttributeLocation,
};

pub const VertexInputBindingDescription = extern struct {
    stride: u8,
};

pub const VertexInputAttributeDescription = extern struct {
    location: VertexAttributeLocation,
    binding: VertexAttributeBinding,
    format: Format,
    /// TODO: This has special requirements. Document them
    offset: u8,
};

pub const BufferCopy = extern struct {
    src_offset: DeviceSize,
    dst_offset: DeviceSize,
    size: DeviceSize,
};

pub const BufferImageCopy = extern struct {
    pub const Flags = packed struct(u8) {
        /// Directly copies the data without performing linear to optimal tiling.
        memcpy: bool = false,
        _: u7 = 0,
    };

    src_offset: DeviceSize,
    flags: Flags,
};

pub const SemaphoreSignalInfo = extern struct {
    value: u64,
    semaphore: Semaphore,
};

pub const SemaphoreWaitInfo = extern struct {
    semaphore_count: u32,
    semaphores: [*]const Semaphore,
    values: [*]const u64,
};

pub const MultiDrawInfo = extern struct {
    first_vertex: u32,
    vertex_count: u32,
};

pub const MultiDrawIndexedInfo = extern struct {
    first_index: u32,
    index_count: u32,
    vertex_offset: i32,
};

pub const RenderingInfo = extern struct {
    color_attachment: ImageView,
    depth_stencil_attachment: ImageView,
};

pub const CombinedImageSampler = extern struct {
    image: ImageView,
    sampler: Sampler,
};

pub const TextureCombiner = extern struct {
    pub const BufferSources = extern struct {
        color_buffer_src: TextureCombinerBufferSource,
        alpha_buffer_src: TextureCombinerBufferSource,
    };

    pub const previous: TextureCombiner = .{
        .color_src = @splat(.previous),
        .alpha_src = @splat(.previous),
        .color_factor = @splat(.src_color),
        .alpha_factor = @splat(.src_alpha),
        .color_op = .replace,
        .alpha_op = .replace,
        .color_scale = .@"1x",
        .alpha_scale = .@"1x",
        .constant = @splat(0),
    };

    color_src: [3]TextureCombinerSource,
    alpha_src: [3]TextureCombinerSource,
    color_factor: [3]TextureCombinerColorFactor,
    alpha_factor: [3]TextureCombinerAlphaFactor,
    color_op: TextureCombinerOperation,
    alpha_op: TextureCombinerOperation,

    color_scale: TextureCombinerScale,
    alpha_scale: TextureCombinerScale,

    constant: [4]u8,

    pub fn native(combiner: TextureCombiner) pica.Registers.Internal.TextureCombiners.Combiner {
        return .{
            .sources = .{
                .color_src_0 = combiner.color_src[0].native(),
                .color_src_1 = combiner.color_src[1].native(),
                .color_src_2 = combiner.color_src[2].native(),
                .alpha_src_0 = combiner.alpha_src[0].native(),
                .alpha_src_1 = combiner.alpha_src[1].native(),
                .alpha_src_2 = combiner.alpha_src[2].native(),
            },
            .factors = .{
                .color_factor_0 = combiner.color_factor[0].native(),
                .color_factor_1 = combiner.color_factor[1].native(),
                .color_factor_2 = combiner.color_factor[2].native(),
                .alpha_factor_0 = combiner.alpha_factor[0].native(),
                .alpha_factor_1 = combiner.alpha_factor[1].native(),
                .alpha_factor_2 = combiner.alpha_factor[2].native(),
            },
            .operations = .{
                .color_op = combiner.color_op.native(),
                .alpha_op = combiner.alpha_op.native(),
            },
            .color = combiner.constant,
            .scales = .{
                .color_scale = combiner.color_scale.native(),
                .alpha_scale = combiner.alpha_scale.native(),
            },
        };
    }
};

pub const SubmitInfo = extern struct {
    command_buffers_len: usize,
    command_buffers: [*]const CommandBuffer,

    pub fn init(command_buffers: []const CommandBuffer) SubmitInfo {
        return .{
            .command_buffers = command_buffers.ptr,
            .command_buffers_len = command_buffers.len,
        };
    }
};

pub const PresentInfo = extern struct {
    pub const Flags = packed struct(u8) {
        /// Ignore the array layers of presented swapchain images and present it as a non-stereoscopic image.
        ignore_stereoscopic: bool = false,
        _: u7 = 0,
    };

    swapchains_len: usize,
    swapchains: [*]const Swapchain,
    image_indices: [*]const u8,
    flags: Flags,
};

pub const Device = backend.Device;
pub const DeviceMemory = backend.DeviceMemory.Handle;
pub const Semaphore = backend.Semaphore.Handle;
pub const Buffer = backend.Buffer.Handle;
pub const Image = backend.Image.Handle;
pub const ImageView = backend.ImageView.Handle;
pub const Pipeline = backend.Pipeline.Handle;
pub const CommandPool = backend.CommandPool.Handle;
pub const CommandBuffer = backend.CommandBuffer.Handle;
pub const Sampler = backend.Sampler.Handle;
pub const Surface = backend.Surface.Handle;
pub const Swapchain = backend.Swapchain.Handle;

// NOTE: This is not pub as implementation details should not be exposed.
const backend = @import("mango/backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;
const internal_regs = &zitrus.memory.arm11.gpu.internal;
