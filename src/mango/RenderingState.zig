const UniformLocation = enum {
    float,
    int,
    bool,
};

pub const Dirty = packed struct(u32) {
    rendering_data: bool = false,
    vertex_buffers: bool = false,
    uniforms: u6 = 0,

    _: u24 = 0,

    pub fn setUniformsDirty(dirty: *Dirty, stage: mango.ShaderStage, location: UniformLocation) void {
        dirty.uniforms |= (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location))); 
    }

    pub fn isUniformsDirty(dirty: Dirty, stage: mango.ShaderStage, location: UniformLocation) bool {
        return (dirty.uniforms & (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location)))) != 0; 
    }

    pub fn isAnyUniformsDirty(dirty: Dirty) bool {
        return dirty.uniforms != 0;
    }
};

pub const Misc = packed struct {
    vertex_buffers_dirty_start: u8,
    vertex_buffers_dirty_end: u8,
    index_format: pica.IndexFormat,
};

pub const UniformState = struct {
    floating_dirty: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Source.Constant)) = .initFill(.initEmpty()),

    // NOTE: Stored in reverse order (wzyx, PICA200 native)
    floating_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Source.Constant, [4]f32)) = .initUndefined(),
    integer_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Integral.Integer, [4]i8)) = .initUndefined(),
    boolean_constants: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Integral.Boolean)) = .initUndefined(),
};

misc: Misc = undefined,
index_buffer_offset: u28 = undefined,
vertex_buffers_offset: [12]u32 = undefined,

color_attachment: PhysicalAddress = undefined,
depth_stencil_attachment: PhysicalAddress = undefined,
dimensions: pica.U16x2 = undefined,

uniform_state: UniformState = .{},
dirty: Dirty = .{},

pub fn bindVertexBuffers(rnd: *RenderingState, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
    if(binding_count == 0) {
        return;
    }

    std.debug.assert(first_binding < internal_regs.geometry_pipeline.attribute_buffer.len and first_binding + binding_count <= internal_regs.geometry_pipeline.attribute_buffer.len);
    std.debug.assertReadable(std.mem.sliceAsBytes(buffers[0..binding_count]));
    std.debug.assertReadable(std.mem.sliceAsBytes(offsets[0..binding_count]));
    
    for (0..binding_count) |i| {
        const current_binding = first_binding + i;
        const offset = offsets[i];
        const buffer: backend.Buffer = .fromHandle(buffers[i]);

        std.debug.assert(offset <= buffer.size);
        std.debug.assert(buffer.usage.vertex_buffer);

        const buffer_physical_address = buffer.memory_info.boundPhysicalAddress();
        const bound_vertex_offset = (@intFromEnum(buffer_physical_address) - @intFromEnum(backend.global_attribute_buffer_base)) + offset;

        rnd.vertex_buffers_offset[current_binding] = bound_vertex_offset;
    }

    rnd.misc.vertex_buffers_dirty_start, rnd.misc.vertex_buffers_dirty_end = if(rnd.dirty.vertex_buffers)
        .{ @intCast(@min(first_binding, rnd.misc.vertex_buffers_dirty_start)), @intCast(@max(first_binding + binding_count, rnd.misc.vertex_buffers_dirty_end)) }
    else 
        .{ @intCast(first_binding), @intCast(first_binding + binding_count) };

    rnd.dirty.vertex_buffers = true;
}

pub fn bindIndexBuffer(rnd: *RenderingState, buffer: mango.Buffer, offset: u32, index_type: mango.IndexType) void {
    const index_buffer: backend.Buffer = .fromHandle(buffer);

    std.debug.assert(offset <= index_buffer.size);
    std.debug.assert(index_buffer.usage.index_buffer);

    const index_buffer_address: u32 = @intFromEnum(index_buffer.memory_info.boundPhysicalAddress()) + offset;

    rnd.misc.index_format = index_type.native();
    rnd.index_buffer_offset = @intCast(index_buffer_address - @intFromEnum(backend.global_attribute_buffer_base));
}

