//! Records 3D commands to be submitted to the PICA200.
//!
//! As the PICA200 is limited to what it can do with 3D drawing commands,
//! things like clearing an `Image` or copying data is done with the `Device`.
//!
//! ## Things to consider
//!
//! **mango** follows some assumptions about its state:
//!
//! * `config` (GPUREG_GEOSTAGE_CONFIG) and `config_2` (GPUREG_GEOSTAGE_CONFIG2) are
//! initialized with `Drawing triangle elements` to `true` when binding a pipeline or changing primitive topology. Don't
//! know the implications of this but currently works (Thanks DMP engineers!)
//!
//! * `primitive_config` (GPUREG_PRIMITIVE_CONFIG) is initialized to the primitive topology for `drawIndexed` (see `pica.PrimitiveTopology`)
//! which means less register writes when using `drawIndexed` (which programs should use!).
//!
//! TODO: Document more assumptions made.

pub const Handle = enum(u32) {
    null = 0,
    _,

    pub fn begin(cmd: Handle) !void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.begin();
    }

    pub fn end(cmd: Handle) !void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.end();
    }

    pub fn bindShaders(cmd: Handle, stages: []const mango.ShaderStage, shaders: []const mango.Shader) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.bindShaders(stages, shaders);
    }

    pub fn bindVertexBuffersSlice(cmd: Handle, first_binding: u32, buffers: []const mango.Buffer, offsets: []const u32) void {
        std.debug.assert(buffers.len == offsets.len);
        return cmd.bindVertexBuffers(first_binding, buffers.len, buffers.ptr, offsets.ptr);
    }

    pub fn bindVertexBuffers(cmd: Handle, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindVertexBuffers(first_binding, binding_count, buffers, offsets);
    }

    pub fn bindIndexBuffer(cmd: Handle, buffer: mango.Buffer, offset: u32, index_type: mango.IndexType) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindIndexBuffer(buffer, offset, index_type);
    }

    pub fn bindFloatUniforms(cmd: Handle, stage: mango.ShaderStage, first_uniform: u32, uniforms: []const [4]f32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindFloatUniforms(stage, first_uniform, uniforms);
    }

    pub fn bindCombinedImageSamplers(cmd: Handle, first_combined: u32, combined_image_samplers: []const mango.CombinedImageSampler) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindCombinedImageSamplers(first_combined, combined_image_samplers);
    }

    pub fn setLightEnvironmentFactors(cmd: Handle, factors: mango.LightEnvironmentFactors) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLightEnvironmentFactors(factors);
    }

    pub fn setLightsEnabled(cmd: Handle, first_light: u32, enable: []const bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLightsEnabled(first_light, enable);
    }

    pub fn setLights(cmd: Handle, first_light: u32, lights: []const mango.Light) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLights(first_light, lights);
    }

    pub fn setLightFactors(cmd: Handle, first_light: u32, light_factors: []const mango.LightFactors) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLightFactors(first_light, light_factors);
    }

    pub fn bindLightTables(cmd: Handle, slot: mango.LightLookupSlot, first_light: u32, tables: []const mango.LightLookupTable) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindLightTables(slot, first_light, tables);
    }

    pub fn beginRendering(cmd: Handle, rendering_info: mango.RenderingInfo) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.beginRendering(rendering_info);
    }

    pub fn endRendering(cmd: Handle) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.endRendering();
    }

    pub fn draw(cmd: Handle, vertex_count: u32, first_vertex: u32) void {
        return cmd.drawMultiSlice(&.{.{ .vertex_count = vertex_count, .first_vertex = first_vertex }});
    }

    pub fn drawMultiSlice(cmd: Handle, vertex_info: []const mango.MultiDrawInfo) void {
        return cmd.drawMulti(vertex_info.len, vertex_info.ptr, @sizeOf(mango.MultiDrawInfo));
    }

    pub fn drawMulti(cmd: Handle, draw_count: u32, vertex_info: [*]const mango.MultiDrawInfo, stride: u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.drawMulti(draw_count, vertex_info, stride);
    }

    pub fn drawIndexed(cmd: Handle, index_count: u32, first_index: u32, vertex_offset: i32) void {
        return cmd.drawMultiIndexedSlice(&.{.{ .first_index = first_index, .index_count = index_count, .vertex_offset = vertex_offset }});
    }

    pub fn drawMultiIndexedSlice(cmd: Handle, index_info: []const mango.MultiDrawIndexedInfo) void {
        return cmd.drawMultiIndexed(index_info.len, index_info.ptr, @sizeOf(mango.MultiDrawIndexedInfo));
    }

    pub fn drawMultiIndexed(cmd: Handle, draw_count: u32, index_info: [*]const mango.MultiDrawIndexedInfo, stride: u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.drawMultiIndexed(draw_count, index_info, stride);
    }

    pub fn setDepthMode(cmd: Handle, mode: mango.DepthMode) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setDepthMode(mode);
    }

    pub fn setCullMode(cmd: Handle, cull_mode: mango.CullMode) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setCullMode(cull_mode);
    }

    pub fn setFrontFace(cmd: Handle, front_face: mango.FrontFace) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setFrontFace(front_face);
    }

    pub fn setPrimitiveTopology(cmd: Handle, primitive_topology: mango.PrimitiveTopology) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setPrimitiveTopology(primitive_topology);
    }

    pub fn setViewport(cmd: Handle, viewport: mango.Viewport) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setViewport(viewport);
    }

    pub fn setScissor(cmd: Handle, scissor: mango.Scissor) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setScissor(scissor);
    }

    pub fn setTextureCombiners(cmd: Handle, texture_combiners: []const mango.TextureCombinerUnit, texture_combiner_buffer_sources: []const mango.TextureCombinerUnit.BufferSources) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setTextureCombiners(texture_combiners, texture_combiner_buffer_sources);
    }

    pub fn setBlendEquation(cmd: Handle, blend_equation: mango.ColorBlendEquation) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setBlendEquation(blend_equation);
    }

    pub fn setColorWriteMask(cmd: Handle, write_mask: mango.ColorComponentFlags) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setColorWriteMask(write_mask);
    }

    pub fn setDepthTestEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setDepthTestEnable(enable);
    }

    pub fn setDepthCompareOp(cmd: Handle, op: mango.CompareOperation) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setDepthCompareOp(op);
    }

    pub fn setDepthWriteEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setDepthWriteEnable(enable);
    }

    pub fn setDepthBias(cmd: Handle, constant: f32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setDepthBias(constant);
    }

    pub fn setLogicOpEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLogicOpEnable(enable);
    }

    pub fn setLogicOp(cmd: Handle, logic_op: mango.LogicOperation) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setLogicOp(logic_op);
    }

    pub fn setAlphaTestEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setAlphaTestEnable(enable);
    }

    pub fn setAlphaTestCompareOp(cmd: Handle, compare_op: mango.CompareOperation) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setAlphaTestCompareOp(compare_op);
    }

    pub fn setAlphaTestReference(cmd: Handle, reference: u8) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setAlphaTestReference(reference);
    }

    pub fn setStencilTestEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilTestEnable(enable);
    }

    pub fn setStencilOp(cmd: Handle, fail_op: mango.StencilOperation, pass_op: mango.StencilOperation, depth_fail_op: mango.StencilOperation, op: mango.CompareOperation) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilOp(fail_op, pass_op, depth_fail_op, op);
    }

    pub fn setStencilCompareMask(cmd: Handle, compare_mask: u8) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilCompareMask(compare_mask);
    }

    pub fn setStencilWriteMask(cmd: Handle, write_mask: u8) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilWriteMask(write_mask);
    }

    pub fn setStencilReference(cmd: Handle, reference: u8) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilReference(reference);
    }

    pub fn setTextureCoordinates(cmd: Handle, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setTextureCoordinates(texture_2_coordinates, texture_3_coordinates);
    }

    pub fn setVertexInput(cmd: Handle, layout: mango.VertexInputLayout) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setVertexInput(layout);
    }

    pub fn setLightingEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setLightingEnable(enable);
    }

    pub fn setLightEnvironmentEnable(cmd: Handle, enable: mango.LightEnvironmentEnable) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setLightEnvironmentEnable(enable);
    }

    pub fn setLightEnvironmentInput(cmd: Handle, input: mango.LightEnvironmentInput) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setLightEnvironmentInput(input);
    }

    pub fn setLightEnvironmentRange(cmd: Handle, range: mango.LightEnvironmentRange) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setLightEnvironmentRange(range);
    }

    pub fn setLightEnvironmentScale(cmd: Handle, scale: mango.LightEnvironmentScale) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.setLightEnvironmentScale(scale);
    }

    pub fn bindLightEnvironmentTable(cmd: Handle, slot: mango.LightEnvironmentLookupSlot, table: mango.LightLookupTable) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.bindLightEnvironmentTable(slot, table);
    }

    pub fn writeTimestamp(cmd: Handle, pool: mango.QueryPool, query: u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.writeTimestamp(pool, query);
    }

    pub fn beginQuery(cmd: Handle, pool: mango.QueryPool, query: u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.beginQuery(pool, query);
    }

    pub fn endQuery(cmd: Handle, pool: mango.QueryPool, query: u32) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        b_cmd.endQuery(pool, query);
    }

    pub fn reset(cmd: Handle, flags: mango.CommandBufferResetFlags) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.reset(flags);
    }
};

