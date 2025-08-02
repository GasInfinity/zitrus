pub const RenderingInfo = extern struct {
    todo_image_view_extents: mango.Extent2D,
    
    // Use image views for these
    color_attachment: zitrus.PhysicalAddress,
    depth_stencil_attachment: zitrus.PhysicalAddress,
};

pub const MultiDrawInfo = extern struct {
    first_vertex: u32,
    vertex_count: u32,
};

pub const MultiDrawIndexedInfo = extern struct {
    first_index: u32,
    index_count: u32,
    vertex_offset: u32,
};

const DirtyDynamicFlags = packed struct(u32) {
    index_config: bool = false,
    _: u31 = 0,
};

queue: cmd3d.Queue,
dirty: DirtyDynamicFlags = .{},

// TODO: this MUST use a mango.ImageView
// TODO: don't set registers here, have an updateDrawState for dynamic states also
pub fn beginRendering(cmd: *CommandBuffer, rendering_info: *const RenderingInfo) void {
    const queue = &cmd.queue;

    queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_invalidate, .init(.trigger));
    queue.addIncremental(internal_regs, .{
        &internal_regs.framebuffer.depth_buffer_location,
        &internal_regs.framebuffer.color_buffer_location,
        &internal_regs.framebuffer.render_buffer_dimensions,
    }, .{
        .fromPhysical(rendering_info.depth_stencil_attachment),
        .fromPhysical(rendering_info.color_attachment),
        .{
            .width = @intCast(rendering_info.todo_image_view_extents.width),
            .height_end = @intCast(rendering_info.todo_image_view_extents.height - 1),
            // TODO: Expose a flag for flipping?
            .flip_vertically = true,
        }
    });
}

pub fn endRendering(cmd: *CommandBuffer) void {
    const queue = &cmd.queue;

    queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_flush, .init(.trigger));
}

// TODO: use mango.Buffer

pub fn bindVertexBuffersSlice(cmd: *CommandBuffer, first_binding: u32, buffers: []const PhysicalAddress, offsets: []const u32) void {
    std.debug.assert(buffers.len == offsets.len);

    return cmd.bindVertexBuffers(first_binding, buffers.len, buffers.ptr, offsets.ptr);
}

pub fn bindVertexBuffers(cmd: *CommandBuffer, first_binding: u32, binding_count: u32, buffers: [*]const PhysicalAddress, offsets: [*]const u32) void {
    if(binding_count == 0) {
        return;
    }

    std.debug.assert(first_binding < internal_regs.geometry_pipeline.attribute_buffer.len and first_binding + binding_count <= internal_regs.geometry_pipeline.attribute_buffer.len);
    std.debug.assertReadable(std.mem.sliceAsBytes(buffers[0..binding_count]));
    std.debug.assertReadable(std.mem.sliceAsBytes(offsets[0..binding_count]));
    
    // XXX: Temporal, until mango.Buffer is implemented

    const queue = &cmd.queue; 

    for (0..binding_count) |i| {
        std.debug.assert(@intFromEnum(buffers[i]) >= zitrus.memory.arm11.vram_begin);
        const physical_offset = (@intFromEnum(buffers[i]) - zitrus.memory.arm11.vram_begin) + offsets[i];

        queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[first_binding + i].offset, physical_offset);
    }
}

pub fn bindIndexBuffer(cmd: *CommandBuffer, buffer: *mango.Buffer, offset: usize, index_type: mango.IndexType) void {
    _ = cmd;
    _ = buffer;
    _ = offset;
    _ = index_type;
}

pub fn draw(cmd: *CommandBuffer, vertex_count: u32, first_vertex: u32) void {
    return cmd.drawMultiSlice(&.{ .{ .first_vertex = first_vertex, .vertex_count = vertex_count } });
}

pub fn drawMultiSlice(cmd: *CommandBuffer, vertex_info: []const MultiDrawInfo) void {
    return cmd.drawMulti(vertex_info.len, vertex_info.ptr, @sizeOf(MultiDrawInfo));   
}

pub fn drawMulti(cmd: *CommandBuffer, draw_count: usize, vertex_info: [*]const MultiDrawInfo, stride: usize) void {
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

    // Drawing arrays always makes the index buffer registers dirty.
    cmd.dirty.index_config = true;
    
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

pub fn drawIndexed(cmd: *CommandBuffer, index_count: u32, first_index: u32, vertex_offset: u32) void {
    _ = cmd;
    _ = index_count;
    _ = first_index;
    _ = vertex_offset;
}

// TODO: Bind combined Samplers and ImageViews

// TODO: How should we approach immediate rendering, are 16 vertex attributes really needed?

fn updateDrawState(cmd: *CommandBuffer) void {
    if(cmd.dirty.index_config) {
    }

    cmd.dirty = .{};
}

const CommandBuffer = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
