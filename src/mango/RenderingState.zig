pub const UniformLocation = enum {
    float,
    int,
    bool,
};

pub const Dirty = packed struct(u32) {
    rendering_data: bool = false,
    vertex_buffers: bool = false,
    uniforms: u6 = 0,
    texture_units: u3 = 0,
    _: u21 = 0,

    pub fn setUniformsDirty(dirty: *Dirty, stage: mango.ShaderStage, location: UniformLocation) void {
        dirty.uniforms |= (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location)));
    }

    pub fn isUniformsDirty(dirty: Dirty, stage: mango.ShaderStage, location: UniformLocation) bool {
        return (dirty.uniforms & (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location)))) != 0;
    }

    pub fn isAnyUniformsDirty(dirty: Dirty) bool {
        return dirty.uniforms != 0;
    }

    pub fn setTextureUnitDirty(dirty: *Dirty, unit: u2) void {
        std.debug.assert(unit <= 2);
        dirty.texture_units |= (@as(u3, 1) << unit);
    }

    pub fn isTextureUnitDirty(dirty: Dirty, unit: u2) bool {
        std.debug.assert(unit <= 2);
        return (dirty.texture_units & (@as(u3, 1) << unit)) != 0;
    }

    pub fn isAnyTextureUnitDirty(dirty: *Dirty) bool {
        return dirty.texture_units != 0;
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
    floating_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Source.Constant, [4]f32)),
    integer_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Integral.Integer, [4]i8)),
    boolean_constants: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Integral.Boolean)),
};

pub const TextureUnitState = struct {
    pub const ImageInfo = packed struct(u32) {
        width: u11,
        height: u11,
        format: pica.TextureUnitFormat,
        base_mip_level: u3,
        levels_minus_one: u3,
    };

    info: [3]ImageInfo,
    address: [3]PhysicalAddress,
    sampler: [3]backend.Sampler,
};

pub const empty: RenderingState = .{
    .misc = undefined,
    .index_buffer_offset = undefined,
    .vertex_buffers_offset = undefined,
    .color_attachment = undefined,
    .depth_stencil_attachment = undefined,
    .framebuffer_dimensions = undefined,
    .uniform_state = undefined,
    .texture_unit_state = undefined,
    .dirty = .{},
};

misc: Misc,
index_buffer_offset: u28,
vertex_buffers_offset: [12]u28,

color_attachment: PhysicalAddress,
depth_stencil_attachment: PhysicalAddress,
framebuffer_dimensions: [2]u16 = undefined,

uniform_state: UniformState,
texture_unit_state: TextureUnitState,
dirty: Dirty,

pub fn beginRendering(rnd: *RenderingState, rendering_info: mango.RenderingInfo) void {
    const color_width: u16, const color_height: u16, const color_physical_address: PhysicalAddress = if (rendering_info.color_attachment != .null) info: {
        @branchHint(.likely);
        const color_attachment: backend.ImageView = .fromHandle(rendering_info.color_attachment);
        const color_rendering_info = color_attachment.getRenderingInfo(.color);

        break :info .{ color_rendering_info.width, color_rendering_info.height, color_rendering_info.address };
    } else .{ 0, 0, .fromAddress(0) };

    const depth_stencil_width: u16, const depth_stencil_height: u16, const depth_stencil_physical_address: PhysicalAddress = if (rendering_info.depth_stencil_attachment != .null) info: {
        const depth_stencil_attachment: backend.ImageView = .fromHandle(rendering_info.depth_stencil_attachment);
        const depth_stencil_rendering_info = depth_stencil_attachment.getRenderingInfo(.depth_stencil);

        break :info .{ depth_stencil_rendering_info.width, depth_stencil_rendering_info.height, depth_stencil_rendering_info.address };
    } else .{ 0, 0, .fromAddress(0) };

    if (color_physical_address != .zero and depth_stencil_physical_address != .zero) {
        std.debug.assert(color_width == depth_stencil_width and color_height == depth_stencil_height);
    }

    rnd.color_attachment = color_physical_address;
    rnd.depth_stencil_attachment = depth_stencil_physical_address;
    rnd.framebuffer_dimensions = if (color_physical_address != .zero)
        .{ color_width, color_height }
    else
        .{ depth_stencil_width, depth_stencil_height };

    rnd.dirty.rendering_data = true;
}

/// returns if any draw call has been issued between `beginRendering` and this call.
pub fn endRendering(rnd: *RenderingState) bool {
    defer rnd.dirty.rendering_data = false;

    // If this is not dirty then at least one draw call has been issued.
    return !rnd.dirty.rendering_data;
}

