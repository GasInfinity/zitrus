pub const Dirty = packed struct(u32) {
    primitive_topology: bool = false,
    cull_mode: bool = false,
    depth_map_mode: bool = false,
    depth_map_parameters: bool = false,
    viewport_parameters: bool = false,
    scissor_parameters: bool = false,
    depth_test_masks: bool = false,
    color_operation: bool = false,
    blend_config: bool = false,
    blend_constants: bool = false,
    logic_operation: bool = false,
    alpha_test: bool = false,
    stencil_test: bool = false,
    stencil_operation: bool = false,
    texture_update_buffer: bool = false,
    texture_combiners: bool = false,
    texture_config: bool = false,
    _: u15 = 0,
};

pub const DepthParameters = struct {
    min_depth: f32,
    max_depth: f32,
    constant: f32 = 0,
};

pub const Viewport = packed struct {
    x: u10,
    y: u10,
    width_minus_one: u10,
    height_minus_one: u10,
};

pub const Scissor = packed struct {
    x: u10,
    y: u10,
    end_x: u10,
    end_y: u10,
};

pub const Combiners = struct {
    pub const NativeState = pica.Registers.Internal.TextureCombiners.UpdateBuffer;
    pub const NativeCombiner = pica.Registers.Internal.TextureCombiners.Combiner;

    combiner_state: [6]NativeCombiner,
    update_buffer: NativeState,
};

pub const Misc = packed struct {
    primitive_topology: pica.PrimitiveTopology,
    cull_mode_ccw: pica.CullMode,
    is_front_ccw: bool,
    depth_mode: pica.DepthMapMode,
    is_scissor_inside: bool,
    depth_test_enable: bool,
    depth_test_op: pica.CompareOperation,
    depth_write_enable: bool,

    color_r_enable: bool,
    color_g_enable: bool,
    color_b_enable: bool,
    color_a_enable: bool,

    logic_op_enable: bool,
    logic_op: pica.LogicOperation,

    alpha_test_enable: bool,
    alpha_test_op: pica.CompareOperation,
    alpha_test_reference: u8,

    texture_0_enable: bool,
    texture_1_enable: bool,
    texture_2_enable: bool,
    texture_3_enable: bool,

    texture_2_coordinates: pica.TextureUnitTexture2Coordinates,
    texture_3_coordinates: pica.TextureUnitTexture3Coordinates,
};

pub const Stencil = struct {
    pub const State = packed struct {
        enable: bool,
        op: pica.CompareOperation,
        fail_op: pica.StencilOperation,
        pass_op: pica.StencilOperation,
        depth_fail_op: pica.StencilOperation,
    };

    state: State,
    compare_mask: u8,
    write_mask: u8,
    reference: u8,
};

const GpuBlendConfig = pica.Registers.Internal.Framebuffer.BlendConfig;

pub const empty: GraphicsState = .{
    .misc = undefined,
    .stencil = undefined,
    .blend_config = undefined,
    .blend_constants = undefined,
    .depth_map_parameters = undefined,
    .viewport = undefined,
    .scissor = undefined,
    .combiners = undefined,
    .vtx_input = undefined,
    .dirty = .{},
};

misc: Misc = undefined,
stencil: Stencil = undefined,
blend_config: GpuBlendConfig = undefined,
blend_constants: [4]u8 = undefined,
depth_map_parameters: DepthParameters = undefined,
viewport: Viewport = undefined,
scissor: Scissor = undefined,
combiners: Combiners = undefined,
vtx_input: VertexInputLayout = undefined,
dirty: Dirty = .{},

pub fn setDepthMode(state: *GraphicsState, mode: mango.DepthMode) void {
    state.misc.depth_mode = mode.native();
    state.dirty.depth_map_mode = true;
}

pub fn setCullMode(state: *GraphicsState, cull_mode: mango.CullMode) void {
    const native_cull_mode_ccw = cull_mode.native(.ccw);

    state.misc.cull_mode_ccw = native_cull_mode_ccw;
    state.dirty.cull_mode = true;
}

pub fn setFrontFace(state: *GraphicsState, front_face: mango.FrontFace) void {
    const front_ccw = switch (front_face) {
        .ccw => true,
        .cw => false,
    };

    state.misc.is_front_ccw = front_ccw;
    state.dirty.cull_mode = true;
}

pub fn setPrimitiveTopology(state: *GraphicsState, primitive_topology: mango.PrimitiveTopology) void {
    const native_primitive_topology = primitive_topology.native();

    state.misc.primitive_topology = native_primitive_topology;
    state.dirty.primitive_topology = true;
}