pub const State = enum {
    initial,
    recording,
    executable,
    pending,
    invalid,
};

pub const Scope = enum {
    none,
    render_pass,
    immediate_draw,
};

pub const Error = error{OutOfMemory} || validation.Error;

pub const operation = struct {
    pub const Kind = enum(u3) {
        graphics,
        timestamp,
        begin_query,
        end_query,
    };

    // NOTE: as both address and size must be aligned to 16 bytes we can reuse some unused bits!
    // This means this must always be aligned or UB will happen
    pub const Node = packed struct(u32) {
        /// Kind of THIS node, not the next one.
        kind: Kind,
        _: u1 = 0,
        next: u28,

        pub fn empty(kind: Kind) Node {
            return .{ .kind = kind, .next = 0 };
        }

        pub fn nextPtr(node: Node) ?*Node {
            return @ptrFromInt(@as(u32, node.next) << 4);
        }
    };

    pub const Graphics = extern struct {
        node: Node,
        head: [*]align(16) const u32,
        len: u32,
    };

    pub const Fill = extern struct {
        pub const Size = pica.DisplayController.Framebuffer.Pixel.Size;

        node: Node,
        address: [*]align(16) u8,
        value: u32,
    };

    pub const Copy = extern struct {
        pub const Line = pica.PictureFormatter.Copy.Line;

        node: Node,
        src: [*]align(16) const u8,
        dst: [*]align(16) u8,
        src_line: Line,
        dst_line: Line,
        size: u32,
    };

    pub const Blit = extern struct {
        pub const Dimensions = pica.PictureFormatter.Dimensions;
        pub const Kind = enum(u2) { linear_tiled, tiled_linear, tiled_tiled };

        node: Node,
        src: [*]align(16) const u8,
        dst: [*]align(16) u8,
        src_dimensions: Dimensions,
        dst_dimensions: Dimensions,
    };

    pub const Query = extern struct {
        node: Node,
        pool: *backend.QueryPool,
        query: u32,
    };
};

