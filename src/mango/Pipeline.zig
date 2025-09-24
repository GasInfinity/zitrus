//! A PICA200 pipeline.
//!
//! Currently *parses* shaders and stores all non-dynamic fixed-function state.
//!

pub const Handle = enum(u32) {
    null = 0,
    _,
};

pub const Kind = enum(u2) {
    graphics,
};

pub const Graphics = struct {
    pub const Misc = packed struct(u32) {
        cull_mode_ccw: pica.CullMode,
        is_front_ccw: bool,

        depth_test_enable: bool,
        depth_test_op: pica.CompareOperation,
        depth_write_enable: bool,

        color_r_enable: bool,
        color_g_enable: bool,
        color_b_enable: bool,
        color_a_enable: bool,

        alpha_test_enable: bool,
        alpha_test_op: pica.CompareOperation,

        stencil_test_enable: bool,
        stencil_test_op: pica.CompareOperation,
        topology: pica.PrimitiveTopology,
        _: u10 = 0,
    };

    dyn: mango.GraphicsPipelineCreateInfo.DynamicState,
    misc: Misc,
    depth_parameters: GraphicsState.DepthParameters,
    vertex_attribute_strides: [12]u8,
    vertex_attributes_len: u8,
    alpha_test_reference: u8,
    stencil_compare_mask: u8,
    stencil_reference: u8,
    stencil_write_mask: u8,
    boolean_constants: std.EnumArray(mango.ShaderStage, std.EnumSet(pica.shader.register.Integral.Boolean)),
    integer_constants: std.EnumArray(mango.ShaderStage, std.EnumArray(pica.shader.register.Integral.Integer, [4]i8)),

    cmd3d_state: []align(8) u32,

    pub fn init(create_info: mango.GraphicsPipelineCreateInfo, gpa: std.mem.Allocator) !Graphics {
        const dyn = create_info.dynamic_state;

        var gfx: Graphics = .{
            .dyn = dyn,
            .misc = undefined,
            .depth_parameters = undefined,
            .vertex_attribute_strides = undefined,
            .vertex_attributes_len = undefined,
            .alpha_test_reference = undefined,
            .stencil_compare_mask = undefined,
            .stencil_reference = undefined,
            .stencil_write_mask = undefined,
            .boolean_constants = undefined,
            .integer_constants = undefined,
            .cmd3d_state = try gpa.alignedAlloc(u32, .@"8", 1024),
        };
        errdefer gfx.deinit(gpa);

        var gfx_queue: cmd3d.Queue = .{
            .buffer = gfx.cmd3d_state,
            .current_index = 0,
        };

        // NOTE: It doesn't make sense to set internal_regs.geometry_pipeline.start_draw_function to config mode always, what do you do more, pipeline changes or drawcalls bro? (silly question)
        gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .config);
        // TODO: What to do with early depth?
        gfx_queue.add(internal_regs, &internal_regs.rasterizer.early_depth_test_enable_1, .init(false));
        gfx_queue.add(internal_regs, &internal_regs.framebuffer.early_depth_test_enable_2, .init(false));

        // TODO: Lighting in pipelines
        gfx_queue.add(internal_regs, &internal_regs.texturing.lighting_enable, .init(false));
        gfx_queue.add(internal_regs, &internal_regs.fragment_lighting.disable, .init(true));

        if (create_info.geometry_shader_state) |_| {
            @panic("TODO");
        } else {
            gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.enable_geometry_shader_configuration, .init(false));

            const vtx_info = try compileShader(create_info.vertex_shader_state.*, &internal_regs.vertex_shader, &gfx_queue);

            gfx.boolean_constants = .init(.{ .vertex = vtx_info.boolean_constants, .geometry = undefined });
            gfx.integer_constants = .init(.{ .vertex = vtx_info.integer_constants, .geometry = undefined });

            // TODO: When we support geometry shaders, this should be a separate function!
            gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.vertex_shader_output_map_total_1, .init(vtx_info.outputs_minus_one));
            gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.vertex_shader_output_map_total_2, .init(vtx_info.outputs_minus_one));
            gfx_queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{
                .total_vertex_outputs = vtx_info.outputs_minus_one,
                .topology = .triangle_list, // NOTE: Ignored by mask
            }, 0b0001);

            var attribute_clock: pica.Registers.Internal.Rasterizer.OutputAttributeClock = .{};

            var out_it = vtx_info.entrypoint.output_set.iterator();
            var semantic_outputs: usize = 0;
            while (out_it.next()) |o| {
                const map = vtx_info.entrypoint.output_map[semantic_outputs];

                if (@intFromEnum(o) >= @intFromEnum(pica.shader.register.Destination.Output.o7)) {
                    std.debug.assert(map.x == .unused and map.y == .unused and map.z == .unused and map.w == .unused);
                    continue;
                }

                // zig fmt: on
                attribute_clock.color_present = attribute_clock.color_present or (map.x.isColor() or map.y.isColor() or map.z.isColor() or map.w.isColor());
                attribute_clock.position_z_present = attribute_clock.position_z_present or (map.x == .position_z or map.y == .position_z or map.z == .position_z or map.w == .position_z);
                attribute_clock.texture_coordinates_0_present = attribute_clock.texture_coordinates_0_present or (map.x.isTextureCoordinate0() or map.y.isTextureCoordinate0() or map.z.isTextureCoordinate0() or map.w.isTextureCoordinate0());
                attribute_clock.texture_coordinates_1_present = attribute_clock.texture_coordinates_1_present or (map.x.isTextureCoordinate1() or map.y.isTextureCoordinate1() or map.z.isTextureCoordinate1() or map.w.isTextureCoordinate1());
                attribute_clock.texture_coordinates_2_present = attribute_clock.texture_coordinates_2_present or (map.x.isTextureCoordinate2() or map.y.isTextureCoordinate2() or map.z.isTextureCoordinate2() or map.w.isTextureCoordinate2());
                attribute_clock.texture_coordinates_0_w_present = attribute_clock.texture_coordinates_0_w_present or (map.x == .texture_coordinate_0_w or map.y == .texture_coordinate_0_w or map.z == .texture_coordinate_0_w or map.w == .texture_coordinate_0_w);
                attribute_clock.normal_quaternion_or_view_present = attribute_clock.normal_quaternion_or_view_present or (map.x.isView() or map.x.isNormalQuaternion()) or (map.y.isView() or map.y.isNormalQuaternion()) or (map.z.isView() or map.z.isNormalQuaternion()) or (map.w.isView() or map.w.isNormalQuaternion());
                // zig fmt: off

                gfx_queue.add(internal_regs, &internal_regs.rasterizer.shader_output_map_output[semantic_outputs], map);
                semantic_outputs += 1;
            }

            gfx_queue.add(internal_regs, &internal_regs.rasterizer.shader_output_map_total, .init(@intCast(semantic_outputs)));
            gfx_queue.add(internal_regs, &internal_regs.rasterizer.shader_output_attribute_clock, attribute_clock);
            gfx_queue.add(internal_regs, &internal_regs.rasterizer.shader_output_attribute_mode, .{
                .use_texture_coordinates = attribute_clock.texture_coordinates_0_present or attribute_clock.texture_coordinates_1_present or attribute_clock.texture_coordinates_2_present or attribute_clock.texture_coordinates_0_w_present,
            });
        }

        if(!dyn.vertex_input) {
            const vtx_input_state = create_info.vertex_input_state.?;
            const bindings = vtx_input_state.bindings[0..vtx_input_state.bindings_len];
            const attributes = vtx_input_state.attributes[0..vtx_input_state.attributes_len];
            const fixed_attributes = vtx_input_state.fixed_attributes[0..vtx_input_state.fixed_attributes_len];

            const vtx_input_layout: VertexInputLayout = .compile(bindings, attributes, fixed_attributes);

            gfx.vertex_attributes_len = vtx_input_layout.buffers_len;

            gfx_queue.addIncremental(internal_regs, .{
                &internal_regs.geometry_pipeline.attribute_buffer_base,
                &internal_regs.geometry_pipeline.attribute_config.low,
                &internal_regs.geometry_pipeline.attribute_config.high,
            }, .{
                .fromPhysical(backend.global_attribute_buffer_base),
                vtx_input_layout.config.low,
                vtx_input_layout.config.high,
            });

            for (0..vtx_input_layout.buffers_len) |i| {
                gfx.vertex_attribute_strides[i] = vtx_input_layout.buffer_config[i].high.bytes_per_vertex;

                gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.attribute_buffer[i].config, vtx_input_layout.buffer_config[i]);
            }
            
            gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.vertex_shader_input_attributes, .init(vtx_input_layout.config.high.attributes_end));

            gfx_queue.add(internal_regs, &internal_regs.vertex_shader.input_buffer_config, .{
                .num_input_attributes = (vtx_input_layout.config.high.attributes_end),
                .enabled_for_vertex_0 = true,
                .enabled_for_vertex_1 = true,
            });

            gfx_queue.add(internal_regs, &internal_regs.vertex_shader.attribute_permutation, vtx_input_layout.permutation);
        }

        if(!dyn.primitive_topology) {
            const topo = create_info.input_assembly_state.?.topology;
            const native_topo = topo.native();

            gfx.misc.topology = native_topo;

            gfx_queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{
                .total_vertex_outputs = 0, // NOTE: Ignored by mask
                // NOTE: Hah, another PICA200 classic, after debugging in azahar and in hardware it seems triangle lists
                // are drawn with a `geometry` primitive topology, totally acceptable bro. Keep it up DMP
                .topology = native_topo.indexedTopology(),
            }, 0b0010);

            gfx_queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config, .{
                .geometry_shader_usage = .disabled, // NOTE: Ignored by mask
                .drawing_triangles = native_topo == .triangle_list,
                .use_reserved_geometry_subdivision = false, // NOTE: Ignored by mask
            }, 0b0010);

            gfx_queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{
                .drawing_triangles = native_topo == .triangle_list,
            }, 0b0010);
        }

        if(!dyn.front_face) {
            const raster_state = create_info.rasterization_state.?;

            gfx.misc.is_front_ccw = switch (raster_state.front_face) {
                .ccw => true,
                .cw => false,
            };

            if(!dyn.cull_mode) {
                gfx.misc.cull_mode_ccw = raster_state.cull_mode.native(.ccw);

                gfx_queue.add(internal_regs, &internal_regs.rasterizer.faceculling_config, .init(raster_state.cull_mode.native(raster_state.front_face)));
            }
        } else if(!dyn.cull_mode) {
            gfx.misc.cull_mode_ccw = create_info.rasterization_state.?.cull_mode.native(.ccw);
        }

        if(!dyn.depth_mode) {
            gfx_queue.add(internal_regs, &internal_regs.rasterizer.depth_map_mode, .init(create_info.rasterization_state.?.depth_mode.native()));
        }

        if(!dyn.viewport) {
            const static_viewport = create_info.viewport_state.?.viewport.?;
            const flt_width: f32 = @floatFromInt(static_viewport.rect.extent.width);
            const flt_height: f32 = @floatFromInt(static_viewport.rect.extent.height);

            gfx_queue.addIncremental(internal_regs, .{
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

            gfx_queue.add(internal_regs, &internal_regs.rasterizer.viewport_xy, .{ .x = static_viewport.rect.offset.x, .y = static_viewport.rect.offset.y });

            gfx.depth_parameters.min_depth = static_viewport.min_depth;
            gfx.depth_parameters.max_depth = static_viewport.max_depth;

            if(!dyn.depth_bias_constant) {
                const depth_map_scale = (static_viewport.min_depth - static_viewport.max_depth); 
                const depth_map_offset = static_viewport.min_depth + create_info.rasterization_state.?.depth_bias_constant;

                gfx_queue.addIncremental(internal_regs, .{
                    &internal_regs.rasterizer.depth_map_scale,
                    &internal_regs.rasterizer.depth_map_offset,
                }, .{
                    .init(.of(depth_map_scale)),
                    .init(.of(depth_map_offset)),
                });
            }
        } else if(!dyn.depth_bias_constant) {
            gfx.depth_parameters.constant = create_info.rasterization_state.?.depth_bias_constant;
        }

        if(!dyn.scissor) {
            const static_scissor = create_info.viewport_state.?.scissor.?;
            
            gfx_queue.addIncremental(internal_regs, .{
                &internal_regs.rasterizer.scissor_config,
                &internal_regs.rasterizer.scissor_start,
                &internal_regs.rasterizer.scissor_end,
            }, .{
                .init(static_scissor.mode.native()),
                @bitCast(static_scissor.rect.offset),
                .{ .x = static_scissor.rect.offset.x + static_scissor.rect.extent.width, .y = static_scissor.rect.offset.y + static_scissor.rect.extent.height },
            });
        }

        if(!dyn.logic_op_enable) {
            const color_blend_state = create_info.color_blend_state.?;

            if(color_blend_state.logic_op_enable) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.color_operation, .{
                    .fragment_operation = .default,
                    .mode = .logic,
                });

                if(!dyn.logic_op) {
                    gfx_queue.add(internal_regs, &internal_regs.framebuffer.logic_operation, .init(color_blend_state.logic_op.native()));
                }
            } else {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.color_operation, .{
                    .fragment_operation = .default,
                    .mode = .blend,
                });

                if(!dyn.blend_equation) {
                    gfx_queue.add(internal_regs, &internal_regs.framebuffer.blend_config, color_blend_state.attachment.blend_equation.native());
                } 

                if(!dyn.blend_constants) {
                    gfx_queue.add(internal_regs, &internal_regs.framebuffer.blend_color, color_blend_state.blend_constants);
                }
            }
        } else {
            if(!dyn.logic_op) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.logic_operation, .init(create_info.color_blend_state.?.logic_op.native()));
            }

            if(!dyn.blend_equation) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.blend_config, create_info.color_blend_state.?.attachment.blend_equation.native());
            } 

            if(!dyn.blend_constants) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.blend_color, create_info.color_blend_state.?.blend_constants);
            }
        }

        if(!dyn.alpha_test_enable and !dyn.alpha_test_compare_op and !dyn.alpha_test_reference) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

            gfx_queue.add(internal_regs, &internal_regs.framebuffer.alpha_test, .{
                .enable = alpha_depth_stencil_state.alpha_test_enable,
                .op = alpha_depth_stencil_state.alpha_test_compare_op.native(),
                .reference = alpha_depth_stencil_state.alpha_test_reference,
            });
        } else if(!dyn.alpha_test_enable or !dyn.alpha_test_compare_op or !dyn.alpha_test_reference) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

            gfx.misc.alpha_test_enable = alpha_depth_stencil_state.alpha_test_enable;
            gfx.misc.alpha_test_op = alpha_depth_stencil_state.alpha_test_compare_op.native();
            gfx.alpha_test_reference = alpha_depth_stencil_state.alpha_test_reference;
        }

        if(!dyn.stencil_test_enable) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

            if(!alpha_depth_stencil_state.stencil_test_enable) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.stencil_test, .{
                    .enable = false,
                    .op = .never,
                    .compare_mask = 0x00,
                    .reference = 0x00,
                    .write_mask = 0x00,
                });
            } else if(!dyn.stencil_test_operation and !dyn.stencil_compare_mask and !dyn.stencil_reference and !dyn.stencil_write_mask) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.stencil_test, .{
                    .enable = true,
                    .op = alpha_depth_stencil_state.back_front.compare_op.native(),
                    .compare_mask = alpha_depth_stencil_state.back_front.compare_mask,
                    .reference = alpha_depth_stencil_state.back_front.reference,
                    .write_mask = alpha_depth_stencil_state.back_front.write_mask,
                }); 
            } else if(!dyn.stencil_compare_mask or !dyn.stencil_reference or !dyn.stencil_write_mask) {
                gfx.stencil_compare_mask = alpha_depth_stencil_state.back_front.compare_mask;
                gfx.stencil_reference = alpha_depth_stencil_state.back_front.reference;
                gfx.stencil_write_mask = alpha_depth_stencil_state.back_front.write_mask;
            }
        } else if(!dyn.stencil_test_enable or !dyn.stencil_compare_mask or !dyn.stencil_reference or !dyn.stencil_write_mask) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

            gfx.misc.stencil_test_enable = alpha_depth_stencil_state.stencil_test_enable;
            gfx.stencil_compare_mask = alpha_depth_stencil_state.back_front.compare_mask;
            gfx.stencil_reference = alpha_depth_stencil_state.back_front.reference;
            gfx.stencil_write_mask = alpha_depth_stencil_state.back_front.write_mask;
        }

        if(((!dyn.stencil_test_enable and create_info.alpha_depth_stencil_state.?.stencil_test_enable) or dyn.stencil_test_enable) and !dyn.stencil_test_operation) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

            gfx.misc.stencil_test_op = alpha_depth_stencil_state.back_front.compare_op.native();

            gfx_queue.add(internal_regs, &internal_regs.framebuffer.stencil_operation, .{
                .fail_op = alpha_depth_stencil_state.back_front.fail_op.native(),
                .depth_fail_op = alpha_depth_stencil_state.back_front.depth_fail_op.native(),
                .pass_op = alpha_depth_stencil_state.back_front.pass_op.native(),
            });
        }

        if(!dyn.depth_test_enable and !dyn.color_write_mask) {
            const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;
            const color_blend_state = create_info.color_blend_state.?;

            gfx.misc.depth_test_enable = alpha_depth_stencil_state.depth_test_enable;

            gfx.misc.color_r_enable = color_blend_state.attachment.color_write_mask.r_enable;
            gfx.misc.color_g_enable = color_blend_state.attachment.color_write_mask.g_enable;
            gfx.misc.color_b_enable = color_blend_state.attachment.color_write_mask.b_enable;
            gfx.misc.color_a_enable = color_blend_state.attachment.color_write_mask.a_enable;

            if(!alpha_depth_stencil_state.depth_test_enable) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.depth_color_mask, .{
                    .enable_depth_test = false,
                    .depth_op = .never,
                    .r_write_enable = color_blend_state.attachment.color_write_mask.r_enable,
                    .g_write_enable = color_blend_state.attachment.color_write_mask.g_enable,
                    .b_write_enable = color_blend_state.attachment.color_write_mask.b_enable,
                    .a_write_enable = color_blend_state.attachment.color_write_mask.a_enable,
                    .depth_write_enable = false,
                });
            } else if(!dyn.depth_compare_op and !dyn.depth_write_enable) {
                gfx_queue.add(internal_regs, &internal_regs.framebuffer.depth_color_mask, .{
                    .enable_depth_test = true,
                    .depth_op = alpha_depth_stencil_state.depth_compare_op.native(),
                    .r_write_enable = color_blend_state.attachment.color_write_mask.r_enable,
                    .g_write_enable = color_blend_state.attachment.color_write_mask.g_enable,
                    .b_write_enable = color_blend_state.attachment.color_write_mask.b_enable,
                    .a_write_enable = color_blend_state.attachment.color_write_mask.a_enable,
                    .depth_write_enable = alpha_depth_stencil_state.depth_write_enable,
                });
            } else if(!dyn.depth_compare_op or !dyn.depth_write_enable) {
                gfx.misc.depth_test_op = alpha_depth_stencil_state.depth_compare_op.native();
                gfx.misc.depth_write_enable = alpha_depth_stencil_state.depth_write_enable;
            }
        } else {
            if(!dyn.depth_test_enable or !dyn.depth_compare_op or !dyn.depth_write_enable) {
                const alpha_depth_stencil_state = create_info.alpha_depth_stencil_state.?;

                gfx.misc.depth_test_enable = alpha_depth_stencil_state.depth_test_enable;
                gfx.misc.depth_test_op = alpha_depth_stencil_state.depth_compare_op.native();
                gfx.misc.depth_write_enable = alpha_depth_stencil_state.depth_write_enable;
            }
            
            if(!dyn.color_write_mask) {
                const color_blend_state = create_info.color_blend_state.?;
                
                gfx.misc.color_r_enable = color_blend_state.attachment.color_write_mask.r_enable;
                gfx.misc.color_g_enable = color_blend_state.attachment.color_write_mask.g_enable;
                gfx.misc.color_b_enable = color_blend_state.attachment.color_write_mask.b_enable;
                gfx.misc.color_a_enable = color_blend_state.attachment.color_write_mask.a_enable;
            }
        }

        if(!dyn.texture_combiner) {
            const texture_combiner_state = create_info.texture_combiner_state.?;
            
            const combiners = texture_combiner_state.texture_combiners[0..texture_combiner_state.texture_combiners_len];
            const combiner_buffer_sources = texture_combiner_state.texture_combiner_buffer_sources[0..texture_combiner_state.texture_combiner_buffer_sources_len];

            const native_combiners: TextureCombinerState = .compile(std.mem.zeroes(@FieldType(TextureCombinerState, "update_buffer")), combiners, combiner_buffer_sources);

            // TODO: Merge / Investigate z_flip. shading_density_source and fog mode
            gfx_queue.add(internal_regs, &internal_regs.texture_combiners.update_buffer, native_combiners.update_buffer);

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

                gfx_queue.add(internal_regs, current_combiner_reg, native_combiners.combiner[i]);
            }
        }

        if(!dyn.texture_config) {
            const texture_sampling_state = create_info.texture_sampling_state.?;

            gfx_queue.add(internal_regs, &internal_regs.texturing.config, .{
                .texture_0_enabled = texture_sampling_state.texture_enable[0],
                .texture_1_enabled = texture_sampling_state.texture_enable[1],
                .texture_2_enabled = texture_sampling_state.texture_enable[2],
                .texture_3_coordinates = texture_sampling_state.texture_3_coordinates.nativeTexture3(),
                .texture_3_enabled = texture_sampling_state.texture_enable[2],
                .texture_2_coordinates = texture_sampling_state.texture_3_coordinates.nativeTexture2(),
                .clear_texture_cache = false,
            });
        }

        const rendering_info = create_info.rendering_info;

        gfx_queue.addIncremental(internal_regs, .{
            &internal_regs.framebuffer.color_buffer_reading,
            &internal_regs.framebuffer.color_buffer_writing,
            &internal_regs.framebuffer.depth_buffer_reading,
            &internal_regs.framebuffer.depth_buffer_writing,
            &internal_regs.framebuffer.depth_buffer_format,
            &internal_regs.framebuffer.color_buffer_format,
        }, .{
            if(rendering_info.color_attachment_format != .undefined) .enable else .disable,
            if(rendering_info.color_attachment_format != .undefined) .enable else .disable,
            .{
                .depth_enable = rendering_info.depth_stencil_attachment_format != .undefined,
                .stencil_enable = false, // TODO: stencil test reading enable
            },
            .{
                .depth_enable = rendering_info.depth_stencil_attachment_format != .undefined,
                .stencil_enable = false, // TODO: stencil test writing enable
            },
            .init(if(rendering_info.depth_stencil_attachment_format != .undefined) rendering_info.depth_stencil_attachment_format.nativeDepthStencilFormat() else .d16),
            .init(if(rendering_info.color_attachment_format != .undefined) rendering_info.color_attachment_format.nativeColorFormat() else .abgr8888),
        });

        gfx_queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_block_size, .{ .mode = .@"8x8" });
        gfx_queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .drawing);

        gfx.cmd3d_state = if(gpa.remap(gfx.cmd3d_state, gfx_queue.current_index * @sizeOf(u32))) |remapped|
            remapped
        else manual: {
            const new = try gpa.alignedAlloc(u32, .@"8", gfx_queue.current_index);
            @memcpy(new, gfx.cmd3d_state[0..new.len]);

            gpa.free(gfx.cmd3d_state);
            break :manual new;
        };

        return gfx;
    }

    pub fn deinit(gfx: *Graphics, gpa: std.mem.Allocator) void {
        gpa.free(gfx.cmd3d_state);
        gfx.* = undefined;
    }

    pub fn copyRenderingState(gfx_pip: Graphics, rnd_state: *RenderingState) void {
        rnd_state.uniform_state.boolean_constants = gfx_pip.boolean_constants;
        rnd_state.uniform_state.integer_constants = gfx_pip.integer_constants;
    }

    /// Copies static state that can't be changed alone (they depend on other states)
    /// Dynamic state is and must be preserved
    pub fn copyGraphicsState(gfx_pip: Graphics, gfx_state: *GraphicsState) void {
        const dyn = &gfx_pip.dyn;

        if(!dyn.primitive_topology) {
            gfx_state.misc.primitive_topology = gfx_pip.misc.topology;
        }

        if(!dyn.cull_mode) {
            gfx_state.misc.cull_mode_ccw = gfx_pip.misc.cull_mode_ccw;
        }

        if(!dyn.front_face) {
            gfx_state.misc.is_front_ccw = gfx_pip.misc.is_front_ccw;
        }

        if(!dyn.color_write_mask) {
            gfx_state.misc.color_r_enable = gfx_pip.misc.color_r_enable;
            gfx_state.misc.color_g_enable = gfx_pip.misc.color_g_enable;
            gfx_state.misc.color_b_enable = gfx_pip.misc.color_b_enable;
            gfx_state.misc.color_a_enable = gfx_pip.misc.color_a_enable;
        }

        if(!dyn.viewport) {
            gfx_state.depth_map_parameters.min_depth = gfx_pip.depth_parameters.min_depth;
            gfx_state.depth_map_parameters.max_depth = gfx_pip.depth_parameters.max_depth;
        }

        if(!dyn.depth_bias_constant) {
            gfx_state.depth_map_parameters.constant = gfx_pip.depth_parameters.constant;
        }

        if(!dyn.depth_test_enable) {
            gfx_state.misc.depth_test_enable = gfx_pip.misc.depth_test_enable;
        }

        if(!dyn.depth_compare_op) {
            gfx_state.misc.depth_test_op = gfx_pip.misc.depth_test_op;
        }

        if(!dyn.depth_write_enable) {
            gfx_state.misc.depth_write_enable = gfx_pip.misc.depth_write_enable;
        }

        if(!dyn.alpha_test_enable) {
            gfx_state.misc.alpha_test_enable = gfx_pip.misc.alpha_test_enable;
        }

        if(!dyn.alpha_test_compare_op) {
            gfx_state.misc.alpha_test_op = gfx_pip.misc.alpha_test_op;
        }

        if(!dyn.alpha_test_reference) {
            gfx_state.misc.alpha_test_reference = gfx_pip.alpha_test_reference;
        }

        if(!dyn.stencil_test_enable) {
            gfx_state.stencil.state.enable = gfx_pip.misc.stencil_test_enable;
        }

        if(!dyn.stencil_test_operation) {
            gfx_state.stencil.state.op = gfx_pip.misc.stencil_test_op;
        }

        if(!dyn.stencil_compare_mask) {
            gfx_state.stencil.compare_mask = gfx_pip.stencil_compare_mask;
        }

        if(!dyn.stencil_reference) {
            gfx_state.stencil.reference = gfx_pip.stencil_reference;
        }

        if(!dyn.stencil_write_mask) {
            gfx_state.stencil.write_mask = gfx_pip.stencil_write_mask;
        }

        if(!dyn.vertex_input) {
            gfx_state.vtx_input.buffers_len = gfx_pip.vertex_attributes_len;

            for (0..gfx_pip.vertex_attributes_len) |i| {
                gfx_state.vtx_input.buffer_config[i].high.bytes_per_vertex = gfx_pip.vertex_attribute_strides[i];
            }
        }
    }

    pub fn fromHandleMutable(handle: Handle) *Graphics {
        return @ptrFromInt(@intFromEnum(handle));
    }

    pub fn toHandle(graphics: *Graphics) Handle {
        return @enumFromInt(@intFromPtr(graphics));
    }
};

