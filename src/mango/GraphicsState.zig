pub const Dirty = packed struct(u64) {
    vertex_shader: bool = false,
    vertex_shader_code: bool = false,
    geometry_shader: bool = false,
    geometry_shader_code: bool = false,
    primitive_topology: bool = false,
    cull_mode: bool = false,
    depth_map_mode: bool = false,
    depth_map_parameters: bool = false,
    viewport_parameters: bool = false,
    scissor_parameters: bool = false,
    depth_test_masks: bool = false,
    logic_blend_mode: bool = false,
    blend_config: bool = false,
    blend_constants: bool = false,
    logic_operation: bool = false,
    alpha_test: bool = false,
    stencil_config: bool = false,
    stencil_operation: bool = false,
    combiners_config: bool = false,
    combiners: hardware.BitpackedArray(bool, 6) = .splat(false),
    vertex_input_layout: bool = false,
    texture_config: bool = false,
    lighting_enable: bool = false,
    light_environment_control: bool = false,
    light_environment_input: bool = false,
    light_environment_scale: bool = false,
    light_environment_absolute: bool = false,
    light_luts: hardware.BitpackedArray(bool, 6) = .splat(false),
    _: u26 = 0,
};

pub const DepthParameters = struct {
    min_depth: f32,
    max_depth: f32,
    constant: f32 = 0,
};

pub const Viewport = packed struct(u40) {
    x: u10,
    y: u10,
    width_minus_one: u10,
    height_minus_one: u10,
};

pub const Scissor = packed struct(u40) {
    x: u10,
    y: u10,
    end_x: u10,
    end_y: u10,
};

pub const Misc = packed struct {
    primitive_topology: pica.PrimitiveTopology,
    cull_mode_ccw: pica.CullMode,
    is_front_ccw: bool,
    depth_mode: Graphics.Rasterizer.DepthMap.Mode,
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

    lighting_enable: bool,

    alpha_test_enable: bool,
    alpha_test_op: pica.CompareOperation,
    alpha_test_reference: u8,

    texture_2_coordinates: pica.TextureUnitTexture2Coordinates,
    texture_3_coordinates: pica.TextureUnitTexture3Coordinates,
};