const Flags = packed struct(u8) {
    pub const none: Flags = .{};

    subsequent_emissions: bool = false,
    drawcall_in_pass: bool = false,
    _: u6 = 0,
};

pool: *CommandPool,
stream: Stream = .empty,

// NOTE: no need to free these as they are embedded in the stream :p
head: ?*operation.Node = null,
last: ?*operation.Node = null,

gfx_state: GraphicsState = .empty,
rnd_state: RenderingState = .empty,
current_error: ?Error = null,
flags: Flags = .none,
state: State = .initial,
scope: Scope = .none,

pub fn init(pool: *CommandPool) CommandBuffer {
    return .{
        .pool = pool,
    };
}

pub fn deinit(cmd: *CommandBuffer) void {
    defer cmd.* = undefined;
    cmd.stream.deinit(cmd.pool.native_gpa);
}

pub fn begin(cmd: *CommandBuffer) !void {
    std.debug.assert(cmd.state == .initial or cmd.state == .executable);
    cmd.reset(.none);
    cmd.state = .recording;
}

pub fn end(cmd: *CommandBuffer) !void {
    std.debug.assert(cmd.state == .recording);

    if (cmd.current_error) |err| {
        cmd.state = .invalid;
        return err;
    }

    cmd.finalizeCurrent() catch |err| {
        cmd.state = .invalid;
        cmd.current_error = err;
        return err;
    };

    cmd.state = .executable;
}