pub fn setViewport(state: *GraphicsState, viewport: *const mango.Viewport) void {
    const viewport_x: u10 = @intCast(viewport.rect.offset.x);
    const viewport_y: u10 = @intCast(viewport.rect.offset.y);
    const viewport_width_minus_one: u10 = @intCast(viewport.rect.extent.width - 1);
    const viewport_height_minus_one: u10 = @intCast(viewport.rect.extent.height - 1);

    state.viewport.x = viewport_x;
    state.viewport.y = viewport_y;
    state.viewport.width_minus_one = viewport_width_minus_one;
    state.viewport.height_minus_one = viewport_height_minus_one;
    state.dirty.viewport_parameters = true;

    state.depth_map_parameters.min_depth = viewport.min_depth;
    state.depth_map_parameters.max_depth = viewport.max_depth;
    state.dirty.depth_map_parameters = true;
}

pub fn setScissor(state: *GraphicsState, scissor: *const mango.Scissor) void {
    const new_scissor: GraphicsState.Scissor = .{
        .x = @intCast(scissor.rect.offset.x),
        .y = @intCast(scissor.rect.offset.y),
        .end_x = @intCast(scissor.rect.offset.x + @as(u10, @intCast(scissor.rect.extent.width - 1))),
        .end_y = @intCast(scissor.rect.offset.y + @as(u10, @intCast(scissor.rect.extent.height - 1))),
    };

    const is_inside = switch (scissor.mode) {
        .inside => true,
        .outside => false,
    };

    state.scissor = new_scissor;
    state.misc.is_scissor_inside = is_inside;
    state.dirty.scissor_parameters = true;
}

pub fn setTextureCombiners(state: *GraphicsState, texture_combiners_len: usize, texture_combiners: [*]const mango.TextureCombiner, texture_combiner_buffer_sources_len: usize, texture_combiner_buffer_sources: [*]const mango.TextureCombiner.BufferSources) void {
    const dyn_combiners = &state.combiners;

    const combiners = texture_combiners[0..texture_combiners_len];
    const combiner_buffer_sources = texture_combiner_buffer_sources[0..texture_combiner_buffer_sources_len];

    std.debug.assert(combiners.len > 0 and combiners.len <= 6);
    std.debug.assert(combiners.len == 1 or (combiners.len > 1 and combiner_buffer_sources.len == combiners.len - 1));

    dyn_combiners.update_buffer.z_flip = false;
    dyn_combiners.update_buffer.shading_density_source = .plain;
    dyn_combiners.update_buffer.fog_mode = .disabled;

    for (combiner_buffer_sources, 0..) |buffer_sources, index| {
        dyn_combiners.update_buffer.setColorBufferSource(@enumFromInt(index), buffer_sources.color_buffer_src.native());
        dyn_combiners.update_buffer.setAlphaBufferSource(@enumFromInt(index), buffer_sources.alpha_buffer_src.native());
    }

    for (combiners, 0..) |combiner, i| {
        dyn_combiners.combiner_state[i] = combiner.native();
    }

    for (combiners.len..dyn_combiners.combiner_state.len) |i| {
        dyn_combiners.combiner_state[i] = mango.TextureCombiner.previous.native();
    }

    state.dirty.texture_update_buffer = true;
    state.dirty.texture_combiners = true;
}

pub fn setBlendEquation(state: *GraphicsState, blend_equation: *const mango.ColorBlendEquation) void {
    const native_blend_config = blend_equation.native();

    state.blend_config = native_blend_config;
    state.dirty.blend_config = true;
}

pub fn setBlendConstants(state: *GraphicsState, blend_constants: *const [4]u8) void {
    state.blend_constants = blend_constants.*;
    state.dirty.blend_constants = true;
}