pub fn bindFloatUniforms(rnd: *RenderingState, stage: mango.ShaderStage, first_uniform: u32, uniforms: []const [4]f32) void {
    std.debug.assert(first_uniform + uniforms.len <= 96);

    if(uniforms.len == 0) {
        return;
    }

    rnd.uniform_state.floating_dirty.getPtr(stage).bits.setRangeValue(.{
        .start = first_uniform,
        .end = first_uniform + @as(u32, @intCast(uniforms.len)),
    }, true);

    const flt_values = &rnd.uniform_state.floating_constants.getPtr(stage).values;
    @memcpy(flt_values[first_uniform..][0..uniforms.len], uniforms);

    for (first_uniform..(first_uniform + uniforms.len)) |i| {
        std.mem.reverse(f32, &flt_values[i]);
    }

    rnd.dirty.setUniformsDirty(stage, .float); 
}

pub fn emitDirty(rnd: *RenderingState, queue: *cmd3d.Queue) void {
    const dirty = &rnd.dirty;

    if(dirty.isAnyUniformsDirty()) {
        queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .config);

        if(dirty.isUniformsDirty(.vertex, .bool)) {
            queue.add(internal_regs, &internal_regs.vertex_shader.bool_uniform, @bitCast(@as(u32, 0x7FFF0000) | @as(u16, @bitCast(rnd.uniform_state.boolean_constants.get(.vertex).bits))));
        }

        if(dirty.isUniformsDirty(.geometry, .bool)) {
            queue.add(internal_regs, &internal_regs.geometry_shader.bool_uniform, @bitCast(@as(u32, 0x7FFF0000) | @as(u16, @bitCast(rnd.uniform_state.boolean_constants.get(.geometry).bits))));
        }

        if(dirty.isUniformsDirty(.vertex, .int)) {
            queue.add(internal_regs, &internal_regs.vertex_shader.int_uniform[0..4].*, rnd.uniform_state.integer_constants.get(.vertex).values);
        }

        if(dirty.isUniformsDirty(.geometry, .int)) {
            queue.add(internal_regs, &internal_regs.geometry_shader.int_uniform[0..4].*, rnd.uniform_state.integer_constants.get(.geometry).values);
        }

        if(dirty.isUniformsDirty(.vertex, .float)) {
            emitFloatUniforms(rnd.uniform_state.floating_dirty.get(.vertex), rnd.uniform_state.floating_constants.get(.vertex), &internal_regs.vertex_shader, queue);
        }

        if(dirty.isUniformsDirty(.geometry, .float)) {
            emitFloatUniforms(rnd.uniform_state.floating_dirty.get(.geometry), rnd.uniform_state.floating_constants.get(.geometry), &internal_regs.geometry_shader, queue);
        }

        queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .drawing);
    }

    if(dirty.vertex_buffers) {
        for (rnd.misc.vertex_buffers_dirty_start..rnd.misc.vertex_buffers_dirty_end) |current_binding| {
            queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[current_binding].offset, rnd.vertex_buffers_offset[current_binding]);
        }
    }

    if(dirty.rendering_data) {
        queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_invalidate, .init(.trigger));
        queue.addIncremental(internal_regs, .{
            &internal_regs.framebuffer.depth_buffer_location,
            &internal_regs.framebuffer.color_buffer_location,
            &internal_regs.framebuffer.render_buffer_dimensions,
        }, .{
            .fromPhysical(rnd.depth_stencil_attachment),
            .fromPhysical(rnd.color_attachment),
            .{
                .width = @intCast(rnd.dimensions.x),
                .height_end = @intCast(rnd.dimensions.y - 1),
                // TODO: Expose a flag for flipping?
                .flip_vertically = true,
            }
        });
    }

    dirty.* = .{};
}

fn emitFloatUniforms(flt_dirty: std.EnumSet(pica.shader.register.Source.Constant), flt_constants: std.EnumArray(pica.shader.register.Source.Constant, [4]f32), comptime shader: *pica.Registers.Internal.Shader, queue: *cmd3d.Queue) void {
    var last_const: ?pica.shader.register.Source.Constant = null;

    var it = flt_dirty.iterator();
    while (it.next()) |f| {
        if(last_const == null or (@intFromEnum(last_const.?) > @intFromEnum(f)) or (@intFromEnum(f) - @intFromEnum(last_const.?)) != 1) {
            queue.add(internal_regs, &shader.float_uniform_index, .{
                .index = f,
                .mode = .f8_23,
            });
        }

        queue.add(internal_regs, &shader.float_uniform_data[0..4].*, @bitCast(flt_constants.get(f)));
        last_const = f;
    }  
}

const RenderingState = @This();

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