pub fn reset(cmd: *CommandBuffer, flags: mango.CommandBufferResetFlags) void {
    cmd.stream.reset(cmd.pool.native_gpa, if (flags.release_resources) .free_all else .retain_largest);
    cmd.head = null;
    cmd.last = null;
    cmd.gfx_state = .empty;
    cmd.rnd_state = .empty;
    cmd.current_error = null;
    cmd.flags = .none;
    cmd.scope = .none;
    cmd.state = .initial;
}

pub fn bindShaders(cmd: *CommandBuffer, stages: []const mango.ShaderStage, shaders: []const mango.Shader) void {
    cmd.gfx_state.bindShaders(stages, shaders);
    cmd.rnd_state.bindShaders(stages, shaders);
}

pub fn bindVertexBuffers(cmd: *CommandBuffer, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.bindVertexBuffers(first_binding, binding_count, buffers, offsets);
}

pub fn bindIndexBuffer(cmd: *CommandBuffer, buffer: mango.Buffer, offset: u32, index_type: mango.IndexType) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.bindIndexBuffer(buffer, offset, index_type);
}

pub fn bindFloatUniforms(cmd: *CommandBuffer, stage: mango.ShaderStage, first_uniform: u32, uniforms: []const [4]f32) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.bindFloatUniforms(stage, first_uniform, uniforms);
}

pub fn bindCombinedImageSamplers(cmd: *CommandBuffer, first_combined: u32, combined_image_samplers: []const mango.CombinedImageSampler) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.bindCombinedImageSamplers(first_combined, combined_image_samplers);
}

pub fn setLightEnvironmentFactors(cmd: *CommandBuffer, factors: mango.LightEnvironmentFactors) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.setLightEnvironmentFactors(factors);
}

pub fn setLightsEnabled(cmd: *CommandBuffer, first_light: u32, enable: []const bool) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.setLightsEnabled(first_light, enable);
}

pub fn setLights(cmd: *CommandBuffer, first_light: u32, lights: []const mango.Light) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.setLights(first_light, lights);
}

pub fn setLightFactors(cmd: *CommandBuffer, first_light: u32, light_factors: []const mango.LightFactors) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.setLightFactors(first_light, light_factors);
}

pub fn bindLightTables(cmd: *CommandBuffer, slot: mango.LightLookupSlot, first_light: u32, tables: []const mango.LightLookupTable) void {
    std.debug.assert(cmd.state == .recording);

    return cmd.rnd_state.bindLightTables(slot, first_light, tables);
}

pub fn beginRendering(cmd: *CommandBuffer, rendering_info: mango.RenderingInfo) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .none);
    defer cmd.scope = .render_pass;

    return cmd.rnd_state.beginRendering(rendering_info);
}

pub fn endRendering(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);
    defer cmd.scope = .none;

    const queue = cmd.stream.first().?;

    if (cmd.flags.drawcall_in_pass) {
        queue.add(p3d, &p3d.output_merger.flush, .init(.trigger));
        cmd.flags.drawcall_in_pass = false;
    }

    return cmd.rnd_state.endRendering();
}

// TODO: beginShadowRendering, endShadowRendering for the shadow pass w/color op

