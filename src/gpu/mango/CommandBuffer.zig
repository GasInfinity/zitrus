//! Records 3D commands to be submitted to the PICA200.
//!
//! As the PICA200 is limited to what it can do with 3D drawing commands,
//! things like clearing an `Image` or copying data is done with the `Device`.

pub const RenderingInfo = extern struct {
    // TODO: This is why we want handles
    color_attachment: ?*mango.ImageView,
    depth_stencil_attachment: ?*mango.ImageView,
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

const DirtyDynamicFlags = packed struct(u32) {
    primitive_topology: bool = false,
    cull_mode: bool = false,
    depth_map_mode: bool = false,
    depth_map_parameters: bool = false,
    viewport_parameters: bool = false,
    scissor_parameters: bool = false,
    vertex_buffers: bool = false,
    _: u25 = 0,
};

const DynamicData = struct {
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

    pub const Misc = packed struct {
        primitive_topology: gpu.PrimitiveTopology,
        cull_mode_ccw: gpu.CullMode,
        is_front_ccw: bool,
        index_format: gpu.IndexFormat,
        depth_mode: gpu.DepthMapMode,
        depth_bias_enabled: bool, 
        is_scissor_inside: bool,
    };

    misc: Misc = undefined, 
    depth_map_parameters: DepthParameters = undefined, 
    viewport: Viewport = undefined,
    scissor: Scissor = undefined,
    bound_index_buffer_offset: u28 = undefined,
    bound_vertex_buffers_offset: [12]u32 = undefined,
    bound_vertex_buffers_dirty_start: u8 = undefined,
    bound_vertex_buffers_dirty_end: u8 = undefined,
};

queue: cmd3d.Queue,
dynamic_state: DynamicData = .{},
dirty: DirtyDynamicFlags = .{},
state: State = .initial,
scope: Scope = .none,

pub fn begin(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .initial);
    cmd.state = .recording;
}

pub fn end(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .recording);
    cmd.state = .executable;
}

// TODO: should we cache this also?
pub fn beginRendering(cmd: *CommandBuffer, rendering_info: *const RenderingInfo) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .none);

    if(rendering_info.depth_stencil_attachment) |depth_stencil| {
        if(rendering_info.color_attachment) |color| {
            std.debug.assert(depth_stencil.image.info.width() == color.image.info.width() and depth_stencil.image.info.height() == color.image.info.height());
        }
    }

    const width, const height = if(rendering_info.color_attachment) |color| 
        .{ color.image.info.width(), color.image.info.height() }
    else if(rendering_info.depth_stencil_attachment) |depth_stencil|
        .{ depth_stencil.image.info.width(), depth_stencil.image.info.height() }
    else unreachable;

    const queue = &cmd.queue;

    queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_invalidate, .init(.trigger));
    queue.addIncremental(internal_regs, .{
        &internal_regs.framebuffer.depth_buffer_location,
        &internal_regs.framebuffer.color_buffer_location,
        &internal_regs.framebuffer.render_buffer_dimensions,
    }, .{
        .fromPhysical(if(rendering_info.depth_stencil_attachment) |depth_stencil| depth_stencil.image.address else .zero),
        .fromPhysical(if(rendering_info.color_attachment) |color| color.image.address else .zero),
        .{
            .width = @intCast(width),
            .height_end = @intCast(height - 1),
            // TODO: Expose a flag for flipping?
            .flip_vertically = true,
        }
    });
    cmd.scope = .render_pass;
}

pub fn endRendering(cmd: *CommandBuffer) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);
    const queue = &cmd.queue;

    queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_flush, .init(.trigger));
    cmd.scope = .none;
}

pub fn bindVertexBuffersSlice(cmd: *CommandBuffer, first_binding: u32, buffers: []const *mango.Buffer, offsets: []const u32) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(buffers.len == offsets.len);

    return cmd.bindVertexBuffers(first_binding, buffers.len, buffers.ptr, offsets.ptr);
}