pub const Stencil = struct {
    pub const empty: Stencil = .{ .state = std.mem.zeroes(State), .compare_mask = undefined, .write_mask = undefined, .reference = undefined };

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

pub const LightEnvironment = struct {
    control: FragmentLighting.Control,
    lut_input_select: FragmentLighting.LookupTable.Select,
    lut_input_abs: FragmentLighting.LookupTable.Absolute,
    lut_input_scale: FragmentLighting.LookupTable.Scale,
    // d0, d1, rr, rg, rb, fr. DA and SP are set per-light.
    luts: [6]mango.LightLookupTable,
};

pub const Check = struct {
    pub const Set = packed struct {
        cull_mode: bool = false,
        front_face: bool = false,
        primitive_topology: bool = false,
        viewport: bool = false,
        scissor: bool = false,
        texture_combiners: bool = false,
        blend_equation: bool = false,
        blend_constants: bool = false,
        color_write_mask: bool = false,
        depth_test_enable: bool = false,
        depth_write_enable: bool = false,
        depth_compare_op: bool = false,
        depth_bias: bool = false,
        depth_mode: bool = false,
        logic_op_enable: bool = false,
        logic_op: bool = false,
        vertex_input: bool = false,
        alpha_test_enable: bool = false,
        alpha_test_op: bool = false,
        alpha_test_reference: bool = false,
        stencil_test_enable: bool = false,
        lighting_enable: bool = false,
    };

    set: Set = .{},
};

pub const empty: GraphicsState = .{
    .misc = std.mem.zeroes(Misc),
    .stencil = .empty,
    // NOTE: Always modified as a whole, can be `undefined`.
    .blend_config = undefined,
    .blend_constants = undefined,
    .depth_map_parameters = undefined,
    // NOTE: Always modified as a whole, can be `undefined`.
    .viewport = undefined,
    // NOTE: Always modified as a whole, can be `undefined`.
    .scissor = undefined,
    .combiners = undefined,
    // NOTE: Always modified as a whole, can be `undefined`.
    .vtx_input = undefined,
    .light_environment = undefined,
    .vertex_shader = null,
    .geometry_shader = null,
    .dirty = .{},
};

check: validation.Data(Check) = validation.init(Check, .{}),

misc: Misc,
stencil: Stencil,
/// Always modify this as a whole or change `empty`
blend_config: BlendConfig,
blend_constants: [4]u8,
depth_map_parameters: DepthParameters,
/// Always modify this as a whole or change `empty`
viewport: Viewport,
/// Always modify this as a whole or change `empty`
scissor: Scissor,
combiners: TextureCombinerState = .empty,
/// Always modify this as a whole or change `empty`
vtx_input: VertexInputLayout,
light_environment: LightEnvironment,
vertex_shader: ?*backend.Shader,
geometry_shader: ?*backend.Shader,
dirty: Dirty,

pub fn setDepthMode(state: *GraphicsState, mode: mango.DepthMode) void {
    if (validation.enabled) state.check.set.depth_mode = true;

    state.misc.depth_mode = mode.native();
    state.dirty.depth_map_mode = true;
}

pub fn setCullMode(state: *GraphicsState, cull_mode: mango.CullMode) void {
    if (validation.enabled) state.check.set.cull_mode = true;

    const native_cull_mode_ccw = cull_mode.native(.ccw);

    state.misc.cull_mode_ccw = native_cull_mode_ccw;
    state.dirty.cull_mode = true;
}

pub fn setFrontFace(state: *GraphicsState, front_face: mango.FrontFace) void {
    if (validation.enabled) state.check.set.front_face = true;

    const front_ccw = switch (front_face) {
        .ccw => true,
        .cw => false,
    };

    state.misc.is_front_ccw = front_ccw;
    state.dirty.cull_mode = true;
}

pub fn setPrimitiveTopology(state: *GraphicsState, primitive_topology: mango.PrimitiveTopology) void {
    if (validation.enabled) state.check.set.primitive_topology = true;

    const native_primitive_topology = primitive_topology.native();

    state.misc.primitive_topology = native_primitive_topology;
    state.dirty.primitive_topology = true;
}

pub fn setViewport(state: *GraphicsState, viewport: mango.Viewport) void {
    if (validation.enabled) state.check.set.viewport = true;

    const viewport_x: u10 = @intCast(viewport.rect.offset.x);
    const viewport_y: u10 = @intCast(viewport.rect.offset.y);
    const viewport_width_minus_one: u10 = @intCast(viewport.rect.extent.width - 1);
    const viewport_height_minus_one: u10 = @intCast(viewport.rect.extent.height - 1);

    state.viewport = .{
        .x = viewport_x,
        .y = viewport_y,
        .width_minus_one = viewport_width_minus_one,
        .height_minus_one = viewport_height_minus_one,
    };
    state.dirty.viewport_parameters = true;

    state.depth_map_parameters.min_depth = viewport.min_depth;
    state.depth_map_parameters.max_depth = viewport.max_depth;
    state.dirty.depth_map_parameters = true;
}

pub fn setScissor(state: *GraphicsState, scissor: mango.Scissor) void {
    if (validation.enabled) state.check.set.scissor = true;

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

pub fn setTextureCombiners(state: *GraphicsState, combiners: []const mango.TextureCombinerUnit, combiner_buffer_sources: []const mango.TextureCombinerUnit.BufferSources) void {
    if (validation.enabled) state.check.set.texture_combiners = true;

    state.combiners = .compile(combiners, combiner_buffer_sources);
    state.dirty.combiners = comptime .splat(true);
    state.dirty.combiners_config = true;
}

pub fn setBlendEquation(state: *GraphicsState, blend_equation: mango.ColorBlendEquation) void {
    if (validation.enabled) state.check.set.blend_equation = true;

    const native_blend_config = blend_equation.native();

    state.blend_config = native_blend_config;
    state.dirty.blend_config = true;
}

pub fn setBlendConstants(state: *GraphicsState, blend_constants: *const [4]u8) void {
    if (validation.enabled) state.check.set.blend_constants = true;

    state.blend_constants = blend_constants.*;
    state.dirty.blend_constants = true;
}

pub fn setColorWriteMask(state: *GraphicsState, write_mask: mango.ColorComponentFlags) void {
    if (validation.enabled) state.check.set.color_write_mask = true;

    state.misc.color_r_enable = write_mask.r_enable;
    state.misc.color_g_enable = write_mask.g_enable;
    state.misc.color_b_enable = write_mask.b_enable;
    state.misc.color_a_enable = write_mask.a_enable;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthTestEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.depth_test_enable = true;

    state.misc.depth_test_enable = enable;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthCompareOp(state: *GraphicsState, op: mango.CompareOperation) void {
    if (validation.enabled) state.check.set.depth_compare_op = true;

    const native_op = op.native();

    state.misc.depth_test_op = native_op;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthWriteEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.depth_write_enable = true;

    state.misc.depth_write_enable = enable;
    state.dirty.depth_test_masks = true;
}

pub fn setDepthBias(state: *GraphicsState, bias: f32) void {
    if (validation.enabled) state.check.set.depth_bias = true;

    state.depth_map_parameters.constant = bias;
    state.dirty.depth_map_parameters = true;
}

pub fn setLogicOpEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.logic_op_enable = true;

    state.misc.logic_op_enable = enable;
    state.dirty.logic_blend_mode = true;
}

pub fn setLogicOp(state: *GraphicsState, logic_op: mango.LogicOperation) void {
    if (validation.enabled) state.check.set.logic_op = true;

    const native_logic_op = logic_op.native();

    state.misc.logic_op = native_logic_op;
    state.dirty.logic_operation = true;
}

pub fn setAlphaTestEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.alpha_test_enable = true;

    state.misc.alpha_test_enable = enable;
    state.dirty.alpha_test = true;
}

pub fn setAlphaTestCompareOp(state: *GraphicsState, compare_op: mango.CompareOperation) void {
    if (validation.enabled) state.check.set.alpha_test_op = true;

    const native = compare_op.native();

    state.misc.alpha_test_op = native;
    state.dirty.alpha_test = true;
}

pub fn setAlphaTestReference(state: *GraphicsState, reference: u8) void {
    if (validation.enabled) state.check.set.alpha_test_reference = true;

    state.misc.alpha_test_reference = reference;
    state.dirty.alpha_test = true;
}

pub fn setStencilTestEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.stencil_test_enable = true;

    state.stencil.state.enable = enable;
    state.dirty.stencil_config = true;
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
    state.dirty.stencil_config = true;
    state.dirty.stencil_operation = true;
}