pub fn drawMulti(cmd: *CommandBuffer, draw_count: u32, vertex_info: [*]const mango.MultiDrawInfo, stride: u32) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if (draw_count == 0) {
        return;
    }

    std.debug.assert(stride >= @sizeOf(mango.MultiDrawInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&vertex_info[0]));

    if (!cmd.beforeDraw(draw_count)) {
        return;
    }

    const queue = &cmd.queue;

    switch (cmd.gfx_state.misc.primitive_topology) {
        .triangle_list => queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{
            .total_vertex_outputs = 0, // NOTE: Ignored by mask
            .topology = cmd.gfx_state.misc.primitive_topology,
        }, 0b0010),
        else => {},
    }
    defer switch (cmd.gfx_state.misc.primitive_topology) {
        .triangle_list => queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{
            .total_vertex_outputs = 0, // NOTE: Ignored by mask
            .topology = cmd.gfx_state.misc.primitive_topology.indexedTopology(),
        }, 0b0010),
        else => {},
    };

    queue.add(p3d, &p3d.primitive_engine.mode, .init(.drawing));
    defer queue.add(p3d, &p3d.primitive_engine.mode, .init(.config));

    queue.addMasked(p3d, &p3d.primitive_engine.state, .{ .inputting_vertices_or_draw_arrays = true }, 0b0001);
    defer queue.addMasked(p3d, &p3d.primitive_engine.state, .{ .inputting_vertices_or_draw_arrays = false }, 0b0001);

    const first_draw = vertex_info[0];
    queue.addIncremental(p3d, .{
        &p3d.primitive_engine.attributes.index_buffer,
        &p3d.primitive_engine.draw_vertex_count,
    }, .{
        .init(0x00, .u16), // NOTE: MUST be u16 for non-indexed draws
        first_draw.vertex_count,
    });

    queue.add(p3d, &p3d.primitive_engine.draw_first_index, first_draw.first_vertex);
    queue.add(p3d, &p3d.primitive_engine.restart_primitive, .init(.trigger));
    queue.add(p3d, &p3d.primitive_engine.draw, .init(.trigger));
    queue.add(p3d, &p3d.primitive_engine.clear_post_vertex_cache, .init(.trigger));

    var last_vertex_info = first_draw;
    var current_vertex_info_ptr: *const mango.MultiDrawInfo = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(vertex_info)) + stride));

    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_vertex_info_ptr));

        const current_vertex_info = current_vertex_info_ptr.*;

        if (current_vertex_info.vertex_count != last_vertex_info.vertex_count) {
            queue.add(p3d, &p3d.primitive_engine.draw_vertex_count, current_vertex_info.vertex_count);
        }

        if (current_vertex_info.first_vertex != last_vertex_info.first_vertex) {
            queue.add(p3d, &p3d.primitive_engine.draw_first_index, current_vertex_info.first_vertex);
        }

        queue.add(p3d, &p3d.primitive_engine.restart_primitive, .init(.trigger));
        queue.add(p3d, &p3d.primitive_engine.draw, .init(.trigger));
        queue.add(p3d, &p3d.primitive_engine.clear_post_vertex_cache, .init(.trigger));

        last_vertex_info = current_vertex_info;
        current_vertex_info_ptr = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(current_vertex_info_ptr)) + stride));
    }

    cmd.flags.drawcall_in_pass = true;
}

pub fn drawMultiIndexed(cmd: *CommandBuffer, draw_count: u32, index_info: [*]const mango.MultiDrawIndexedInfo, stride: u32) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if (draw_count == 0) return;
    std.debug.assert(stride >= @sizeOf(mango.MultiDrawIndexedInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&index_info[0]));

    if (!cmd.beforeDraw(draw_count)) {
        return;
    }

    const queue = cmd.stream.first().?;
    const dynamic_graphics_state = cmd.gfx_state;
    const dynamic_rendering_state = cmd.rnd_state;

    const first_draw = index_info[0];

    queue.add(p3d, &p3d.primitive_engine.mode, .init(.drawing));
    defer queue.add(p3d, &p3d.primitive_engine.mode, .init(.config));

    queue.addIncremental(p3d, .{
        &p3d.primitive_engine.attributes.index_buffer,
        &p3d.primitive_engine.draw_vertex_count,
    }, .{
        .init(@intCast(dynamic_rendering_state.index_buffer_offset + first_draw.first_index), dynamic_rendering_state.misc.index_format),
        first_draw.index_count,
    });

    if (first_draw.vertex_offset != 0) {
        for (&dynamic_rendering_state.vertex_buffers_offset, &dynamic_graphics_state.vtx_input.buffer_config, 0..) |offset, buf_conf, i| {
            const offset_from_bound: i32 = first_draw.vertex_offset * buf_conf.high.bytes_per_vertex;
            const new_offset: u28 = @intCast(offset + offset_from_bound);

            queue.add(p3d, &p3d.primitive_engine.attributes.vertex_buffers[i].offset, .init(new_offset));
        }

        cmd.rnd_state.dirty.vertex_buffers = true;
    }

    queue.add(p3d, &p3d.primitive_engine.restart_primitive, .init(.trigger));
    queue.add(p3d, &p3d.primitive_engine.draw_indexed, .init(.trigger));
    queue.add(p3d, &p3d.primitive_engine.clear_post_vertex_cache, .init(.trigger));

    // NOTE: Seems to be needed, weird things happens if we don't write these?
    queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
    queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

    var last_index_info = first_draw;
    var current_index_info_ptr: *const mango.MultiDrawIndexedInfo = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(index_info)) + stride));

    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_index_info_ptr));

        const current_index_info = current_index_info_ptr.*;

        if (current_index_info.index_count != last_index_info.index_count) {
            queue.add(p3d, &p3d.primitive_engine.draw_vertex_count, current_index_info.index_count);
        }

        if (current_index_info.first_index != last_index_info.first_index) {
            queue.add(p3d, &p3d.primitive_engine.attributes.index_buffer, .init(@intCast(dynamic_rendering_state.index_buffer_offset + current_index_info.first_index), dynamic_rendering_state.misc.index_format));
        }

        if (current_index_info.vertex_offset != last_index_info.vertex_offset) {
            for (&dynamic_rendering_state.vertex_buffers_offset, &dynamic_graphics_state.vtx_input.buffer_config, 0..) |offset, buf_conf, i| {
                const offset_from_bound: i32 = first_draw.vertex_offset * buf_conf.high.bytes_per_vertex;
                const new_offset: u28 = @intCast(offset + offset_from_bound);

                queue.add(p3d, &p3d.primitive_engine.attributes.vertex_buffers[i].offset, .init(new_offset));
            }

            cmd.rnd_state.dirty.vertex_buffers = true;
        }

        queue.add(p3d, &p3d.primitive_engine.restart_primitive, .init(.trigger));
        queue.add(p3d, &p3d.primitive_engine.draw_indexed, .init(.trigger));
        queue.add(p3d, &p3d.primitive_engine.clear_post_vertex_cache, .init(.trigger));

        // NOTE: See above
        queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
        queue.addMasked(p3d, &p3d.primitive_engine.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

        last_index_info = current_index_info;
        current_index_info_ptr = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(current_index_info_ptr)) + stride));
    }

    cmd.flags.drawcall_in_pass = true;
}

