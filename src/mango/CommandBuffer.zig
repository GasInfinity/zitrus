//! Records 3D commands to be submitted to the PICA200.
//!
//! As the PICA200 is limited to what it can do with 3D drawing commands,
//! things like clearing an `Image` or copying data is done with the `Device`.

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

    pub fn bindPipeline(cmd: Handle, bind_point: mango.PipelineBindPoint, pipeline: mango.Pipeline) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.bindPipeline(bind_point, pipeline);
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

    pub fn setViewport(cmd: Handle, viewport: *const mango.Viewport) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setViewport(viewport);
    }

    pub fn setScissor(cmd: Handle, scissor: *const mango.Scissor) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setScissor(scissor);
    }

    pub fn setTextureCombiners(cmd: Handle, texture_combiners_len: u32, texture_combiners: [*]const mango.TextureCombiner, texture_combiner_buffer_sources_len: u32, texture_combiner_buffer_sources: [*]const mango.TextureCombiner.BufferSources) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setTextureCombiners(texture_combiners_len, texture_combiners, texture_combiner_buffer_sources_len, texture_combiner_buffer_sources);
    }

    pub fn setBlendEquation(cmd: Handle, blend_equation: *const mango.ColorBlendEquation) void {
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
        return b_cmd.setDepthTestEnable(op);
    }

    pub fn setDepthWriteEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setDepthWriteEnable(enable);
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

    pub fn setStencilEnable(cmd: Handle, enable: bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setStencilEnable(enable);
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

    pub fn setTextureEnable(cmd: Handle, enable: *const [4]bool) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setTextureEnable(enable);
    }

    pub fn setTextureCoordinates(cmd: Handle, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.setTextureCoordinates(texture_2_coordinates, texture_3_coordinates);
    }

    pub fn reset(cmd: Handle) void {
        const b_cmd: *CommandBuffer = .fromHandleMutable(cmd);
        return b_cmd.reset();
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
};

pool: *backend.CommandPool,
node: std.DoublyLinkedList.Node = .{},

queue: cmd3d.Queue,
gfx_state: GraphicsState = .empty,
rnd_state: RenderingState = .empty,
emitted_graphics_pipeline: ?*backend.Pipeline.Graphics = null,
bound_graphics_pipeline: ?*backend.Pipeline.Graphics = null,
current_error: ?anyerror = null,
state: State = .initial,
scope: Scope = .none,

pub fn init(pool: *backend.CommandPool, native_buffer: []align(8) u32) CommandBuffer {
    return .{ .pool = pool, .queue = .{
        .buffer = native_buffer,
        .current_index = 0,
    } };
}

pub fn deinit(command_buffer: *CommandBuffer) void {
    command_buffer.pool.freeNative(command_buffer.queue.buffer);
    command_buffer.* = undefined;
}

pub fn begin(cmd: *CommandBuffer) !void {
    std.debug.assert(cmd.state == .initial or cmd.state == .executable);
    cmd.reset();
    cmd.state = .recording;
}

pub fn end(cmd: *CommandBuffer) !void {
    std.debug.assert(cmd.state == .recording);

    if (cmd.current_error) |err| {
        cmd.state = .invalid;
        return err;
    }

    // XXX: Homebrew apps expect start_draw_function to start in configuration mode. Or you have a dreaded black screen of death x-x
    cmd.queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .config);
    cmd.queue.finalize();
    cmd.state = .executable;
}

pub fn bindPipeline(cmd: *CommandBuffer, bind_point: mango.PipelineBindPoint, pipeline: mango.Pipeline) void {
    std.debug.assert(cmd.state == .recording);

    switch (bind_point) {
        .graphics => {
            if (pipeline == .null) {
                cmd.bound_graphics_pipeline = null;
                return;
            }

            cmd.bound_graphics_pipeline = .fromHandleMutable(pipeline);
        },
    }
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

pub fn beginRendering(cmd: *CommandBuffer, rendering_info: mango.RenderingInfo) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .none);

    const color_width, const color_height, const color_physical_address: zitrus.PhysicalAddress = if (rendering_info.color_attachment != .null) info: {
        @branchHint(.likely);
        const color_attachment: backend.ImageView = .fromHandle(rendering_info.color_attachment);
        const color_image: backend.Image = .fromHandle(color_attachment.data.image);

        std.debug.assert(color_image.info.usage.color_attachment);
        break :info .{ color_image.info.width(), color_image.info.height(), color_image.memory_info.boundPhysicalAddress() };
    } else .{ 0, 0, .fromAddress(0) };

    const depth_stencil_width, const depth_stencil_height, const depth_stencil_physical_address: zitrus.PhysicalAddress = if (rendering_info.depth_stencil_attachment != .null) info: {
        const depth_stencil_attachment: backend.ImageView = .fromHandle(rendering_info.depth_stencil_attachment);
        const depth_stencil_image: backend.Image = .fromHandle(depth_stencil_attachment.data.image);

        std.debug.assert(depth_stencil_image.info.usage.depth_stencil_attachment);
        break :info .{ depth_stencil_image.info.width(), depth_stencil_image.info.height(), depth_stencil_image.memory_info.boundPhysicalAddress() };
    } else .{ 0, 0, .fromAddress(0) };

    if (color_physical_address != .zero and depth_stencil_physical_address != .zero) {
        std.debug.assert(color_width == depth_stencil_width and color_height == depth_stencil_height);
    }

    cmd.rnd_state.color_attachment = color_physical_address;
    cmd.rnd_state.depth_stencil_attachment = depth_stencil_physical_address;
    cmd.rnd_state.dimensions = if (color_physical_address != .zero)
        .{ .x = @intCast(color_width), .y = @intCast(color_height) }
    else
        .{ .x = @intCast(depth_stencil_width), .y = @intCast(depth_stencil_height) };

    cmd.rnd_state.dirty.rendering_data = true;
    cmd.scope = .render_pass;
}