pub fn bindVertexBuffers(cmd: *CommandBuffer, first_binding: u32, binding_count: u32, buffers: [*]const *mango.Buffer, offsets: [*]const u32) void {
    std.debug.assert(cmd.state == .recording);
    if(binding_count == 0) {
        return;
    }

    std.debug.assert(first_binding < internal_regs.geometry_pipeline.attribute_buffer.len and first_binding + binding_count <= internal_regs.geometry_pipeline.attribute_buffer.len);
    std.debug.assertReadable(std.mem.sliceAsBytes(buffers[0..binding_count]));
    std.debug.assertReadable(std.mem.sliceAsBytes(offsets[0..binding_count]));
    
    const dynamic_state = &cmd.dynamic_state;

    var dirty_vertex_buffers = false;
    for (0..binding_count) |i| {
        const current_binding = first_binding + i;
        const offset = offsets[i];
        const buffer = buffers[i];

        std.debug.assert(offset <= buffer.size);
        std.debug.assert(buffer.usage.vertex_buffer);

        const bound_vertex_offset = (@intFromEnum(buffers[i].address) - @intFromEnum(mango.global_attribute_buffer_base)) + offsets[i];

        dirty_vertex_buffers = dirty_vertex_buffers or dynamic_state.bound_vertex_buffers_offset[current_binding] != bound_vertex_offset;
        dynamic_state.bound_vertex_buffers_offset[current_binding] = bound_vertex_offset;
    }

    cmd.dynamic_state.bound_vertex_buffers_dirty_start, cmd.dynamic_state.bound_vertex_buffers_dirty_end = if(cmd.dirty.vertex_buffers)
        .{ @intCast(@min(first_binding, dynamic_state.bound_vertex_buffers_dirty_start)), @intCast(@max(first_binding + binding_count, dynamic_state.bound_vertex_buffers_dirty_end)) }
    else 
        .{ @intCast(first_binding), @intCast(first_binding + binding_count) };

    cmd.dirty.vertex_buffers = dirty_vertex_buffers;
}

pub fn bindIndexBuffer(cmd: *CommandBuffer, buffer: *mango.Buffer, offset: usize, index_type: mango.IndexType) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(offset <= buffer.size);
    std.debug.assert(buffer.usage.index_buffer);

    cmd.dynamic_state.misc.index_format = index_type.native();
    cmd.dynamic_state.bound_index_buffer_offset = @intCast(@intFromEnum(buffer.address) - @intFromEnum(mango.global_attribute_buffer_base));
}

pub fn draw(cmd: *CommandBuffer, vertex_count: u32, first_vertex: u32) void {
    return cmd.drawMultiSlice(&.{ .{ .first_vertex = first_vertex, .vertex_count = vertex_count } });
}

pub fn drawMultiSlice(cmd: *CommandBuffer, vertex_info: []const MultiDrawInfo) void {
    return cmd.drawMulti(vertex_info.len, vertex_info.ptr, @sizeOf(MultiDrawInfo));   
}

pub fn drawMulti(cmd: *CommandBuffer, draw_count: usize, vertex_info: [*]const MultiDrawInfo, stride: usize) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if(draw_count == 0) {
        return;
    }

    std.debug.assert(stride >= @sizeOf(MultiDrawInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&vertex_info[0]));

    cmd.updateDrawState();

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
    var current_vertex_info_ptr: *const MultiDrawInfo = @alignCast(@ptrCast(@as([*]const u8, @ptrCast(vertex_info)) + stride));
    
    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_vertex_info_ptr));

        const current_vertex_info = current_vertex_info_ptr.*;
        
        if(current_vertex_info.vertex_count != last_vertex_info.vertex_count) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_num_vertices, current_vertex_info.vertex_count);
        }

        if(current_vertex_info.first_vertex != last_vertex_info.first_vertex) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_first_index, current_vertex_info.first_vertex);
        }

        queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_arrays, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

        last_vertex_info = current_vertex_info;
        current_vertex_info_ptr = @alignCast(@ptrCast(@as([*]const u8, @ptrCast(current_vertex_info_ptr)) + stride));
    }
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{ .inputting_vertices_or_draw_arrays = false }, 0b0001);
}

pub fn drawIndexed(cmd: *CommandBuffer, index_count: u32, first_index: u32, vertex_offset: i32) void {
    return cmd.drawMultiIndexedSlice(&.{ .{ .first_index = first_index, .index_count = index_count, .vertex_offset = vertex_offset } });
}

pub fn drawMultiIndexedSlice(cmd: *CommandBuffer, index_info: []const MultiDrawIndexedInfo) void {
    return cmd.drawMultiIndexed(index_info.len, index_info.ptr, @sizeOf(MultiDrawIndexedInfo));   
}

