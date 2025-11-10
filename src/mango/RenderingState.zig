pub const UniformLocation = enum {
    float,
    int,
    bool,
};

pub const Dirty = packed struct(u32) {
    begin_rendering: bool = false,
    vertex_buffers: bool = false,
    uniforms: u6 = 0,
    texture_units: u3 = 0,
    light_environment_factors: bool = false,
    light_parameters: bool = false,
    light_factors: bool = false,
    _: u18 = 0,

    pub fn setUniformsDirty(dirty: *Dirty, stage: mango.ShaderStage, location: UniformLocation) void {
        dirty.uniforms |= (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location)));
    }

    pub fn isUniformsDirty(dirty: Dirty, stage: mango.ShaderStage, location: UniformLocation) bool {
        return (dirty.uniforms & (@as(u6, 1) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len + @intFromEnum(location)))) != 0;
    }

    pub fn isStageUniformsDirty(dirty: Dirty, stage: mango.ShaderStage) bool {
        return (dirty.uniforms & (@as(u6, 0b111) << @intCast(@intFromEnum(stage) * std.enums.values(UniformLocation).len))) != 0;
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
    pub const empty: Misc = .{};

    vertex_buffers_dirty_start: u8 = 0,
    vertex_buffers_dirty_end: u8 = 0,
    index_format: pica.IndexFormat = .u8,
};

pub const UniformState = struct {
    floating_dirty: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Source.Constant)) = .initFill(.initEmpty()),

    // Stored as XYZW
    floating_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Source.Constant, [4]f32)),
    // Stored as XYZW
    integer_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Integral.Integer, [4]u8)),
    boolean_constants: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Integral.Boolean)),
};

pub const TextureUnitState = struct {
    view: backend.ImageView,
    sampler: backend.Sampler,
};

pub const LightingState = struct {
    pub const LightParameters = struct {
        vector: [3]f32,
        spotlight_direction: [3]f32,

        attenuation_bias: f32,
        attenuation_scale: f32,

        // NOTE: `.null` means its NOT enabled!
        attenuation_table: mango.LightLookupTable,
        spotlight_table: mango.LightLookupTable,
    };

    ambient: [3]u8,
    light_types: BitpackedArray(Graphics.FragmentLighting.Light.Type, 8),
    light_shadows_disabled: BitpackedArray(bool, 8),
    light_parameters: [8]LightParameters,
    light_factors: [8]mango.LightFactors,

    /// Amount of lights configured by the user.
    configured: u8,
};

pub const empty: RenderingState = .{
    .misc = .empty,
    .index_buffer_offset = undefined,
    .vertex_buffers_offset = undefined,
    .color_attachment = undefined,
    .depth_stencil_attachment = undefined,
    .uniform_state = undefined,
    .texture_unit_enabled = @splat(false),
    .texture_units = undefined,
    .lighting_state = undefined,
    .dirty = .{},
};

misc: Misc,
index_buffer_offset: u28,
vertex_buffers_offset: [12]u28,

color_attachment: backend.ImageView,
depth_stencil_attachment: backend.ImageView,

uniform_state: UniformState,
texture_unit_enabled: [3]bool,
texture_units: [3]TextureUnitState,
lighting_state: LightingState,
dirty: Dirty,

pub fn beginRendering(rnd: *RenderingState, rendering_info: mango.RenderingInfo) void {
    rnd.color_attachment = .fromHandle(rendering_info.color_attachment);
    rnd.depth_stencil_attachment = .fromHandle(rendering_info.depth_stencil_attachment);
    rnd.dirty.begin_rendering = true;
}

/// returns if any draw call has been issued between `beginRendering` and this call.
pub fn endRendering(rnd: *RenderingState) bool {
    defer rnd.dirty.begin_rendering = false;

    // If this is not dirty then at least one draw call has been issued.
    return !rnd.dirty.begin_rendering;
}

pub fn bindVertexBuffers(rnd: *RenderingState, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
    if (binding_count == 0) return;

    std.debug.assert(first_binding < p3d.primitive_engine.attributes.vertex_buffers.len and first_binding + binding_count <= p3d.primitive_engine.attributes.vertex_buffers.len);
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

    if (uniforms.len == 0) return;

    rnd.uniform_state.floating_dirty.getPtr(stage).bits.setRangeValue(.{
        .start = first_uniform,
        .end = first_uniform + @as(u32, @intCast(uniforms.len)),
    }, true);

    const flt_values = &rnd.uniform_state.floating_constants.getPtr(stage).values;
    @memcpy(flt_values[first_uniform..][0..uniforms.len], uniforms);

    rnd.dirty.setUniformsDirty(stage, .float);
}