pub fn endRendering(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);
    const queue = &cmd.queue;

    // This means a drawcall has been issued so flush the render buffer.
    if (!cmd.rnd_state.dirty.rendering_data) {
        queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_flush, .init(.trigger));
    }

    cmd.rnd_state.dirty.rendering_data = false;
    cmd.scope = .none;
}

pub fn drawMulti(cmd: *CommandBuffer, draw_count: u32, vertex_info: [*]const mango.MultiDrawInfo, stride: u32) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if (draw_count == 0) {
        return;
    }

    std.debug.assert(stride >= @sizeOf(mango.MultiDrawInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&vertex_info[0]));

    if (!cmd.beforeDraw()) {
        return;
    }

    const queue = &cmd.queue;
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{ .inputting_vertices_or_draw_arrays = true }, 0b0001);

    const first_draw = vertex_info[0];
    queue.addIncremental(internal_regs, .{
        &internal_regs.geometry_pipeline.attribute_buffer_index_buffer,
        &internal_regs.geometry_pipeline.attribute_buffer_num_vertices,
    }, .{
        .{
            .base_offset = 0x00,
            .format = .u16, // NOTE: MUST be u16 for non-indexed draws
        },
        first_draw.vertex_count,
    });

    queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_first_index, first_draw.first_vertex);
    queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_arrays, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

    var last_vertex_info = first_draw;
    var current_vertex_info_ptr: *const mango.MultiDrawInfo = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(vertex_info)) + stride));

    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_vertex_info_ptr));

        const current_vertex_info = current_vertex_info_ptr.*;

        if (current_vertex_info.vertex_count != last_vertex_info.vertex_count) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_num_vertices, current_vertex_info.vertex_count);
        }

        if (current_vertex_info.first_vertex != last_vertex_info.first_vertex) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_first_index, current_vertex_info.first_vertex);
        }

        queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_arrays, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

        last_vertex_info = current_vertex_info;
        current_vertex_info_ptr = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(current_vertex_info_ptr)) + stride));
    }
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{ .inputting_vertices_or_draw_arrays = false }, 0b0001);
}

pub fn drawMultiIndexed(cmd: *CommandBuffer, draw_count: u32, index_info: [*]const mango.MultiDrawIndexedInfo, stride: u32) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if (draw_count == 0) {
        return;
    }

    std.debug.assert(stride >= @sizeOf(mango.MultiDrawIndexedInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&index_info[0]));

    if (!cmd.beforeDraw()) {
        return;
    }

    const queue = &cmd.queue;
    const dynamic_graphics_state = cmd.gfx_state;
    const dynamic_rendering_state = cmd.rnd_state;

    const first_draw = index_info[0];
    queue.addIncremental(internal_regs, .{
        &internal_regs.geometry_pipeline.attribute_buffer_index_buffer,
        &internal_regs.geometry_pipeline.attribute_buffer_num_vertices,
    }, .{
        .{
            .base_offset = @intCast(dynamic_rendering_state.index_buffer_offset + first_draw.first_index),
            .format = dynamic_rendering_state.misc.index_format,
        },
        first_draw.index_count,
    });

    if (first_draw.vertex_offset != 0) {
        for (&dynamic_rendering_state.vertex_buffers_offset, &dynamic_graphics_state.vtx_input.buffer_config, 0..) |offset, buf_conf, i| {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[i].offset, offset + @as(u32, @bitCast(first_draw.vertex_offset * buf_conf.high.bytes_per_vertex)));
        }

        cmd.rnd_state.dirty.vertex_buffers = true;
    }

    queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_elements, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

    // NOTE: Seems to be needed, weird things happens if we don't write these?
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

    var last_index_info = first_draw;
    var current_index_info_ptr: *const mango.MultiDrawIndexedInfo = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(index_info)) + stride));

    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_index_info_ptr));

        const current_index_info = current_index_info_ptr.*;

        if (current_index_info.index_count != last_index_info.index_count) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_num_vertices, current_index_info.index_count);
        }

        if (current_index_info.first_index != last_index_info.first_index) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_index_buffer, .{
                .base_offset = @intCast(dynamic_rendering_state.index_buffer_offset + current_index_info.first_index),
                .format = dynamic_rendering_state.misc.index_format,
            });
        }

        if (current_index_info.vertex_offset != last_index_info.vertex_offset) {
            for (&dynamic_rendering_state.vertex_buffers_offset, &dynamic_graphics_state.vtx_input.buffer_config, 0..) |offset, buf_conf, i| {
                queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[i].offset, offset + @as(u32, @bitCast(current_index_info.vertex_offset * buf_conf.high.bytes_per_vertex)));
            }

            cmd.rnd_state.dirty.vertex_buffers = true;
        }

        queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_elements, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

        // NOTE: See above
        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

        last_index_info = current_index_info;
        current_index_info_ptr = @ptrCast(@alignCast(@as([*]const u8, @ptrCast(current_index_info_ptr)) + stride));
    }
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