pub fn drawMultiIndexed(cmd: *CommandBuffer, draw_count: usize, index_info: [*]const MultiDrawIndexedInfo, stride: usize) void {
    std.debug.assert(cmd.state == .recording);
    std.debug.assert(cmd.scope == .render_pass);

    if(draw_count == 0) {
        return;
    }

    std.debug.assert(stride >= @sizeOf(MultiDrawIndexedInfo) and std.mem.isAligned(stride, 4));
    std.debug.assertReadable(std.mem.asBytes(&index_info[0]));

    cmd.updateDrawState();

    const queue = &cmd.queue;
    const dynamic_state = cmd.dynamic_state;

    const first_draw = index_info[0];
    queue.addIncremental(internal_regs, .{
        &internal_regs.geometry_pipeline.attribute_buffer_index_buffer,
        &internal_regs.geometry_pipeline.attribute_buffer_num_vertices,
    }, .{
        .{
            .base_offset = @intCast(dynamic_state.bound_index_buffer_offset + first_draw.first_index),
            .format = dynamic_state.misc.index_format,
        },
        first_draw.index_count,
    });

    if(first_draw.vertex_offset != 0) {
        // TODO: offset bound vertex buffers by the stride, for that we need the stride when (TODO) binding a pipeline
        @panic("TODO");
    }

    queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_elements, .init(.trigger));
    queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

    // NOTE: Seems to be needed, weird things happens if we don't write these?
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
    queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

    var last_index_info = first_draw;
    var current_index_info_ptr: *const MultiDrawIndexedInfo = @alignCast(@ptrCast(@as([*]const u8, @ptrCast(index_info)) + stride));
    
    for (1..draw_count) |_| {
        std.debug.assertReadable(std.mem.asBytes(current_index_info_ptr));

        const current_index_info = current_index_info_ptr.*;
        
        if(current_index_info.index_count != last_index_info.index_count) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_num_vertices, current_index_info.index_count);
        }

        if(current_index_info.first_index != last_index_info.first_index) {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_index_buffer, .{
                .base_offset = @intCast(dynamic_state.bound_index_buffer_offset + current_index_info.first_index),
                .format = dynamic_state.misc.index_format,
            });
        }

        if(current_index_info.vertex_offset != last_index_info.vertex_offset) {
            // TODO: offset bound vertex buffers by the stride, for that we need the stride when (TODO) binding a pipeline
            @panic("TODO");
        }

        queue.add(internal_regs, &internal_regs.geometry_pipeline.restart_primitive, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer_draw_elements, .init(.trigger));
        queue.add(internal_regs, &internal_regs.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));

        // NOTE: See above
        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);
        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{ .total_vertex_outputs = 0, .topology = .triangle_list }, 0b1000);

        last_index_info = current_index_info;
        current_index_info_ptr = @alignCast(@ptrCast(@as([*]const u8, @ptrCast(current_index_info_ptr)) + stride));
    }
}

// TODO: Bind combined Samplers and ImageViews
// TODO: How should we approach immediate rendering, are 16 vertex attributes really needed?

pub fn setCullMode(cmd: *CommandBuffer, cull_mode: mango.CullMode) void {
    std.debug.assert(cmd.state == .recording);
    const native_cull_mode_ccw = cull_mode.native(.ccw);

    cmd.dirty.cull_mode = cmd.dynamic_state.misc.cull_mode_ccw != native_cull_mode_ccw;
    cmd.dynamic_state.misc.cull_mode_ccw = native_cull_mode_ccw;
}

pub fn setFrontFace(cmd: *CommandBuffer, front_face: mango.FrontFace) void {
    std.debug.assert(cmd.state == .recording);
    const front_ccw = switch (front_face) {
        .ccw => true,
        .cw => false,
    };

    cmd.dirty.cull_mode = cmd.dynamic_state.misc.is_front_ccw != front_ccw;
    cmd.dynamic_state.misc.is_front_ccw = front_ccw;
}

pub fn setPrimitiveTopology(cmd: *CommandBuffer, primitive_topology: mango.PrimitiveTopology) void {
    std.debug.assert(cmd.state == .recording);
    const native_primitive_topology = primitive_topology.native();

    cmd.dirty.primitive_topology = cmd.dynamic_state.misc.primitive_topology != native_primitive_topology;
    cmd.dynamic_state.misc.primitive_topology = native_primitive_topology;
}

pub fn setViewport(cmd: *CommandBuffer, viewport: *const mango.Viewport) void {
    std.debug.assert(cmd.state == .recording);
    const dynamic_state = &cmd.dynamic_state;
    const dirty = &cmd.dirty;

    const viewport_x: u10 = @intCast(viewport.rect.offset.x);
    const viewport_y: u10 = @intCast(viewport.rect.offset.y);
    const viewport_width_minus_one: u10 = @intCast(viewport.rect.extent.width - 1);
    const viewport_height_minus_one: u10 = @intCast(viewport.rect.extent.height - 1);
    
    dirty.viewport_parameters = dynamic_state.viewport.x != viewport_x or dynamic_state.viewport.y != viewport_y or dynamic_state.viewport.width != viewport_width_minus_one or dynamic_state.viewport.height != viewport_height_minus_one.height;
    dynamic_state.viewport.x = viewport_x;
    dynamic_state.viewport.y = viewport_x;
    dynamic_state.viewport.width_minus_one = viewport_width_minus_one;
    dynamic_state.viewport.height_minus_one = viewport_height_minus_one;

    dirty.depth_map_parameters = dynamic_state.depth_map_parameters.min_depth != viewport.min_depth or dynamic_state.depth_map_parameters.max_depth != viewport.max_depth;
    dynamic_state.depth_map_parameters.min_depth = viewport.min_depth;
    dynamic_state.depth_map_parameters.max_depth = viewport.max_depth;
}