pub fn setStencilCompareMask(state: *GraphicsState, compare_mask: u8) void {
    state.stencil.compare_mask = compare_mask;
    state.dirty.stencil_config = true;
}

pub fn setStencilWriteMask(state: *GraphicsState, write_mask: u8) void {
    state.stencil.write_mask = write_mask;
    state.dirty.stencil_config = true;
}

pub fn setStencilReference(state: *GraphicsState, reference: u8) void {
    state.stencil.reference = reference;
    state.dirty.stencil_config = true;
}

pub fn setVertexInput(state: *GraphicsState, layout: mango.VertexInputLayout) void {
    if (validation.enabled) state.check.set.vertex_input = true;

    state.vtx_input = backend.VertexInputLayout.fromHandleMutable(layout).*;
    state.dirty.vertex_input_layout = true;
}

pub fn setTextureCoordinates(state: *GraphicsState, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
    state.misc.texture_2_coordinates = texture_2_coordinates.nativeTexture2();
    state.misc.texture_3_coordinates = texture_3_coordinates.nativeTexture3();
    state.dirty.texture_config = true;
}

pub fn setLightingEnable(state: *GraphicsState, enable: bool) void {
    if (validation.enabled) state.check.set.lighting_enable = true;

    state.misc.lighting_enable = enable;
    state.dirty.lighting_enable = true;
}

pub fn setLightEnvironmentEnable(state: *GraphicsState, enable: mango.LightEnvironmentEnable) void {
    state.light_environment.control = .{
        .environment = .{
            .enable_shadow_factor = false,
            .fresnel = enable.fresnel.native(),
            .enabled_lookup_tables = enable.nativeEnabledLookupTables(),
            .apply_shadow_attenuation_to_primary_color = false,
            .apply_shadow_attenuation_to_secondary_color = false,
            .invert_shadow_attenuation = false,
            .apply_shadow_attenuation_to_alpha = false,
            .bump_map_unit = .@"0",
            .shadow_map_unit = .@"0", // Not configurable, only unit 0 can use shadow textures...
            .clamp_highlights = false,
            .bump_mode = .none,
            .disable_bump_recalculation = false,
        },
        .lights = .{
            .shadows_disabled = .splat(true),
            .spotlight_disabled = .splat(true),
            .disable_d0 = !enable.distribution[0],
            .disable_d1 = !enable.distribution[1],
            .disable_fr = enable.fresnel == .none,
            .disable_rb = !enable.reflection[2],
            .disable_rg = !enable.reflection[1],
            .disable_rr = !enable.reflection[0],
            .distance_attenuation_disabled = .splat(true), // Set by lights
        },
    };

    state.dirty.light_environment_control = true;
}

pub fn setLightEnvironmentInput(state: *GraphicsState, input: mango.LightEnvironmentInput) void {
    state.light_environment.lut_input_select = .{
        .d0 = input.distribution[0].native(),
        .d1 = input.distribution[1].native(),
        .sp = input.spotlight.native(),
        .fr = input.fresnel.native(),
        .rb = input.reflection[2].native(),
        .rg = input.reflection[1].native(),
        .rr = input.reflection[0].native(),
    };

    state.dirty.light_environment_input = true;
}