pub fn setViewport(cmd: *CommandBuffer, viewport: *const mango.Viewport) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setViewport(viewport);
}

pub fn setScissor(cmd: *CommandBuffer, scissor: *const mango.Scissor) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setScissor(scissor);
}

pub fn setTextureCombiners(cmd: *CommandBuffer, texture_combiners_len: u32, texture_combiners: [*]const mango.TextureCombiner, texture_combiner_buffer_sources_len: u32, texture_combiner_buffer_sources: [*]const mango.TextureCombiner.BufferSources) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setTextureCombiners(texture_combiners_len, texture_combiners, texture_combiner_buffer_sources_len, texture_combiner_buffer_sources);
}

pub fn setBlendEquation(cmd: *CommandBuffer, blend_equation: *const mango.ColorBlendEquation) void {
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
    cmd.gfx_state.setDepthTestEnable(op);
}

pub fn setDepthWriteEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setDepthWriteEnable(enable);
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

pub fn setStencilEnable(cmd: *CommandBuffer, enable: bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setStencilEnable(enable);
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

pub fn setTextureEnable(cmd: *CommandBuffer, enable: *const [4]bool) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setTextureEnable(enable);
}

pub fn setTextureCoordinates(cmd: *CommandBuffer, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
    std.debug.assert(cmd.state == .recording);
    cmd.gfx_state.setTextureCoordinates(texture_2_coordinates, texture_3_coordinates);
}

fn beforeDraw(cmd: *CommandBuffer) bool {
    if (cmd.current_error) |_| {
        return false;
    }

    cmd.growIfNeeded() catch |err| {
        cmd.current_error = err;
        return false;
    };

    const queue = &cmd.queue;

    if (cmd.bound_graphics_pipeline != cmd.emitted_graphics_pipeline) if (cmd.bound_graphics_pipeline) |bound_gfx_pipeline| {
        @memcpy(cmd.queue.buffer[cmd.queue.current_index..][0..bound_gfx_pipeline.cmd3d_state.len], bound_gfx_pipeline.cmd3d_state);
        cmd.queue.current_index += bound_gfx_pipeline.cmd3d_state.len;

        bound_gfx_pipeline.copyGraphicsState(&cmd.gfx_state);
        bound_gfx_pipeline.copyRenderingState(&cmd.rnd_state);
        cmd.emitted_graphics_pipeline = bound_gfx_pipeline;
    };

    cmd.gfx_state.emitDirty(queue);
    cmd.rnd_state.emitDirty(queue);
    return true;
}

fn growIfNeeded(cmd: *CommandBuffer) !void {
    // TODO: grow native queue from the pool, we can avoid doing this until we have more complex scenes.
    _ = cmd;
}

pub fn reset(cmd: *CommandBuffer) void {
    cmd.queue.current_index = 0;
    cmd.gfx_state = .empty;
    cmd.rnd_state = .empty;
    cmd.bound_graphics_pipeline = null;
    cmd.emitted_graphics_pipeline = null;
    cmd.current_error = null;
    cmd.scope = .none;
    cmd.state = .initial;
}

pub fn notifyPending(cmd: *CommandBuffer) void {
    @atomicStore(backend.CommandBuffer.State, &cmd.state, .pending, .monotonic);
}

/// NOTE: Should we have a one-time submit?
pub fn notifyCompleted(cmd: *CommandBuffer) void {
    @atomicStore(backend.CommandBuffer.State, &cmd.state, .executable, .monotonic);
}

pub fn toHandle(image: *CommandBuffer) Handle {
    return @enumFromInt(@intFromPtr(image));
}

pub fn fromHandleMutable(handle: Handle) *CommandBuffer {
    return @as(*CommandBuffer, @ptrFromInt(@intFromEnum(handle)));
}

const CommandBuffer = @This();
const backend = @import("backend.zig");

const GraphicsState = backend.GraphicsState;
const RenderingState = backend.RenderingState;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