// TODO: How should we approach immediate rendering, are 16 vertex attributes really needed?

pub fn setDepthMode(cmd: *CommandBuffer, mode: mango.DepthMode) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthMode(mode);
}

pub fn setCullMode(cmd: *CommandBuffer, cull_mode: mango.CullMode) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setCullMode(cull_mode);
}

pub fn setFrontFace(cmd: *CommandBuffer, front_face: mango.FrontFace) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setFrontFace(front_face);
}

pub fn setPrimitiveTopology(cmd: *CommandBuffer, primitive_topology: mango.PrimitiveTopology) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setPrimitiveTopology(primitive_topology);
}

pub fn setViewport(cmd: *CommandBuffer, viewport: mango.Viewport) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setViewport(viewport);
}

pub fn setScissor(cmd: *CommandBuffer, scissor: mango.Scissor) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setScissor(scissor);
}

pub fn setTextureCombiners(cmd: *CommandBuffer, texture_combiners: []const mango.TextureCombinerUnit, texture_combiner_buffer_sources: []const mango.TextureCombinerUnit.BufferSources) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setTextureCombiners(texture_combiners, texture_combiner_buffer_sources);
}

pub fn setBlendEquation(cmd: *CommandBuffer, blend_equation: mango.ColorBlendEquation) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setBlendEquation(blend_equation);
}

pub fn setColorWriteMask(cmd: *CommandBuffer, write_mask: mango.ColorComponentFlags) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setColorWriteMask(write_mask);
}

pub fn setDepthTestEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthTestEnable(enable);
}

pub fn setDepthCompareOp(cmd: *CommandBuffer, op: mango.CompareOperation) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthCompareOp(op);
}

pub fn setDepthWriteEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthWriteEnable(enable);
}

pub fn setDepthBias(cmd: *CommandBuffer, constant: f32) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthBias(constant);
}

pub fn setLogicOpEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLogicOpEnable(enable);
}

pub fn setLogicOp(cmd: *CommandBuffer, logic_op: mango.LogicOperation) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLogicOp(logic_op);
}

pub fn setAlphaTestEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setAlphaTestEnable(enable);
}

pub fn setAlphaTestCompareOp(cmd: *CommandBuffer, compare_op: mango.CompareOperation) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setAlphaTestCompareOp(compare_op);
}