pub fn bindCombinedImageSamplers(rnd: *RenderingState, first_combined: u32, combined_image_samplers: []const mango.CombinedImageSampler) void {
    std.debug.assert(first_combined + combined_image_samplers.len <= 3);

    for (combined_image_samplers, first_combined..) |unit, i| {
        std.debug.assert((unit.image != .null and unit.sampler != .null) or (unit.sampler == .null and unit.image == .null));

        rnd.dirty.setTextureUnitDirty(@intCast(i));
        rnd.texture_unit_enabled[i] = unit.image != .null;

        if (unit.image == .null) continue;

        const b_image_view: backend.ImageView = .fromHandle(unit.image);
        const b_sampler: backend.Sampler = .fromHandle(unit.sampler);

        rnd.texture_units[i] = .{
            .view = b_image_view,
            .sampler = b_sampler,
        };
    }
}

pub fn bindLightEnvironmentFactors(rnd: *RenderingState, factors: mango.LightEnvironmentFactors) void {
    rnd.lighting_state.ambient = factors.ambient;
    rnd.dirty.light_environment_factors = true;
}

pub fn bindLights(rnd: *RenderingState, lights: []const mango.Light) void {
    std.debug.assert(lights.len <= 8);

    rnd.lighting_state.light_types = .splat(.positional);
    rnd.lighting_state.light_shadows_disabled = .splat(true);

    for (lights, 0..) |light, i| {
        rnd.lighting_state.light_types.set(i, light.type.native());
        rnd.lighting_state.light_shadows_disabled.set(i, !light.enable_shadow);

        rnd.lighting_state.light_parameters[i] = .{
            .vector = light.vector,
            .spotlight_direction = light.spotlight_direction,

            .attenuation_bias = light.attenuation_bias,
            .attenuation_scale = light.attenuation_scale,

            .attenuation_table = if (light.enable_attenuation) light.attenuation_table else .null,
            .spotlight_table = if (light.enable_spotlight) light.spotlight_table else .null,
        };
    }

    rnd.lighting_state.configured = @intCast(lights.len);
    rnd.dirty.light_parameters = true;
}

pub fn bindLightFactors(rnd: *RenderingState, light_factors: []const mango.LightFactors) void {
    std.debug.assert(light_factors.len <= 8);

    @memcpy(rnd.lighting_state.light_factors[0..light_factors.len], light_factors);
    rnd.dirty.light_factors = true;
}

/// Returns the maximum amount of words the next dirty emission will take.
///
/// Its a safe upper bound, not the exact amount needed.
pub fn maxEmitDirtyQueueLength(rnd: *RenderingState) usize {
    // NOTE: This must be FAST as its always checked every drawcall!
    // TODO: Optimize this
    const dirty = &rnd.dirty;

    // zig fmt: off
    var cost: usize = (@as(usize, @intFromBool(dirty.begin_rendering)) * 8)
                    + (@as(usize, @intFromBool(dirty.light_environment_factors)) * 2)
                    + (@as(usize, @intFromBool(dirty.light_factors or dirty.light_parameters)) * rnd.lighting_state.configured) * 30
                    + (@as(usize, @intFromBool(dirty.vertex_buffers)) * (rnd.misc.vertex_buffers_dirty_end - rnd.misc.vertex_buffers_dirty_start)) * 6;
    // zig fmt: on

    for (std.enums.values(mango.ShaderStage)) |stage| {
        if (dirty.isStageUniformsDirty(stage)) {
            const bool_dirty: usize = @intFromBool(dirty.isUniformsDirty(stage, .bool));
            const int_dirty: usize = @intFromBool(dirty.isUniformsDirty(stage, .int));

            cost += (rnd.uniform_state.floating_dirty.getPtr(stage).count() * 8) + (int_dirty * 8) + (bool_dirty * 4);
        }
    }

    if (dirty.isAnyTextureUnitDirty()) {
        for (0..3) |i| {
            cost += @as(usize, @intFromBool(dirty.isTextureUnitDirty(@intCast(i)))) * 10;
        }
    }

    return cost;
}