pub fn bindVertexBuffers(rnd: *RenderingState, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
    if (binding_count == 0) {
        return;
    }

    std.debug.assert(first_binding < p3d.geometry_pipeline.attributes.vertex_buffers.len and first_binding + binding_count <= p3d.geometry_pipeline.attributes.vertex_buffers.len);
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

        rnd.vertex_buffers_offset[current_binding] = @intCast(bound_vertex_offset);
    }

    rnd.misc.vertex_buffers_dirty_start, rnd.misc.vertex_buffers_dirty_end = if (rnd.dirty.vertex_buffers)
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

    if (uniforms.len == 0) {
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

pub fn bindCombinedImageSamplers(rnd: *RenderingState, first_combined: u32, combined_image_samplers: []const mango.CombinedImageSampler) void {
    std.debug.assert(first_combined + combined_image_samplers.len <= 3);

    for (combined_image_samplers, first_combined..) |unit, i| {
        const b_sampler: backend.Sampler = .fromHandle(unit.sampler);
        const b_image_view: backend.ImageView = .fromHandle(unit.image);
        const b_image: *backend.Image = .fromHandleMutable(b_image_view.data.image);

        rnd.texture_unit_state.sampler[i] = b_sampler;
        rnd.texture_unit_state.address[i] = b_image.memory_info.boundPhysicalAddress();
        rnd.texture_unit_state.info[i] = .{
            .width = @intCast(b_image.info.width()),
            .height = @intCast(b_image.info.height()),
            .format = b_image_view.data.format().nativeTextureUnitFormat(),
            .base_mip_level = b_image_view.data.base_mip_level,
            .levels_minus_one = b_image_view.data.levels_minus_one,
        };
        rnd.dirty.setTextureUnitDirty(@intCast(i));
    }
}

pub fn emitDirty(rnd: *RenderingState, queue: *command.Queue) void {
    const dirty = &rnd.dirty;

    if (dirty.isAnyUniformsDirty()) {
        queue.add(p3d, &p3d.geometry_pipeline.start_draw_function, .init(.config));
        defer queue.add(p3d, &p3d.geometry_pipeline.start_draw_function, .init(.drawing));

        if (dirty.isUniformsDirty(.vertex, .bool)) {
            queue.add(p3d, &p3d.vertex_shader.bool_uniform, @bitCast(@as(u32, 0x7FFF0000) | @as(u16, @bitCast(rnd.uniform_state.boolean_constants.get(.vertex).bits))));
        }

        if (dirty.isUniformsDirty(.geometry, .bool)) {
            queue.add(p3d, &p3d.geometry_shader.bool_uniform, @bitCast(@as(u32, 0x7FFF0000) | @as(u16, @bitCast(rnd.uniform_state.boolean_constants.get(.geometry).bits))));
        }

        if (dirty.isUniformsDirty(.vertex, .int)) {
            queue.add(p3d, &p3d.vertex_shader.int_uniform[0..4].*, rnd.uniform_state.integer_constants.get(.vertex).values);
        }

        if (dirty.isUniformsDirty(.geometry, .int)) {
            queue.add(p3d, &p3d.geometry_shader.int_uniform[0..4].*, rnd.uniform_state.integer_constants.get(.geometry).values);
        }

        if (dirty.isUniformsDirty(.vertex, .float)) {
            emitFloatUniforms(rnd.uniform_state.floating_dirty.get(.vertex), rnd.uniform_state.floating_constants.get(.vertex), &p3d.vertex_shader, queue);
        }

        if (dirty.isUniformsDirty(.geometry, .float)) {
            emitFloatUniforms(rnd.uniform_state.floating_dirty.get(.geometry), rnd.uniform_state.floating_constants.get(.geometry), &p3d.geometry_shader, queue);
        }
    }

    if (dirty.isAnyTextureUnitDirty()) {
        inline for (0..3) |unit| if (dirty.isTextureUnitDirty(unit)) switch (unit) {
            0 => {
                // TODO: Cubemaps, Shadow, Projected textures

                const unit_info = rnd.texture_unit_state.info[unit];
                const unit_address = rnd.texture_unit_state.address[unit];
                const unit_sampler = rnd.texture_unit_state.sampler[unit];

                queue.addIncremental(p3d, .{
                    &p3d.texturing.@"0".border_color,
                    &p3d.texturing.@"0".dimensions,
                    &p3d.texturing.@"0".parameters,
                    &p3d.texturing.@"0".lod,
                    &p3d.texturing.@"0".address[0],
                }, .{
                    .{ unit_sampler.data.border_color_r, unit_sampler.data.border_color_g, unit_sampler.data.border_color_b, unit_sampler.data.border_color_a },
                    .{ unit_info.width, unit_info.height },
                    .{
                        .mag_filter = unit_sampler.data.mag_filter,
                        .min_filter = unit_sampler.data.min_filter,
                        .etc1 = if (unit_info.format == .etc1) .etc1 else .none,
                        .wrap_t = unit_sampler.data.address_mode_u,
                        .wrap_s = unit_sampler.data.address_mode_v,
                        .is_shadow = false,
                        .mip_filter = unit_sampler.data.mip_filter,
                        .type = .@"2d",
                    },
                    .{
                        .bias = unit_sampler.data.lod_bias,
                        .max_level_of_detail = @min(unit_info.levels_minus_one, unit_sampler.data.max_lod),
                        .min_level_of_detail = @max(unit_info.base_mip_level, unit_sampler.data.min_lod),
                    },
                    .fromPhysical(unit_address),
                });

                queue.add(p3d, &p3d.texturing.@"0".format, .init(unit_info.format));
            },
            1, 2 => {
                const unit_reg = switch (unit) {
                    1 => &p3d.texturing.@"1",
                    2 => &p3d.texturing.@"2",
                    else => unreachable,
                };

                const unit_info = rnd.texture_unit_state.info[unit];
                const unit_address = rnd.texture_unit_state.address[unit];
                const unit_sampler = rnd.texture_unit_state.sampler[unit];

                queue.addIncremental(p3d, .{
                    &unit_reg.border_color,
                    &unit_reg.dimensions,
                    &unit_reg.parameters,
                    &unit_reg.lod,
                    &unit_reg.address,
                    &unit_reg.format,
                }, .{
                    .{ unit_sampler.data.border_color_r, unit_sampler.data.border_color_g, unit_sampler.data.border_color_b, unit_sampler.data.border_color_a },
                    .{ unit_info.width, unit_info.height },
                    .{
                        .mag_filter = unit_sampler.data.mag_filter,
                        .min_filter = unit_sampler.data.min_filter,
                        .etc1 = if (unit_info.format == .etc1) .etc1 else .none,
                        .wrap_t = unit_sampler.data.address_mode_u,
                        .wrap_s = unit_sampler.data.address_mode_v,
                        .is_shadow = false,
                        .mip_filter = unit_sampler.data.mip_filter,
                        .type = .@"2d",
                    },
                    .{
                        .bias = unit_sampler.data.lod_bias,
                        .max_level_of_detail = @min(unit_info.levels_minus_one, unit_sampler.data.max_lod),
                        .min_level_of_detail = @max(unit_info.base_mip_level, unit_sampler.data.min_lod),
                    },
                    .fromPhysical(unit_address),
                    .init(unit_info.format),
                });
            },
            else => unreachable,
        };

        queue.addMasked(p3d, &p3d.texturing.config, .{
            .texture_enabled = .splat(false),
            .texture_3_coordinates = .@"0",
            .texture_3_enabled = false,
            .texture_2_coordinates = .@"1",
            .clear_texture_cache = true, // NOTE: Not affected by the mask
        }, 0b0100);
    }

    if (dirty.vertex_buffers) {
        for (rnd.misc.vertex_buffers_dirty_start..rnd.misc.vertex_buffers_dirty_end) |current_binding| {
            queue.add(p3d, &p3d.geometry_pipeline.attributes.vertex_buffers[current_binding].offset, .init(rnd.vertex_buffers_offset[current_binding]));
        }
    }

    if (dirty.rendering_data) {
        queue.add(p3d, &p3d.framebuffer.invalidate, .init(.trigger));
        queue.addIncremental(p3d, .{
            &p3d.framebuffer.depth_location,
            &p3d.framebuffer.color_location,
            &p3d.framebuffer.dimensions,
        }, .{
            .fromPhysical(rnd.depth_stencil_attachment),
            .fromPhysical(rnd.color_attachment),
            .{
                .width = @intCast(rnd.framebuffer_dimensions[0]),
                .height_end = @intCast(rnd.framebuffer_dimensions[1] - 1),
                // TODO: Expose a flag for flipping?
                .flip_vertically = true,
            },
        });
    }

    dirty.* = .{};
}

fn emitFloatUniforms(flt_dirty: std.EnumSet(pica.shader.register.Source.Constant), flt_constants: std.EnumArray(pica.shader.register.Source.Constant, [4]f32), comptime shader: *pica.Graphics.Shader, queue: *command.Queue) void {
    var last_const: ?pica.shader.register.Source.Constant = null;

    var it = flt_dirty.iterator();
    while (it.next()) |f| {
        if (last_const == null or (@intFromEnum(last_const.?) > @intFromEnum(f)) or (@intFromEnum(f) - @intFromEnum(last_const.?)) != 1) {
            queue.add(p3d, &shader.float_uniform_index, .{
                .index = f,
                .mode = .f8_23,
            });
        }

        queue.add(p3d, &shader.float_uniform_data[0..4].*, @bitCast(flt_constants.get(f)));
        last_const = f;
    }
}

const RenderingState = @This();

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const pica = zitrus.hardware.pica;
const PhysicalAddress = zitrus.hardware.PhysicalAddress;

const command = pica.command;

const p3d = &zitrus.memory.arm11.pica.p3d;