pub fn setAlphaTestReference(cmd: *CommandBuffer, reference: u8) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setAlphaTestReference(reference);
}

pub fn setStencilTestEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilTestEnable(enable);
}

pub fn setStencilOp(cmd: *CommandBuffer, fail_op: mango.StencilOperation, pass_op: mango.StencilOperation, depth_fail_op: mango.StencilOperation, op: mango.CompareOperation) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilOp(fail_op, pass_op, depth_fail_op, op);
}

pub fn setStencilCompareMask(cmd: *CommandBuffer, compare_mask: u8) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilCompareMask(compare_mask);
}

pub fn setStencilWriteMask(cmd: *CommandBuffer, write_mask: u8) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilWriteMask(write_mask);
}

pub fn setStencilReference(cmd: *CommandBuffer, reference: u8) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilReference(reference);
}

pub fn setTextureCoordinates(cmd: *CommandBuffer, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setTextureCoordinates(texture_2_coordinates, texture_3_coordinates);
}

pub fn setVertexInput(cmd: *CommandBuffer, layout: mango.VertexInputLayout) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setVertexInput(layout);
}

pub fn setLightingEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLightingEnable(enable);
}

pub fn setLightEnvironmentEnable(cmd: *CommandBuffer, enable: mango.LightEnvironmentEnable) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLightEnvironmentEnable(enable);
}

pub fn setLightEnvironmentInput(cmd: *CommandBuffer, input: mango.LightEnvironmentInput) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLightEnvironmentInput(input);
}

pub fn setLightEnvironmentRange(cmd: *CommandBuffer, range: mango.LightEnvironmentRange) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLightEnvironmentRange(range);
}

pub fn setLightEnvironmentScale(cmd: *CommandBuffer, scale: mango.LightEnvironmentScale) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setLightEnvironmentScale(scale);
}

pub fn bindLightEnvironmentTable(cmd: *CommandBuffer, slot: mango.LightEnvironmentLookupSlot, table: mango.LightLookupTable) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.bindLightEnvironmentTable(slot, table);
}

pub fn writeTimestamp(cmd: *CommandBuffer, pool: mango.QueryPool, query: u32) void {
    cmd.doQuery(pool, query, .timestamp);
}

pub fn beginQuery(cmd: *CommandBuffer, pool: mango.QueryPool, query: u32) void {
    cmd.doQuery(pool, query, .begin_query);
}

pub fn endQuery(cmd: *CommandBuffer, pool: mango.QueryPool, query: u32) void {
    cmd.doQuery(pool, query, .end_query);
}

fn doQuery(cmd: *CommandBuffer, pool: mango.QueryPool, query: u32, kind: operation.Kind) void {
    std.debug.assert(cmd.state == .recording);

    if (cmd.current_error) |_| return;

    cmd.finalizeCurrent() catch |err| {
        cmd.current_error = err;
        return;
    };

    const query_op = cmd.allocOperation(operation.Query) catch |err| {
        cmd.current_error = err;
        return;
    };

    query_op.* = .{
        .pool = .fromHandleMutable(pool),
        .query = query,
        .node = .empty(kind),
    };

    cmd.pushOperation(&query_op.node);
}

fn beforeDraw(cmd: *CommandBuffer, draw_count: usize) bool {
    if (cmd.current_error) |_| return false;

    cmd.gfx_state.validate() catch |err| {
        cmd.current_error = err;
        return false;
    };

    cmd.emitDirty(backend.static_emission_cost + draw_count * backend.max_drawcall_emission_cost) catch |err| {
        cmd.current_error = err;
        return false;
    };

    return true;
}

fn emitDirty(cmd: *CommandBuffer, extra_cost: u32) !void {
    const gfx_dirty = cmd.gfx_state.anyDirty();
    const rnd_dirty = cmd.rnd_state.anyDirty();

    if (!gfx_dirty and !rnd_dirty) return;

    const max_graphics_emission_cost = if (gfx_dirty) cmd.gfx_state.maxEmitDirtyQueueLength() else 0;
    const max_rendering_emission_cost = if (rnd_dirty) cmd.rnd_state.maxEmitDirtyQueueLength() else 0;
    const max_emission_cost = backend.static_emission_cost + max_graphics_emission_cost + max_rendering_emission_cost + extra_cost;

    try cmd.ensureUnusedCapacity(max_emission_cost);

    const queue = cmd.stream.first().?;

    if (!cmd.flags.subsequent_emissions) {
        queue.add(p3d, &p3d.primitive_engine.mode, .init(.config));
        cmd.flags.subsequent_emissions = true;
    }

    const gfx_start = queue.end;
    cmd.gfx_state.emitDirty(queue);
    const gfx_end = queue.end;
    std.debug.assert((gfx_end - gfx_start) <= max_graphics_emission_cost);

    const rnd_start = gfx_end;
    cmd.rnd_state.emitDirty(queue);
    const rnd_end = queue.end;
    std.debug.assert((rnd_end - rnd_start) <= max_rendering_emission_cost);
}