pub fn emitDirty(rnd: *RenderingState, queue: *command.Queue) void {
    const dirty = &rnd.dirty;

    if (dirty.isAnyUniformsDirty()) {
        rnd.emitDirtyUniforms(queue);
    }

    if (dirty.isAnyTextureUnitDirty()) {
        rnd.emitDirtyTextureUnits(queue);
    }

    if (dirty.light_environment_factors) {
        queue.add(p3d, &p3d.fragment_lighting.ambient, .initBuffer(rnd.lighting_state.ambient));
    }

    if (dirty.light_parameters) {
        std.debug.assert(dirty.light_factors); // You must bind new light factors after binding new lights!

        queue.add(p3d, &p3d.fragment_lighting.num_lights_min_one, .init(@intCast(rnd.lighting_state.configured - 1)));

        const shadows_disabled = rnd.lighting_state.light_shadows_disabled;
        var spotlight_disabled: BitpackedArray(bool, 8) = .splat(true);
        var attenuation_disabled: BitpackedArray(bool, 8) = .splat(true);

        for (0..rnd.lighting_state.configured) |i| {
            const params = rnd.lighting_state.light_parameters[i];
            const factors = rnd.lighting_state.light_factors[i];

            queue.add(p3d, &p3d.fragment_lighting.light[i].parameters, .{
                .xy = .init(.of(params.vector[0]), .of(params.vector[1])),
                .z = .init(.of(params.vector[2])),
                .spot_xy = .init(.ofSaturating(params.spotlight_direction[0]), .ofSaturating(params.spotlight_direction[1])),
                .spot_z = .init(.ofSaturating(params.spotlight_direction[2])),
            });

            queue.add(p3d, &p3d.fragment_lighting.light[i].config, .{
                .type = rnd.lighting_state.light_types.get(i),
                .diffuse_sides = factors.sides.native(),
                .geometric_factor_enable = factors.geometric.native(),
            });

            if (params.attenuation_table != .null) {
                queue.add(p3d, &p3d.fragment_lighting.light[i].attenuation, .{
                    .bias = .init(.of(params.attenuation_bias)),
                    .scale = .init(.of(params.attenuation_scale)),
                });
            }

            const tables: []const mango.LightLookupTable = &.{ params.attenuation_table, params.spotlight_table };
            const first_selectors: []const Graphics.FragmentLighting.LookupTable = &.{ .da0, .sp0 };
            const disabled_tables: []const *BitpackedArray(bool, 8) = &.{ &attenuation_disabled, &spotlight_disabled };

            for (tables, first_selectors, disabled_tables) |table, first_selector, disabled| {
                if (table == .null) continue;

                const b_table: *backend.LightLookupTable = .fromHandleMutable(table);
                const selector: Graphics.FragmentLighting.LookupTable = @enumFromInt(@intFromEnum(first_selector) + i);

                disabled.set(i, false);
                queue.add(p3d, &p3d.fragment_lighting.lut_index, .init(selector, 0));
                queue.addConsecutive(p3d, &p3d.fragment_lighting.lut_data[0], &b_table.data);
            }
        }

        // Finally enable / disable da, sp and shadows per-light.
        queue.addMasked(p3d, &p3d.fragment_lighting.control.lights, .{
            .shadows_disabled = shadows_disabled,
            .spotlight_disabled = spotlight_disabled,
            .distance_attenuation_disabled = attenuation_disabled,
            // NOTE: Ignored by mask
            .disable_d0 = false,
            .disable_d1 = false,
            .disable_fr = false,
            .disable_rb = false,
            .disable_rg = false,
            .disable_rr = false,
        }, 0b1101);
    }

    if (dirty.light_factors) {
        for (0..rnd.lighting_state.configured) |i| {
            const factors = rnd.lighting_state.light_factors[i];

            // We already configured the light if we changed parameters.
            if (!dirty.light_parameters) {
                queue.add(p3d, &p3d.fragment_lighting.light[i].config, .{
                    .type = rnd.lighting_state.light_types.get(i),
                    .diffuse_sides = factors.sides.native(),
                    .geometric_factor_enable = factors.geometric.native(),
                });
            }

            queue.add(p3d, &p3d.fragment_lighting.light[i].factors, .{
                .specular = .{ .initBuffer(factors.specular[0]), .initBuffer(factors.specular[1]) },
                .diffuse = .initBuffer(factors.diffuse),
                .ambient = .initBuffer(factors.ambient),
            });
        }
    }

    if (dirty.vertex_buffers) {
        for (rnd.misc.vertex_buffers_dirty_start..rnd.misc.vertex_buffers_dirty_end) |current_binding| {
            queue.add(p3d, &p3d.primitive_engine.attributes.vertex_buffers[current_binding].offset, .init(rnd.vertex_buffers_offset[current_binding]));
        }
    }

    if (dirty.begin_rendering) {
        const color_width: u16, const color_height: u16, const color_physical_address: PhysicalAddress = if (rnd.color_attachment.data.valid) info: {
            @branchHint(.likely);
            const color_attachment: backend.ImageView = rnd.color_attachment;
            const color_rendering_info = color_attachment.getRenderingInfo();

            break :info .{ color_rendering_info.width, color_rendering_info.height, color_rendering_info.address };
        } else .{ 0, 0, .fromAddress(0) };

        const depth_stencil_width: u16, const depth_stencil_height: u16, const depth_stencil_physical_address: PhysicalAddress = if (rnd.depth_stencil_attachment.data.valid) info: {
            const depth_stencil_attachment: backend.ImageView = rnd.depth_stencil_attachment;
            const depth_stencil_rendering_info = depth_stencil_attachment.getRenderingInfo();

            break :info .{ depth_stencil_rendering_info.width, depth_stencil_rendering_info.height, depth_stencil_rendering_info.address };
        } else .{ 0, 0, .fromAddress(0) };

        if (color_width != 0 and depth_stencil_width != 0) {
            std.debug.assert(color_width == depth_stencil_width and color_height == depth_stencil_height);
        }

        const width, const height = if (color_width != 0)
            .{ color_width, color_height }
        else
            .{ depth_stencil_width, depth_stencil_height };

        queue.add(p3d, &p3d.output_merger.invalidate, .init(.trigger));
        queue.addIncremental(p3d, .{
            &p3d.output_merger.depth_location,
            &p3d.output_merger.color_location,
            &p3d.output_merger.dimensions,
        }, .{
            .fromPhysical(depth_stencil_physical_address),
            .fromPhysical(color_physical_address),
            .{
                .width = @intCast(width),
                .height_end = @intCast(height - 1),
                // TODO: Expose a flag for flipping?
                .flip_vertically = true,
            },
        });
    }

    dirty.* = .{};
}