pub const CompiledShaderInfo = struct {
    entrypoint: zpsh.Parsed.EntrypointIterator.Entry,
    outputs_minus_one: u4,

    boolean_constants: std.EnumSet(pica.shader.register.Integral.Boolean),
    integer_constants: std.EnumArray(pica.shader.register.Integral.Integer, [4]i8),
};

pub fn compileShader(state: mango.GraphicsPipelineCreateInfo.ShaderStageState, comptime shader: *pica.Registers.Internal.Shader, queue: *cmd3d.Queue) !CompiledShaderInfo {
    const requested_entrypoint_name = state.name[0..state.name_len];
    const parsed: zpsh.Parsed = .initBuffer(state.code[0..state.code_len]);

    const found_entrypoint = ent: {
        var entry_it = parsed.entrypointIterator();

        while (entry_it.next()) |entrypoint| {
            if(std.mem.eql(u8, entrypoint.name, requested_entrypoint_name)) {
                break :ent entrypoint;
            }
        }

        return error.ValidationFailed;
    };

    queue.add(internal_regs, &shader.code_transfer_index, .init(0));
    {
        var instructions_written: usize = 0;

        while (instructions_written < parsed.instructions.len) : (instructions_written += std.math.maxInt(u8)) {
            queue.addConsecutive(internal_regs, &shader.code_transfer_data[0], parsed.instructions[instructions_written..]);
        }
    }
    queue.add(internal_regs, &shader.code_transfer_end, .init(.trigger));

    queue.add(internal_regs, &shader.operand_descriptors_index, .init(0));
    queue.addConsecutive(internal_regs, &shader.operand_descriptors_data[0], parsed.operand_descriptors);

    queue.add(internal_regs, &shader.entrypoint, .initEntry(found_entrypoint.offset));
    queue.add(internal_regs, &shader.bool_uniform, @bitCast(@as(u32, 0x7FFF0000) | @as(u16, @bitCast(found_entrypoint.boolean_constant_set.bits))));

    var int_constants: std.enums.EnumArray(pica.shader.register.Integral.Integer, [4]i8) = .initUndefined();

    {
        var current_const: usize = 0;
        var const_it = found_entrypoint.integer_constant_set.iterator();
        while (const_it.next()) |i| {
            int_constants.set(i, found_entrypoint.integer_constants[current_const]);
            current_const += 1;
        }

        queue.add(internal_regs, &shader.int_uniform, int_constants.values);
    }

    {
        var last_const: ?pica.shader.register.Source.Constant = null;

        var current_const: usize = 0;
        var const_it = found_entrypoint.floating_constant_set.iterator();
        while (const_it.next()) |f| {
            if(last_const == null or (@intFromEnum(last_const.?) > @intFromEnum(f)) or (@intFromEnum(f) - @intFromEnum(last_const.?)) != 1) {
                queue.add(internal_regs, &shader.float_uniform_index, .{
                    .index = f,
                    .mode = .f7_16,
                });
            }

            queue.add(internal_regs, &shader.float_uniform_data[0..3].*, found_entrypoint.floating_constants[current_const].data);

            current_const += 1;
            last_const = f;
        }
    }

    const outputs_minus_one: u4 = max_out: {
        var out_mask: pica.Registers.Internal.Shader.OutputMask = .{};
        var outputs: usize = 0;

        // NOTE: We could use mask in bitSet and `count`, benchmark needed.
        var out_it = found_entrypoint.output_set.iterator();

        while(out_it.next()) |o| {
            out_mask.set(o, true);
            outputs += 1;
        }

        queue.add(internal_regs, &shader.output_map_mask, out_mask);

        break :max_out @intCast(outputs - 1);
    };

    return .{
        .entrypoint = found_entrypoint,
        .outputs_minus_one = outputs_minus_one,

        .boolean_constants = found_entrypoint.boolean_constant_set,
        .integer_constants = int_constants,
    };
}

// TODO: Wtf is Gas? Not even azahar implements it.

const backend = @import("backend.zig");

const GraphicsState = backend.GraphicsState;
const RenderingState = backend.RenderingState;

const VertexInputLayout = backend.VertexInputLayout;
const TextureCombinerState = backend.TextureCombinerState;

const std = @import("std");
const zitrus = @import("zitrus");
const zpsh = zitrus.fmt.zpsh;

const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