/// Finalizes and pushes a graphics operation (if needed)
fn finalizeCurrent(
    cmd: *CommandBuffer,
) !void {
    if (cmd.stream.first()) |queue| if (cmd.flags.drawcall_in_pass) {
        queue.add(p3d, &p3d.output_merger.flush, .init(.trigger));
        cmd.flags.drawcall_in_pass = false;
    };

    if (cmd.stream.finalize()) |head| {
        // NOTE: we're not "leaking" head, if this fails
        // the command buffer must be left in an `invalid` state
        // anyways.

        const gfx_op = try cmd.allocOperation(operation.Graphics);

        gfx_op.* = .{
            .node = .empty(.graphics),
            .head = head.ptr,
            .len = head.len,
        };

        cmd.pushOperation(&gfx_op.node);
    }
}

fn allocOperation(cmd: *CommandBuffer, comptime Operation: type) !*Operation {
    const needed_size = std.mem.alignForward(usize, @sizeOf(operation.Graphics), 16);

    try cmd.ensureUnusedCapacity(needed_size);

    const que = cmd.stream.first().?;
    const ptr: *Operation = @ptrCast(que.buffer.ptr[que.end..]);

    que.end += needed_size;
    cmd.stream.start = que.end;
    return ptr;
}

fn pushOperation(cmd: *CommandBuffer, node: *operation.Node) void {
    std.debug.assert(std.mem.isAligned(@intFromPtr(node), 16));
    const maybe_last = cmd.last;

    cmd.last = node;
    if (maybe_last) |last| {
        std.debug.assert(cmd.head != null);

        last.next = @intCast(@intFromPtr(node) >> 4);
    } else {
        cmd.head = node;
    }
}

fn ensureUnusedCapacity(cmd: *CommandBuffer, capacity: usize) !void {
    const remaining = if (cmd.stream.first()) |que| (que.unusedCapacitySlice().len - cmd.stream.start) else 0;

    if (remaining < capacity) {
        @branchHint(.unlikely);

        // TODO: unregress linear memory pooling
        try cmd.stream.grow(cmd.pool.native_gpa, min_stream_segment_size, .{
            .pool = cmd.pool,
        });
    }
}

pub fn notifyPending(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .executable);
    @atomicStore(backend.CommandBuffer.State, &cmd.state, .pending, .monotonic);
}

/// NOTE: Should we have a one-time submit?
pub fn notifyCompleted(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .pending);
    @atomicStore(backend.CommandBuffer.State, &cmd.state, .executable, .monotonic);
}

pub fn toHandle(image: *CommandBuffer) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *CommandBuffer {
    return @as(*CommandBuffer, @ptrFromInt(@intFromEnum(handle)));
}

const StreamContext = struct {
    comptime use_jumps: bool = true,
    pool: *CommandPool,

    pub fn virtualToPhysical(ctx: StreamContext, virtual: *const anyopaque) zitrus.hardware.PhysicalAddress {
        return ctx.pool.device.vtable.virtualToPhysical(ctx.pool.device, virtual);
    }
};

const min_stream_segment_size = CommandPool.native_min_size;
const Stream = command.stream.Custom(StreamContext);

const CommandBuffer = @This();
const backend = @import("backend.zig");
const validation = backend.validation;

const log = validation.log;

const CommandPool = backend.CommandPool;
const GraphicsState = backend.GraphicsState;
const RenderingState = backend.RenderingState;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.hardware.pica;
const PhysicalAddress = zitrus.hardware.PhysicalAddress;

const command = pica.command;

const p3d = &zitrus.memory.arm11.pica.p3d;