fn emitDirtyTextureUnits(rnd: *RenderingState, queue: *command.Queue) void {
    const dirty = rnd.dirty;

    // NOTE: The 0th or Primary texture unit is special as it can handle
    // all possible texture types and are not limited to only 2D!
    if (rnd.texture_unit_enabled[0] and dirty.isTextureUnitDirty(0)) {
        // TODO: Cubemaps, Shadow, Projected textures, etc...

        const image_view = rnd.texture_units[0].view;
        const sampler = rnd.texture_units[0].sampler;

        const image: *backend.Image = .fromHandleMutable(rnd.texture_units[0].view.data.image);

        std.debug.assert(!image.memory_info.isUnbound());
        const address = image.memory_info.boundPhysicalAddress();
        const format = image_view.data.format().nativeTextureUnitFormat();

        queue.addIncremental(p3d, .{
            &p3d.texture_units.@"0".border_color,
            &p3d.texture_units.@"0".dimensions,
            &p3d.texture_units.@"0".parameters,
            &p3d.texture_units.@"0".lod,
            &p3d.texture_units.@"0".address[0],
        }, .{
            sampler.data.borderColor(),
            .{ image.info.width(), image.info.height() },
            .{
                .mag_filter = sampler.data.mag_filter,
                .min_filter = sampler.data.min_filter,
                .etc1 = if (format == .etc1) .etc1 else .none,
                .address_mode_v = sampler.data.address_mode_v,
                .address_mode_u = sampler.data.address_mode_u,
                .is_shadow = false, // TODO: Shadow
                .mip_filter = sampler.data.mip_filter,
                .type = .@"2d", // TODO: Different types
            },
            .{
                .bias = sampler.data.lod_bias,
                .max_level_of_detail = @min(image_view.data.levels_minus_one, sampler.data.max_lod),
                .min_level_of_detail = @max(image_view.data.base_mip_level, sampler.data.min_lod),
            },
            .fromPhysical(address),
        });

        queue.add(p3d, &p3d.texture_units.@"0".format, .init(format));
    }

    // NOTE: Remaining units are ONLY 2D, they ignore their type
    for (1..3) |unit| {
        if (!rnd.texture_unit_enabled[unit] or !dirty.isTextureUnitDirty(@intCast(unit))) continue;

        const image_view = rnd.texture_units[unit].view;
        const sampler = rnd.texture_units[unit].sampler;

        const image: *backend.Image = .fromHandleMutable(rnd.texture_units[unit].view.data.image);

        std.debug.assert(!image.memory_info.isUnbound());
        const address = image.memory_info.boundPhysicalAddress();
        const format = image_view.data.format().nativeTextureUnitFormat();

        const unit_register = switch (unit) {
            1 => &p3d.texture_units.@"1",
            2 => &p3d.texture_units.@"2",
            else => unreachable,
        };

        queue.add(p3d, unit_register, .{
            .border_color = sampler.data.borderColor(),
            .dimensions = .{ image.info.width(), image.info.height() },
            .parameters = .{
                .mag_filter = sampler.data.mag_filter,
                .min_filter = sampler.data.min_filter,
                .etc1 = if (format == .etc1) .etc1 else .none,
                .address_mode_v = sampler.data.address_mode_v,
                .address_mode_u = sampler.data.address_mode_u,
                .is_shadow = false,
                .mip_filter = sampler.data.mip_filter,
                .type = .@"2d",
            },
            .lod = .{
                .bias = sampler.data.lod_bias,
                .max_level_of_detail = @min(image_view.data.levels_minus_one, sampler.data.max_lod),
                .min_level_of_detail = @max(image_view.data.base_mip_level, sampler.data.min_lod),
            },
            .address = .fromPhysical(address),
            .format = .init(format),
        });
    }

    // NOTE: After updating textures we MUST clear the texture cache! (+ Set enabled/non-null units)
    queue.addMasked(p3d, &p3d.texture_units.config, .{
        .texture_enabled = .init(rnd.texture_unit_enabled), // NOTE: Not affected by the mask
        .texture_3_coordinates = .@"0",
        .texture_3_enabled = false,
        .texture_2_coordinates = .@"1",
        .clear_texture_cache = true, // NOTE: Not affected by the mask
    }, 0b0101);
}