pub fn setScissor(cmd: *CommandBuffer, scissor: *const mango.Scissor) void {
    std.debug.assert(cmd.state == .recording);
    const dynamic_state = &cmd.dynamic_state;
    const dirty = &cmd.dirty;
    
    const new_scissor: DynamicData.Scissor = .{
        .x = @intCast(scissor.rect.offset.x),
        .y = @intCast(scissor.rect.offset.y),
        .end_x = .x + @as(u10, @intCast(scissor.rect.extent.width - 1)),
        .end_y = .y + @as(u10, @intCast(scissor.rect.extent.height - 1)),
    };

    const is_inside = switch (scissor.mode) {
        .inside => true,
        .outside => false,
    };

    dirty.scissor_parameters = dynamic_state.scissor != new_scissor or dynamic_state.misc.is_scissor_inside != is_inside;
    dynamic_state.scissor = new_scissor;
    dynamic_state.misc.is_scissor_inside = is_inside;
}

fn updateDrawState(cmd: *CommandBuffer) void {
    const queue = &cmd.queue;
    const dynamic_state = &cmd.dynamic_state;
    const dirty = &cmd.dirty;

    if(dirty.vertex_buffers) {
        for (dynamic_state.bound_vertex_buffers_dirty_start..dynamic_state.bound_vertex_buffers_dirty_end) |current_binding| {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[current_binding].offset, dynamic_state.bound_vertex_buffers_offset[current_binding]);
        }        
    }

    if(dirty.cull_mode) {
        const cull_mode_ccw = dynamic_state.misc.cull_mode_ccw;
        const is_front_ccw = dynamic_state.misc.is_front_ccw;

        queue.add(internal_regs, &internal_regs.rasterizer.faceculling_config, .init(if(is_front_ccw)
            cull_mode_ccw
        else
            switch (cull_mode_ccw) {
                .none => .none,
                .front_ccw => .back_ccw,
                .back_ccw => .front_ccw,
            }));
    }

    if(dirty.viewport_parameters) {
        const flt_width = @as(f32, @floatFromInt(dynamic_state.viewport.width_minus_one)) + 1.0;
        const flt_height = @as(f32, @floatFromInt(dynamic_state.viewport.height_minus_one)) + 1.0;

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
            .x = dynamic_state.viewport.x,
            .y = dynamic_state.viewport.y,
        }); 
    }

    if(dirty.scissor_parameters) {
        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.scissor_config,
            &internal_regs.rasterizer.scissor_start,
            &internal_regs.rasterizer.scissor_end,
        }, .{
            .init(if(dynamic_state.misc.is_scissor_inside) .inside else .outside),
            .{ .x = dynamic_state.scissor.x, .y = dynamic_state.scissor.y },
            .{ .x = dynamic_state.scissor.end_x, .y = dynamic_state.scissor.end_y },
        }); 
    }

    if(dirty.depth_map_mode) {
        queue.add(internal_regs, &internal_regs.rasterizer.depth_map_mode, .init(dynamic_state.misc.depth_mode));
    }

    if (dirty.depth_map_parameters) {
        const depth_map_scale = (dynamic_state.depth_map_parameters.min_depth - dynamic_state.depth_map_parameters.max_depth); 
        const depth_map_offset = dynamic_state.depth_map_parameters.min_depth + (if(dynamic_state.misc.depth_bias_enabled)
            dynamic_state.depth_map_parameters.constant
        else
            0);

        queue.addIncremental(internal_regs, .{
            &internal_regs.rasterizer.depth_map_scale,
            &internal_regs.rasterizer.depth_map_offset,
        }, .{
            .init(.of(depth_map_scale)),
            .init(.of(depth_map_offset)),
        });
    }

    if(dirty.primitive_topology) {
        const primitive_topology = dynamic_state.misc.primitive_topology;

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{
            .total_vertex_outputs = 0, // NOTE: Ignored by mask
            .topology = primitive_topology,
        }, 0b0010);

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config, .{
            .geometry_shader_usage = .disabled,// NOTE: Ignored by mask
            .drawing_triangles = primitive_topology == .triangle_list,
            .use_reserved_geometry_subdivision = false, // NOTE: Ignored by mask
        }, 0b0010);

        queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{
            .drawing_triangles = primitive_topology == .triangle_list, // NOTE: Ignored by mask
        }, 0b0010); 
    }

    dirty.* = .{};
}

const CommandBuffer = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