pub fn setLightEnvironmentRange(state: *GraphicsState, range: mango.LightEnvironmentRange) void {
    state.light_environment.lut_input_abs = .{
        .disable_d0 = range.distribution[0] == .full,
        .disable_d1 = range.distribution[1] == .full,
        .disable_sp = range.spotlight == .full,
        .disable_fr = range.fresnel == .full,
        .disable_rb = range.reflection[2] == .full,
        .disable_rg = range.reflection[1] == .full,
        .disable_rr = range.reflection[0] == .full,
    };

    state.dirty.light_environment_absolute = true;
}

pub fn setLightEnvironmentScale(state: *GraphicsState, scale: mango.LightEnvironmentScale) void {
    state.light_environment.lut_input_scale = .{
        .d0 = scale.distribution[0].nativeLightLookupMultiplier(),
        .d1 = scale.distribution[1].nativeLightLookupMultiplier(),
        .sp = scale.spotlight.nativeLightLookupMultiplier(),
        .fr = scale.fresnel.nativeLightLookupMultiplier(),
        .rb = scale.reflection[2].nativeLightLookupMultiplier(),
        .rg = scale.reflection[1].nativeLightLookupMultiplier(),
        .rr = scale.reflection[0].nativeLightLookupMultiplier(),
    };

    state.dirty.light_environment_scale = true;
}

pub fn bindLightEnvironmentTable(state: *GraphicsState, slot: mango.LightEnvironmentLookupSlot, table: mango.LightLookupTable) void {
    state.light_environment.luts[@intFromEnum(slot)] = table;

    // NOTE: we have to do this because we get a bit-pointer here
    var luts = state.dirty.light_luts;
    luts.set(@intFromEnum(slot), true);
    state.dirty.light_luts = luts;
}

pub fn bindShaders(state: *GraphicsState, stages: []const mango.ShaderStage, shaders: []const mango.Shader) void {
    std.debug.assert(stages.len == shaders.len and stages.len < 2);

    for (stages, shaders) |stage, shader| {
        const maybe_new: ?*backend.Shader = .fromHandleMutable(shader);

        switch (stage) {
            .vertex => if (maybe_new) |new| {
                // NOTE: as it is invalid to do a drawcall without a vertex shader, we make binding a null one a NOP

                if (state.vertex_shader) |vtx| {
                    state.vertex_shader = new;
                    state.dirty.vertex_shader = state.dirty.vertex_shader or new != vtx;
                    state.dirty.vertex_shader_code = state.dirty.vertex_shader_code or new.code.uid != vtx.code.uid;
                } else {
                    state.vertex_shader = maybe_new;
                    state.dirty.vertex_shader = true;
                    state.dirty.vertex_shader_code = true;
                }
            },
            .geometry => if (maybe_new) |new| {
                if (state.geometry_shader) |gs| {
                    state.geometry_shader = new;
                    state.dirty.geometry_shader = state.dirty.geometry_shader or new != gs;
                    state.dirty.geometry_shader_code = state.dirty.geometry_shader_code or new.code.uid != gs.code.uid;
                } else {
                    state.geometry_shader = new;
                    state.dirty.geometry_shader = true;
                    state.dirty.geometry_shader_code = true;
                }
            } else {
                state.geometry_shader = null;
                state.dirty.geometry_shader = true;
                state.dirty.geometry_shader_code = false; // NOTE: must set this to false, binding null shouldn't change the uploaded code.
            },
        }
    }
}

/// Returns the maximum amount of words the next dirty emission will take.
///
/// Its a safe upper bound, not the exact amount needed.
pub fn maxEmitDirtyQueueLength(state: *GraphicsState) usize {
    // NOTE: This must be FAST as its always checked every drawcall!
    var max: usize = (@as(usize, state.dirty.combiners.raw) * 9) + (@as(usize, state.dirty.light_luts.raw) * 300) + (@as(usize, @intFromBool(state.dirty.vertex_shader)) * 16) + (@as(usize, @intFromBool(state.dirty.geometry_shader)) * 16);

    if (state.dirty.vertex_shader_code) max += if (state.vertex_shader) |vtx|
        10 + vtx.code.instructions.len + vtx.code.descriptors.len
    else
        0;

    if (state.dirty.geometry_shader_code) max += if (state.geometry_shader) |gs|
        10 + gs.code.instructions.len + gs.code.descriptors.len
    else
        0;
    return max;
}