pub fn setColorWriteMask(state: *GraphicsState, write_mask: mango.ColorComponentFlags) void {
    state.misc.color_r_enable = write_mask.r_enable;
    state.misc.color_g_enable = write_mask.g_enable;
    state.misc.color_b_enable = write_mask.b_enable;
    state.misc.color_a_enable = write_mask.a_enable;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthTestEnable(state: *GraphicsState, enable: bool) void {
    state.misc.depth_test_enable = enable;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthCompareOp(state: *GraphicsState, op: mango.CompareOperation) void {
    const native_op = op.native();

    state.misc.depth_test_op = native_op;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthWriteEnable(state: *GraphicsState, enable: bool) void {
    state.misc.depth_write_enable = enable;
    state.dirty.depth_test_masks = true;
}

pub fn setLogicOpEnable(state: *GraphicsState, enable: bool) void {
    state.misc.logic_op_enable = enable;
    state.dirty.color_operation = true;
}

pub fn setLogicOp(state: *GraphicsState, logic_op: mango.LogicOperation) void {
    const native_logic_op = logic_op.native();

    state.misc.logic_op = native_logic_op;
    state.dirty.logic_operation = true;
}

pub fn setAlphaTestEnable(state: *GraphicsState, enable: bool) void {
    state.misc.alpha_test_enable = enable;
    state.dirty.alpha_test = true;
}

pub fn setAlphaTestCompareOp(state: *GraphicsState, compare_op: mango.CompareOperation) void {
    const native = compare_op.native();

    state.misc.alpha_test_op = native;
    state.dirty.alpha_test = true;
}

pub fn setAlphaTestReference(state: *GraphicsState, reference: u8) void {
    state.alpha_test_reference = reference;
    state.dirty.alpha_test = true;
}

pub fn setStencilEnable(state: *GraphicsState, enable: bool) void {
    state.stencil.state.enable = enable;
    state.dirty.stencil_test = true;
}

pub fn setStencilOp(state: *GraphicsState, fail_op: mango.StencilOperation, pass_op: mango.StencilOperation, depth_fail_op: mango.StencilOperation, op: mango.CompareOperation) void {
    const native_fail = fail_op.native();
    const native_pass = pass_op.native();
    const native_depth_fail = depth_fail_op.native();
    const native_op = op.native();

    state.stencil.state.op = native_op;
    state.stencil.state.fail_op = native_fail;
    state.stencil.state.pass_op = native_pass;
    state.stencil.state.depth_fail_op = native_depth_fail;
    state.dirty.stencil_test = true;
    state.dirty.stencil_operation = true;
}

pub fn setStencilCompareMask(state: *GraphicsState, compare_mask: u8) void {
    state.stencil.compare_mask = compare_mask;
    state.dirty.stencil_test = true;
}

pub fn setStencilWriteMask(state: *GraphicsState, write_mask: u8) void {
    state.stencil.write_mask = write_mask;
    state.dirty.stencil_test = true;
}

pub fn setStencilReference(state: *GraphicsState, reference: u8) void {
    state.stencil.reference = reference;
    state.dirty.stencil_test = true;
}

pub fn setTextureEnable(state: *GraphicsState, enable: *const [4]bool) void {
    state.misc.texture_0_enable, state.misc.texture_1_enable, state.misc.texture_2_enable, state.misc.texture_3_enable = enable.*;
    state.dirty.texture_config = true;
}

pub fn setTextureCoordinates(state: *GraphicsState, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
    state.misc.texture_2_coordinates = texture_2_coordinates.nativeTexture2();
    state.misc.texture_3_coordinates = texture_3_coordinates.nativeTexture3();
    state.dirty.texture_config = true;
}

pub fn emitDirty(state: *GraphicsState, queue: *cmd3d.Queue) void {
    if (state.dirty.cull_mode) {
        const cull_mode_ccw = state.misc.cull_mode_ccw;
        const is_front_ccw = state.misc.is_front_ccw;

        queue.add(internal_regs, &internal_regs.rasterizer.faceculling_config, .init(if (is_front_ccw)
            cull_mode_ccw
        else switch (cull_mode_ccw) {
            .none => .none,
            .front_ccw => .back_ccw,
            .back_ccw => .front_ccw,
        }));
    }

    if (state.dirty.viewport_parameters) {
        const flt_width = @as(f32, @floatFromInt(state.viewport.width_minus_one)) + 1.0;
        const flt_height = @as(f32, @floatFromInt(state.viewport.height_minus_one)) + 1.0;

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
            .x = state.viewport.x,
            .y = state.viewport.y,
        });
    }

    if (state.dirty.scissor_parameters) {
        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.scissor_config,
            &internal_regs.rasterizer.scissor_start,
            &internal_regs.rasterizer.scissor_end,
        }, .{
            .init(if (state.misc.is_scissor_inside) .inside else .outside),
            .{ .x = state.scissor.x, .y = state.scissor.y },
            .{ .x = state.scissor.end_x, .y = state.scissor.end_y },
        });
    }

    if (state.dirty.depth_map_mode) {
        queue.add(internal_regs, &internal_regs.rasterizer.depth_map_mode, .init(state.misc.depth_mode));
    }

    if (state.dirty.depth_map_parameters) {
        const depth_map_scale = (state.depth_map_parameters.min_depth - state.depth_map_parameters.max_depth);
        const depth_map_offset = state.depth_map_parameters.min_depth + state.depth_map_parameters.constant;

        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.depth_map_scale,
            &internal_regs.rasterizer.depth_map_offset,
        }, .{
            .init(.of(depth_map_scale)),
            .init(.of(depth_map_offset)),
        });
    }

    if (state.dirty.primitive_topology) {
        const primitive_topology = state.misc.primitive_topology;

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{
            .total_vertex_outputs = 0, // NOTE: Ignored by mask
            .topology = primitive_topology,
        }, 0b0010);

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config, .{
            .geometry_shader_usage = .disabled, // NOTE: Ignored by mask
            .drawing_triangles = primitive_topology == .triangle_list,
            .use_reserved_geometry_subdivision = false, // NOTE: Ignored by mask
        }, 0b0010);

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{
            .drawing_triangles = primitive_topology == .triangle_list, // NOTE: Ignored by mask
        }, 0b0010);
    }

    if (state.dirty.color_operation) {
        queue.addMasked(internal_regs, &internal_regs.framebuffer.color_operation, .{
            .fragment_operation = .default, // NOTE: Ignored by mask
            .mode = if (state.misc.logic_op_enable) .logic else .blend,
        }, 0b0010);
    }

    if (state.dirty.logic_operation) {
        queue.add(internal_regs, &internal_regs.framebuffer.logic_operation, .init(state.misc.logic_op));
    }

    if (state.dirty.depth_test_masks) {
        queue.add(internal_regs, &internal_regs.framebuffer.depth_color_mask, .{
            .enable_depth_test = state.misc.depth_test_enable,
            .depth_op = state.misc.depth_test_op,
            .r_write_enable = state.misc.color_r_enable,
            .g_write_enable = state.misc.color_g_enable,
            .b_write_enable = state.misc.color_b_enable,
            .a_write_enable = state.misc.color_a_enable,
            .depth_write_enable = state.misc.depth_test_enable and state.misc.depth_write_enable,
        });
    }

    if (state.dirty.blend_config) {
        queue.add(internal_regs, &internal_regs.framebuffer.blend_config, state.blend_config);
    }

    if (state.dirty.blend_constants) {
        queue.add(internal_regs, &internal_regs.framebuffer.blend_color, state.blend_constants);
    }

    if (state.dirty.alpha_test) {
        queue.add(internal_regs, &internal_regs.framebuffer.alpha_test, .{
            .enable = state.misc.alpha_test_enable,
            .op = state.misc.alpha_test_op,
            .reference = state.misc.alpha_test_reference,
        });
    }

    if (state.dirty.stencil_test) {
        queue.add(internal_regs, &internal_regs.framebuffer.stencil_test, .{
            .enable = state.stencil.state.enable,
            .op = state.stencil.state.op,
            .compare_mask = state.stencil.compare_mask,
            .reference = state.stencil.reference,
            .write_mask = state.stencil.write_mask,
        });
    }

    if (state.dirty.stencil_operation) {
        queue.add(internal_regs, &internal_regs.framebuffer.stencil_operation, .{
            .fail_op = state.stencil.state.fail_op,
            .depth_fail_op = state.stencil.state.depth_fail_op,
            .pass_op = state.stencil.state.pass_op,
        });
    }

    if (state.dirty.texture_update_buffer) {
        queue.add(internal_regs, &internal_regs.texture_combiners.update_buffer, state.combiners.update_buffer);
    }

    if (state.dirty.texture_combiners) {
        inline for (0..6) |i| {
            const current_combiner_reg = switch (i) {
                0 => &internal_regs.texture_combiners.texture_combiner_0,
                1 => &internal_regs.texture_combiners.texture_combiner_1,
                2 => &internal_regs.texture_combiners.texture_combiner_2,
                3 => &internal_regs.texture_combiners.texture_combiner_3,
                4 => &internal_regs.texture_combiners.texture_combiner_4,
                5 => &internal_regs.texture_combiners.texture_combiner_5,
                else => unreachable,
            };

            const defined_combiner = state.combiners.combiner_state[i];

            queue.addIncremental(internal_regs, .{
                &current_combiner_reg.sources,
                &current_combiner_reg.factors,
                &current_combiner_reg.operations,
                &current_combiner_reg.color,
                &current_combiner_reg.scales,
            }, .{
                defined_combiner.sources,
                defined_combiner.factors,
                defined_combiner.operations,
                defined_combiner.color,
                defined_combiner.scales,
            });
        }
    }

    if (state.dirty.texture_config) {
        queue.add(internal_regs, &internal_regs.texturing.config, .{
            .texture_0_enabled = state.misc.texture_0_enable,
            .texture_1_enabled = state.misc.texture_1_enable,
            .texture_2_enabled = state.misc.texture_2_enable,
            .texture_3_coordinates = state.misc.texture_3_coordinates,
            .texture_3_enabled = state.misc.texture_3_enable,
            .texture_2_coordinates = state.misc.texture_2_coordinates,
            .clear_texture_cache = false,
        });
    }

    state.dirty = .{};
}

const GraphicsState = @This();

const backend = @import("backend.zig");
const VertexInputLayout = backend.VertexInputLayout;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