fn emitDirtyUniforms(rnd: *RenderingState, queue: *command.Queue) void {
    const dirty = rnd.dirty;

    queue.add(p3d, &p3d.primitive_engine.mode, .init(.config));
    defer queue.add(p3d, &p3d.primitive_engine.mode, .init(.drawing));

    const shader_registers: []const *volatile Graphics.Shader = &.{ &p3d.vertex_shader, &p3d.geometry_shader };
    const shader_stages: []const mango.ShaderStage = &.{ mango.ShaderStage.vertex, mango.ShaderStage.geometry };

    for (shader_registers, shader_stages) |registers, stage| {
        for (std.enums.values(UniformLocation)) |location| if (dirty.isUniformsDirty(stage, location)) switch (location) {
            .bool => queue.add(p3d, &registers.bool_uniforms, .init(@bitCast(rnd.uniform_state.boolean_constants.get(stage).bits))),
            .int => queue.add(p3d, &registers.int_uniforms[0..4].*, rnd.uniform_state.integer_constants.get(stage).values),
            .float => emitFloatUniforms(rnd.uniform_state.floating_dirty.getPtr(stage), rnd.uniform_state.floating_constants.getPtr(stage), registers, queue),
        };
    }
}

fn emitFloatUniforms(flt_dirty: *std.EnumSet(pica.shader.register.Source.Constant), flt_constants: *std.EnumArray(pica.shader.register.Source.Constant, [4]f32), shader: *volatile pica.Graphics.Shader, queue: *command.Queue) void {
    var last_const: ?pica.shader.register.Source.Constant = null;

    var it = flt_dirty.iterator();
    while (it.next()) |f| {
        // NOTE: We iterate in index order, `last_const` will always either be null or lower than `f`
        if (last_const == null or (@intFromEnum(f) - @intFromEnum(last_const.?)) != 1) {
            queue.add(p3d, &shader.float_uniform_index, .{
                .index = f,
                .mode = .f8_23,
            });
        }

        const constants = flt_constants.getPtr(f);

        // NOTE: They were stored as XYZW but PICA expects WZYX
        // We can modify in-place because we know it won't be used again until it gets dirty again!
        std.mem.reverse(f32, constants);

        queue.add(p3d, &shader.float_uniform_data[0..4].*, @bitCast(constants.*));
        last_const = f;
    }

    flt_dirty.* = .initEmpty();
}

const RenderingState = @This();

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const pica = zitrus.hardware.pica;
const Graphics = pica.Graphics;

const BitpackedArray = zitrus.hardware.BitpackedArray;
const PhysicalAddress = zitrus.hardware.PhysicalAddress;

const command = pica.command;

const p3d = &zitrus.memory.arm11.pica.p3d;