pub fn emitDirty(state: *GraphicsState, queue: *command.Queue) !void {
    if (validation.enabled) try state.validate();

    // NOTE: a vertex shader must always be bound when drawing
    const vtx = state.vertex_shader.?;
    std.debug.assert(vtx.info.type == .vertex);

    // NOTE: Here we don't set uniforms, that belongs to `RenderingState`
    if (state.dirty.vertex_shader or state.dirty.geometry_shader) {
        if (state.dirty.vertex_shader_code) {
            // NOTE: when code is dirty a shader is always present
            const common = (state.dirty.geometry_shader_code and vtx.code.uid == state.geometry_shader.?.code.uid) or state.geometry_shader == null;

            if (common) {
                queue.add(p3d, &p3d.primitive_engine.exclusive_shader_configuration, .init(false));
                queue.addMasked(p3d, &p3d.primitive_engine.config, .{
                    .geometry_shader_usage = .disabled,
                    .variable_geometry_inputs = false,
                }, 0b1101);
                state.dirty.geometry_shader_code = false; // We're already uploading code to both so don't go through that path
            }

            state.emitCode(queue, &p3d.vertex_shader, vtx.code);
        }

        if (state.dirty.vertex_shader) {
            queue.add(p3d, &p3d.vertex_shader.entrypoint, .{ .entry = vtx.entry });
            queue.add(p3d, &p3d.vertex_shader.output_map_mask, .init(@bitCast(vtx.output_set.bits)));

            const outputs_minus_one: u4 = @intCast(vtx.output_set.count() - 1);
            queue.add(p3d, &p3d.primitive_engine.vertex_shader_output_map_total_1, .init(outputs_minus_one));
            queue.add(p3d, &p3d.primitive_engine.vertex_shader_output_map_total_2, .init(outputs_minus_one));
            queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{
                .total_vertex_outputs = outputs_minus_one,
                .topology = .triangle_list, // NOTE: Ignored by mask
            }, 0b0001);
        }

        if (state.dirty.geometry_shader and state.geometry_shader != null) {
            const gs = state.geometry_shader.?;

            queue.add(p3d, &p3d.primitive_engine.exclusive_shader_configuration, .init(true));
            queue.addMasked(p3d, &p3d.primitive_engine.config, .{
                .geometry_shader_usage = .enabled,
                .variable_geometry_inputs = gs.info.type == .geometry_variable,
            }, 0b1101);

            if (state.dirty.geometry_shader_code) state.emitCode(queue, &p3d.geometry_shader, gs.code);

            queue.add(p3d, &p3d.geometry_shader.entrypoint, .{ .entry = gs.entry });
            queue.add(p3d, &p3d.geometry_shader.output_map_mask, .init(@bitCast(gs.output_set.bits)));

            queue.add(p3d, &p3d.geometry_shader.input, .{
                .inputs = switch (gs.info.type) {
                    .vertex => unreachable,
                    .geometry_point => gs.info.geometry.point.inputs_minus_one,
                    .geometry_variable, .geometry_fixed => 0,
                },
                .enabled_for_geometry_0 = true,
            });

            queue.add(p3d, &p3d.vertex_shader.attribute_permutation, state.vtx_input.permutation);
            queue.add(p3d, &p3d.primitive_engine.geometry_shader, .{
                .mode = switch (gs.info.type) {
                    .vertex => unreachable,
                    .geometry_point => .point,
                    .geometry_variable => .variable,
                    .geometry_fixed => .fixed,
                },
                .fixed_vertices_minus_one = gs.info.geometry.fixed.vertices_minus_one,
                .point_inputs_minus_one = gs.info.geometry.point.inputs_minus_one,
                .uniform_start = gs.info.geometry.fixed.uniform_start,
                .fixed = gs.info.type == .geometry_fixed,
            });

            queue.add(p3d, &p3d.primitive_engine.geometry_shader_full_vertices_minus_one, .init(gs.info.geometry.variable.full_vertices));
        }

        // NOTE: we don't have to change the output to the rasterizer if we have a geometry shader
        // and ONLY a vertex shader has changed as the rasterizer will still get the outputs from the geometry shader.
        if ((state.dirty.vertex_shader and state.geometry_shader == null) or state.dirty.geometry_shader) {
            const output_set, const outputs = if (state.geometry_shader) |gs|
                .{ gs.output_set, gs.output_map }
            else
                .{ vtx.output_set, vtx.output_map };

            var attribute_clock: pica.Graphics.Rasterizer.Clock = .{};

            var out_it = output_set.iterator();
            var semantic_outputs: usize = 0;
            while (out_it.next()) |o| {
                const map = outputs[semantic_outputs];

                if (@intFromEnum(o) >= @intFromEnum(pica.shader.register.Destination.Output.o7)) {
                    std.debug.assert(map.x == .unused and map.y == .unused and map.z == .unused and map.w == .unused);
                    continue;
                }

                const tex_coords_present = &attribute_clock.texture_coordinates;

                attribute_clock.color = attribute_clock.color or (map.x.isColor() or map.y.isColor() or map.z.isColor() or map.w.isColor());
                attribute_clock.position_z = attribute_clock.position_z or (map.x == .position_z or map.y == .position_z or map.z == .position_z or map.w == .position_z);
                tex_coords_present.* = tex_coords_present.copyWith(0, tex_coords_present.get(0) or (map.x.isTextureCoordinates0() or map.y.isTextureCoordinates0() or map.z.isTextureCoordinates0() or map.w.isTextureCoordinates0()));
                tex_coords_present.* = tex_coords_present.copyWith(1, tex_coords_present.get(1) or (map.x.isTextureCoordinates1() or map.y.isTextureCoordinates1() or map.z.isTextureCoordinates1() or map.w.isTextureCoordinates1()));
                tex_coords_present.* = tex_coords_present.copyWith(2, tex_coords_present.get(2) or (map.x.isTextureCoordinates2() or map.y.isTextureCoordinates2() or map.z.isTextureCoordinates2() or map.w.isTextureCoordinates2()));
                attribute_clock.texture_coordinates_0_w = attribute_clock.texture_coordinates_0_w or (map.x == .texture_coordinates_0_w or map.y == .texture_coordinates_0_w or map.z == .texture_coordinates_0_w or map.w == .texture_coordinates_0_w);
                attribute_clock.normal_or_view = attribute_clock.normal_or_view or (map.x.isView() or map.x.isNormalQuaternion()) or (map.y.isView() or map.y.isNormalQuaternion()) or (map.z.isView() or map.z.isNormalQuaternion()) or (map.w.isView() or map.w.isNormalQuaternion());

                queue.add(p3d, &p3d.rasterizer.inputs[semantic_outputs], map);
                semantic_outputs += 1;
            }

            queue.add(p3d, &p3d.rasterizer.num_inputs, .init(@intCast(semantic_outputs)));
            queue.add(p3d, &p3d.rasterizer.input_clock, attribute_clock);
            queue.add(p3d, &p3d.rasterizer.input_mode, .{
                .use_texture_coordinates = (attribute_clock.texture_coordinates.raw != 0) or attribute_clock.texture_coordinates_0_w,
            });
        }
    }

    if (state.dirty.cull_mode) {
        // NOTE: emission takes 2 words
        const cull_mode_ccw = state.misc.cull_mode_ccw;
        const is_front_ccw = state.misc.is_front_ccw;

        queue.add(p3d, &p3d.rasterizer.cull_config, .init(if (is_front_ccw)
            cull_mode_ccw
        else switch (cull_mode_ccw) {
            .none => .none,
            .ccw => .cw,
            .cw => .ccw,
        }));
    }

    if (state.dirty.viewport_parameters) {
        // NOTE: emission takes 8 words

        const flt_width = @as(f32, @floatFromInt(state.viewport.width_minus_one)) + 1.0;
        const flt_height = @as(f32, @floatFromInt(state.viewport.height_minus_one)) + 1.0;

        queue.addIncremental(p3d, .{
            &p3d.rasterizer.viewport_h_scale,
            &p3d.rasterizer.viewport_h_step,
            &p3d.rasterizer.viewport_v_scale,
            &p3d.rasterizer.viewport_v_step,
        }, .{
            .init(.of(flt_width / 2.0)),
            .init(.of(2.0 / flt_width)),
            .init(.of(flt_height / 2.0)),
            .init(.of(2.0 / flt_height)),
        });

        queue.add(p3d, &p3d.rasterizer.viewport_xy, .{ state.viewport.x, state.viewport.y });
    }

    if (state.dirty.scissor_parameters) {
        // NOTE: emission takes 4 words
        queue.add(p3d, &p3d.rasterizer.scissor, .{
            .mode = .init(if (state.misc.is_scissor_inside) .inside else .outside),
            .start = .{ state.scissor.x, state.scissor.y },
            .end = .{ state.scissor.end_x, state.scissor.end_y },
        });
    }

    if (state.dirty.depth_map_mode) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.rasterizer.depth_map_mode, .init(state.misc.depth_mode));
    }

    if (state.dirty.depth_map_parameters) {
        // NOTE: emission takes 4 words
        const depth_map_scale = (state.depth_map_parameters.min_depth - state.depth_map_parameters.max_depth);
        const depth_map_bias = state.depth_map_parameters.min_depth + state.depth_map_parameters.constant;

        queue.add(p3d, &p3d.rasterizer.depth_map, .{
            .scale = .init(.of(depth_map_scale)),
            .bias = .init(.of(depth_map_bias)),
        });
    }

    if (state.dirty.primitive_topology) {
        // NOTE: emission takes 6 words
        const primitive_topology = state.misc.primitive_topology;

        queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{
            .total_vertex_outputs = 0, // NOTE: Ignored by mask
            .topology = primitive_topology.indexedTopology(),
        }, 0b0010);

        queue.addMasked(p3d, &p3d.primitive_engine.config, .{
            .drawing_triangles = primitive_topology == .triangle_list,
        }, 0b0010);

        queue.addMasked(p3d, &p3d.primitive_engine.state, .{
            .drawing_triangles = primitive_topology == .triangle_list,
        }, 0b0010);
    }

    if (state.dirty.logic_blend_mode) {
        // NOTE: emission takes 2 words
        queue.addMasked(p3d, &p3d.output_merger.config, .{
            .mode = .default,
            .blend = if (state.misc.logic_op_enable) .logic else .blend,
        }, 0b0110);
    }

    if (state.dirty.logic_operation) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.logic_config, .init(state.misc.logic_op));
    }

    if (state.dirty.depth_test_masks) {
        queue.add(p3d, &p3d.rasterizer.early_depth_test_enable, .init(false));
        queue.add(p3d, &p3d.output_merger.early_depth_test_enable, .init(false));

        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.depth_color_config, .{
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
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.blend_config, state.blend_config);
    }

    if (state.dirty.blend_constants) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.blend_color, state.blend_constants);
    }

    if (state.dirty.alpha_test) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.alpha_test, .{
            .enable = state.misc.alpha_test_enable,
            .op = state.misc.alpha_test_op,
            .reference = state.misc.alpha_test_reference,
        });
    }

    if (state.dirty.stencil_config) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.stencil_test.config, .{
            .enable = state.stencil.state.enable,
            .op = state.stencil.state.op,
            .compare_mask = state.stencil.compare_mask,
            .reference = state.stencil.reference,
            .write_mask = state.stencil.write_mask,
        });
    }

    if (state.dirty.stencil_operation) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.output_merger.stencil_test.operation, .{
            .fail_op = state.stencil.state.fail_op,
            .depth_fail_op = state.stencil.state.depth_fail_op,
            .pass_op = state.stencil.state.pass_op,
        });
    }

    if (state.dirty.combiners_config) {
        // NOTE: emission takes 2 words
        queue.add(p3d, &p3d.texture_combiners.config, state.combiners.config);
    }

    if (state.dirty.combiners.raw != 0) {
        // NOTE: emission takes 8 words per combiner
        const combiner_regs = &p3d.texture_combiners;
        const units: []const *volatile Graphics.TextureCombiners.Unit = &.{ &combiner_regs.@"0", &combiner_regs.@"1", &combiner_regs.@"2", &combiner_regs.@"3", &combiner_regs.@"4", &combiner_regs.@"5" };
        const units_start: usize = units.len - state.combiners.configured;

        var i: u8 = 0;
        while (i < state.combiners.configured) : (i += 1) {
            queue.add(p3d, units[units_start + i], state.combiners.units[i]);
        }
    }

    if (state.dirty.vertex_input_layout) {
        queue.addIncremental(p3d, .{
            &p3d.primitive_engine.attributes.base,
            &p3d.primitive_engine.attributes.config.low,
            &p3d.primitive_engine.attributes.config.high,
        }, .{
            .fromPhysical(backend.global_attribute_buffer_base),
            state.vtx_input.config.low,
            state.vtx_input.config.high,
        });

        for (0..state.vtx_input.buffers_len) |i| {
            queue.add(p3d, &p3d.primitive_engine.attributes.vertex_buffers[i].config, state.vtx_input.buffer_config[i]);
        }

        queue.add(p3d, &p3d.primitive_engine.vertex_shader_input_attributes, .init(state.vtx_input.config.high.attributes_end));

        queue.add(p3d, &p3d.vertex_shader.input, .{
            .inputs = (state.vtx_input.config.high.attributes_end),
            .enabled_for_vertex_0 = true,
            .enabled_for_vertex_1 = true,
        });

        queue.add(p3d, &p3d.vertex_shader.attribute_permutation, state.vtx_input.permutation);
    }

    if (state.dirty.texture_config) {
        // NOTE: emission takes 2 words
        queue.addMasked(p3d, &p3d.texture_units.config, .{
            .texture_enabled = .splat(false),
            .texture_3_coordinates = state.misc.texture_3_coordinates,
            .texture_3_enabled = false, // TODO: Procedural texture support, should be part of gfx state, not rendering unlike normal textures!
            .texture_2_coordinates = state.misc.texture_2_coordinates,
            .clear_texture_cache = false,
        }, 0b0010);
    }

    if (state.dirty.lighting_enable) {
        queue.add(p3d, &p3d.texture_units.lighting_enable, .init(state.misc.lighting_enable));
        queue.add(p3d, &p3d.fragment_lighting.disable, .init(!state.misc.lighting_enable));
    }

    if (state.dirty.light_environment_control) {
        queue.add(p3d, &p3d.fragment_lighting.control.environment, state.light_environment.control.environment);
        queue.addMasked(p3d, &p3d.fragment_lighting.control.lights, state.light_environment.control.lights, 0b0010);
    }

    if (state.dirty.light_environment_input) {
        queue.add(p3d, &p3d.fragment_lighting.lut_input_select, state.light_environment.lut_input_select);
    }

    if (state.dirty.light_environment_absolute) {
        queue.add(p3d, &p3d.fragment_lighting.lut_input_absolute, state.light_environment.lut_input_abs);
    }

    if (state.dirty.light_environment_scale) {
        queue.add(p3d, &p3d.fragment_lighting.lut_input_scale, state.light_environment.lut_input_scale);
    }

    if (state.dirty.light_luts.raw != 0) {
        const selectors: []const pica.Graphics.FragmentLighting.LookupTable = &.{ .d0, .d1, .rr, .rg, .rb, .fr };

        for (0..6) |i| if (state.dirty.light_luts.get(i) and state.light_environment.luts[i] != .null) {
            const b_table: *backend.LightLookupTable = .fromHandleMutable(state.light_environment.luts[i]);

            queue.add(p3d, &p3d.fragment_lighting.lut_index, .init(selectors[i], 0));
            queue.addConsecutive(p3d, &p3d.fragment_lighting.lut_data[0], &b_table.data);
        };
    }

    state.dirty = .{};
}

