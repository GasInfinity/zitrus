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

/// All index / vertex buffers provided to the gpu are relative to this address.
pub const global_attribute_buffer_base: zitrus.PhysicalAddress = .fromAddress(zitrus.memory.arm11.vram_begin);

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
    _: u4 = 0
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
    
    pub fn nativeColorFormat(fmt: Format) gpu.ColorFormat {
        return switch (fmt) {
            .a8b8g8r8_unorm => .abgr8888,
            .b8g8r8_unorm => .bgr888,
            .r5g6b5_unorm_pack16 => .rgb565,
            .r5g5b5a1_unorm_pack16 => .rgba5551,
            .r4g4b4a4_unorm_pack16 => .rgba4444,
            else => unreachable,
        };
    }

    pub fn nativeDepthStencilFormat(fmt: Format) gpu.DepthStencilFormat {
        return switch (fmt) {
            .d16_unorm => .d16,
            .d24_unorm => .d24,
            .d24_unorm_s8_uint => .d24_s8,
            else => unreachable,
        };
    }

    pub fn nativeVertexFormat(fmt: Format) gpu.AttributeFormat {
        return switch(fmt) {
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

    pub fn nativeTextureUnitFormat(fmt: Format) gpu.TextureUnitFormat {
        return switch (fmt) {
            .g8r8_unorm => .hilo88,
            .a8b8g8r8_unorm => .abgr8888,
            .b8g8r8_unorm => .bgr8888,
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

    pub fn native(topology: PrimitiveTopology) gpu.PrimitiveTopology {
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

    pub fn native(fmt: IndexType) gpu.IndexFormat {
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
};

pub const DepthMode = enum(u8) {
    /// Precision is evenly distributed.
    w_buffer,

    /// Precision is higher close to the near plane.
    z_buffer,

    pub fn native(mode: DepthMode) gpu.DepthMapMode {
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
};

pub const TextureCombinerColorFactor = enum(u8) {
    src_color,
    one_minus_src_color,
    source_alpha,
    one_minus_src_alpha,
    src_red,
    one_minus_src_red,
    source_green = 8,
    one_minus_src_green,
    src_blue = 12,
    one_minus_src_blue,
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
};

pub const TextureCombinerScale = enum(u8) {
    @"1x",
    @"2x",
    @"3x",
};

pub const TextureCombinerBufferSource = enum(u8) {
    /// Use previous combiner buffer output as this combiner's buffer input
    previous_buffer,
    /// Use previous combiner output as this combiner's buffer input 
    previous,
};

pub const VertexAttributeBinding = enum(u8) { @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11" };
pub const VertexAttributeLocation = enum(u8) { v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 };

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

    pub fn native(mode: CullMode, front: FrontFace) gpu.CullMode {
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

        pub fn native(mode: Mode) gpu.ScissorMode {
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

pub const TextureCombiner = extern struct {
    pub const BufferSources = extern struct {
        color_buffer_src: TextureCombinerBufferSource,
        alpha_buffer_src: TextureCombinerBufferSource,     
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
};

// TODO: Make this interface a lot better for C interop
pub const AllocationCallbacks = extern struct {
    ctx: *anyopaque,
    raw_alloc: fn(ctx: *anyopaque, len: usize, alignment: usize, ret_addr: usize) callconv(.c) ?[*]u8,
    raw_remap: fn(ctx: *anyopaque, memory: [*]u8, memory_len: usize, alignment: usize, new_len: usize, ret_addr: usize) callconv(.c) ?[*]u8,
    raw_free: fn(ctx: *anyopaque, memory: [*]u8, memory_len: usize, alignment: usize, ret_addr: usize) callconv(.c) void,

    pub fn allocator(callbacks: *AllocationCallbacks) std.mem.Allocator {
        return .{
            .ptr = callbacks,
            .vtable = .{
                .alloc = &AllocationCallbacks.alloc,
                .remap = &AllocationCallbacks.remap,
                .resize = &std.mem.Allocator.noResize,
                .free = &AllocationCallbacks.free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const callbacks: *AllocationCallbacks = @alignCast(@ptrCast(ctx));
        return callbacks.raw_alloc(callbacks.ctx, len, alignment.toByteUnits(), ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const callbacks: *AllocationCallbacks = @alignCast(@ptrCast(ctx));
        return callbacks.raw_remap(callbacks.ctx, memory.ptr, memory.len, alignment.toByteUnits(), new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const callbacks: *AllocationCallbacks = @alignCast(@ptrCast(ctx));
        return callbacks.raw_remap(callbacks.ctx, memory.ptr, memory.len, alignment.toByteUnits(), ret_addr);
    }
};

pub const Device = @import("mango/Device.zig");
pub const DeviceMemory = @import("mango/DeviceMemory.zig");
pub const Image = @import("mango/Image.zig");
pub const ImageView = @import("mango/ImageView.zig");
pub const Buffer = @import("mango/Buffer.zig");
pub const Pipeline = @import("mango/Pipeline.zig");
pub const CommandBuffer = @import("mango/CommandBuffer.zig");
pub const Sampler = @import("mango/Sampler.zig");
pub const Swapchain = @import("mango/Swapchain.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const cmd3d = gpu.cmd3d;
const internal_regs = &zitrus.memory.arm11.gpu.internal;