fn emitCode(_: *GraphicsState, queue: *command.Queue, shader: *volatile pica.Graphics.Shader, code: *backend.Shader.Code) void {
    queue.add(p3d, &shader.code_transfer_index, .init(0));
    queue.addConsecutive(p3d, &shader.code_transfer_data[0], code.instructions);

    queue.add(p3d, &shader.code_transfer_end, .init(.trigger));

    queue.add(p3d, &shader.operand_descriptors_index, .init(0));
    queue.addConsecutive(p3d, &shader.operand_descriptors_data[0], code.descriptors);
}

fn validate(state: *GraphicsState) !void {
    const check = state.check;

    const conditions: []const bool = &.{
        state.vertex_shader != null,
        check.set.cull_mode,
        check.set.front_face,
        check.set.primitive_topology,
        check.set.viewport,
        check.set.scissor,
        check.set.texture_combiners,
        check.set.blend_equation,
        check.set.color_write_mask,
        check.set.depth_test_enable,
        check.set.logic_op_enable,
        check.set.vertex_input,
        check.set.alpha_test_enable,
        check.set.stencil_test_enable,
        check.set.lighting_enable,
    };

    const kinds: []const []const u8 = &.{
        "vertex shader",
        "cull mode",
        "front face",
        "primitive topology",
        "viewport",
        "scissor",
        "texture combiners",
        "blend equation",
        "color write mask",
        "depth test enable",
        "logic op enable",
        "vertex input layout",
        "alpha test enable",
        "stencil test enable",
        "lighting enable",
    };

    var success = true;

    for (conditions, kinds) |condition, kind| {
        success &= validation.check(condition, validation.graphics_state.must_be_set, .{kind});
    }

    if (!success) return error.ValidationFailed;
}

const GraphicsState = @This();

const backend = @import("backend.zig");
const validation = backend.validation;

const TextureCombinerState = backend.TextureCombinerState;
const VertexInputLayout = backend.VertexInputLayout;

const std = @import("std");
const zitrus = @import("zitrus");

const hardware = zitrus.hardware;
const mango = zitrus.mango;
const pica = hardware.pica;

const Graphics = pica.Graphics;
const FragmentLighting = Graphics.FragmentLighting;
const BlendConfig = Graphics.OutputMerger.BlendConfig;

const command = pica.command;

const p3d = &zitrus.memory.arm11.pica.p3d;
