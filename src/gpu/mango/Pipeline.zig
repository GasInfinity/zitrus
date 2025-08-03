pub const CreateGraphics = extern struct {
    pub const RenderingInfo = extern struct {
        color_attachment_format: mango.Format,
        depth_stencil_attachment_format: mango.Format,
    };

    pub const VertexInputState = extern struct {
        bindings: [*]const mango.VertexInputBindingDescription,
        attributes: [*]const mango.VertexInputAttributeDescription,
        fixed_attributes: [*]const mango.VertexInputFixedAttributeDescription,

        bindings_len: usize,
        attributes_len: usize,
        fixed_attributes_len: usize,

        pub fn init(bindings: []const mango.VertexInputBindingDescription, attributes: []const mango.VertexInputAttributeDescription, fixed_attributes: []const mango.VertexInputFixedAttributeDescription) VertexInputState {
            return .{
                .bindings = bindings.ptr,
                .attributes = attributes.ptr,
                .fixed_attributes = fixed_attributes.ptr,

                .bindings_len = bindings.len,
                .attributes_len = attributes.len,
                .fixed_attributes_len = fixed_attributes.len,
            };
        }

        const AttributeConfig = gpu.Registers.Internal.GeometryPipeline.AttributeConfig;
        const AttributeBuffer = gpu.Registers.Internal.GeometryPipeline.AttributeBuffer;
        const AttributePermutation = gpu.Registers.Internal.Shader.AttributePermutation;
        
        const BindingAttribute = struct {
            offset: u8,
            index_format: packed struct(u8) {
                index: u4,
                format: gpu.AttributeFormat, 
            },

            pub fn lessThan(_: void, lhs: BindingAttribute, rhs: BindingAttribute) bool {
                return lhs.offset < rhs.offset;
            }
        };

        pub fn write(vtx_input_state: VertexInputState, queue: *cmd3d.Queue) void {
            const bindings = vtx_input_state.bindings[0..vtx_input_state.bindings_len]; 
            const attributes = vtx_input_state.attributes[0..vtx_input_state.attributes_len]; 
            const fixed_attributes = vtx_input_state.fixed_attributes[0..vtx_input_state.fixed_attributes_len]; 

            std.debug.assert(bindings.len < 12 and (attributes.len + fixed_attributes.len) < 12);

            var permutation: AttributePermutation = .{};
            var native_bindings: [12]AttributeBuffer.Config = @splat(std.mem.zeroes(AttributeBuffer.Config));
            var native_attribs: AttributeConfig = .{
                .low = .{},
                .high = .{
                    .attributes_end = @intCast((attributes.len + fixed_attributes.len) - 1)
                },
            };

            for (bindings, 0..) |binding, binding_index| {
                native_bindings[binding_index].high.bytes_per_vertex = binding.stride;
            }

            const BoundedAttributes = std.BoundedArray(BindingAttribute, 12);
            var sorted_binding_attributes: [12]BoundedAttributes = @splat(BoundedAttributes.init(0) catch unreachable);

            // TODO: writePackedStruct in zig 0.15
            for (attributes, 0..) |attribute, attribute_index| {
                // NOTE: This may seem redundant but they could come from C code!
                std.debug.assert(@intFromEnum(attribute.location) < 12);
                std.debug.assert(@intFromEnum(attribute.binding) < bindings.len);
                
                const native_format = attribute.format.nativeVertexFormat();

                permutation.setAttribute(@enumFromInt(attribute_index), @enumFromInt(@intFromEnum(attribute.location)));
                native_attribs.setAttribute(@enumFromInt(attribute_index), native_format);

                const attrib_binding_index = @intFromEnum(attribute.binding);
                const offset = attribute.offset;

                sorted_binding_attributes[attrib_binding_index].appendAssumeCapacity(.{ .index_format = .{ .index = @intCast(attribute_index), .format = native_format }, .offset = offset });
            }

            for (&sorted_binding_attributes, 0..) |*binding_attributes_array, binding_index| {
                if(binding_attributes_array.len == 0) {
                    break;
                }

                std.sort.insertion(BindingAttribute, binding_attributes_array.slice(), {}, BindingAttribute.lessThan);
                
                const current_binding = &native_bindings[binding_index];
                const binding_attributes = binding_attributes_array.constSlice();
                const first_format = binding_attributes[0].index_format.format;
                std.debug.assert(binding_attributes[0].offset == 0);
                
                var current_binding_alignment: usize = first_format.type.byteSize();
                var current_attribute_offset: usize = current_binding_alignment * (@as(usize, @intFromEnum(first_format.size)) + 1);
                var current_binding_attribute: u4 = 1;

                current_binding.setComponent(.@"0", @enumFromInt(binding_attributes[0].index_format.index));

                for (binding_attributes[1..]) |binding_attribute| {
                    const new_format = binding_attribute.index_format.format;
                    const new_format_type_size = new_format.type.byteSize();
                    const new_format_size = new_format_type_size * (@as(usize, @intFromEnum(new_format.size)) + 1);

                    current_binding_alignment = @max(current_binding_alignment, new_format_type_size);

                    const new_offset = binding_attribute.offset;
                    std.debug.assert(std.mem.isAligned(new_offset, new_format_type_size));

                    std.debug.assert(new_offset >= current_attribute_offset);
                    const extra_offset = new_offset - current_attribute_offset;

                    if(extra_offset > 0) {
                        @branchHint(.unlikely);
                        
                        const needed_padding = if(!std.mem.isAligned(current_attribute_offset, @sizeOf(f32))) offset: {
                            const padding_start_offset = std.mem.alignForward(usize, current_attribute_offset, @sizeOf(f32)) - current_attribute_offset;
                            const needed_padding = extra_offset - padding_start_offset;
                            std.debug.assert(std.mem.isAligned(needed_padding, @sizeOf(f32)));
                            
                            break :offset needed_padding;
                        } else extra_offset;

                        var remaining_padding = needed_padding;
                        inline for (&.{ AttributeBuffer.ArrayComponent.padding_16, AttributeBuffer.ArrayComponent.padding_12, AttributeBuffer.ArrayComponent.padding_8, AttributeBuffer.ArrayComponent.padding_4 }) |padding| {
                            appendPadAttributes(current_binding, &current_binding_attribute, &remaining_padding, padding);
                        }
                    }

                    current_binding.setComponent(@enumFromInt(current_binding_attribute), @enumFromInt(binding_attribute.index_format.index));
                    current_binding_attribute += 1;
                    current_attribute_offset = new_offset + new_format_size;
                }

                std.debug.assert(std.mem.isAligned(current_binding.high.bytes_per_vertex, current_binding_alignment));
                std.debug.assert(current_binding.high.bytes_per_vertex >= current_attribute_offset);

                const end_attribute_offset = std.mem.alignForward(usize, current_attribute_offset, current_binding_alignment);
                const needed_end_padding = current_binding.high.bytes_per_vertex - end_attribute_offset; 
                std.debug.assert(std.mem.isAligned(needed_end_padding, @sizeOf(f32)));

                var remaining_end_padding = needed_end_padding;
                inline for (&.{ AttributeBuffer.ArrayComponent.padding_16, AttributeBuffer.ArrayComponent.padding_12, AttributeBuffer.ArrayComponent.padding_8, AttributeBuffer.ArrayComponent.padding_4 }) |padding| {
                    appendPadAttributes(current_binding, &current_binding_attribute, &remaining_end_padding, padding);
                }

                native_bindings[binding_index].high.num_components = current_binding_attribute;
            }

            // TODO: Calculate binding paddings based on stride

            queue.addIncremental(internal_regs, .{
                &internal_regs.geometry_pipeline.attribute_buffer_base,
                &internal_regs.geometry_pipeline.attribute_config.low,
                &internal_regs.geometry_pipeline.attribute_config.high,
                &internal_regs.geometry_pipeline.attribute_buffer[0].offset,
                &internal_regs.geometry_pipeline.attribute_buffer[0].config.low,
                &internal_regs.geometry_pipeline.attribute_buffer[0].config.high,
            }, .{
                // NOTE: This MUST always be vram_begin as we depend on this for all physical offsets
                .fromPhysical(mango.global_attribute_buffer_base),
                native_attribs.low,
                native_attribs.high,
                0x00,
                native_bindings[0].low,
                native_bindings[0].high,
            });

            queue.addIncremental(internal_regs, .{
                &internal_regs.vertex_shader.attribute_permutation.low,
                &internal_regs.vertex_shader.attribute_permutation.high,
            }, .{
                permutation.low,
                permutation.high,
            });

            queue.add(internal_regs, &internal_regs.geometry_pipeline.vertex_shader_input_attributes, .init(native_attribs.high.attributes_end));
        }

        fn appendPadAttributes(current_binding: *AttributeBuffer.Config, current_binding_attribute: *u4, remaining_padding: *usize, padding: AttributeBuffer.ArrayComponent) void {
            std.debug.assert(@intFromEnum(padding) >= @intFromEnum(AttributeBuffer.ArrayComponent.padding_4));
            
            const components: usize = (@intFromEnum(padding) - @intFromEnum(AttributeBuffer.ArrayComponent.padding_4)) + 1;
            while (remaining_padding.* >= @sizeOf(f32) * components) : (remaining_padding.* -= @sizeOf(f32) * components) {
                current_binding.setComponent(@enumFromInt(current_binding_attribute.*), padding);
                current_binding_attribute.* += 1;
            }
        }
    };

    pub const ShaderStageState = extern struct {
    };

    pub const InputAssemblyState = extern struct {
        topology: mango.PrimitiveTopology,
    };

    pub const ViewportState = extern struct {
        scissor: ?*const mango.Scissor,
        viewport: ?*const mango.Viewport,
    };

    pub const RasterizationState = extern struct {
        front_face: mango.FrontFace,
        cull_mode: mango.CullMode,

        depth_mode: mango.DepthMode,
        depth_bias_enable: bool,
        depth_bias_constant: f32,
    };

    pub const LightingState = extern struct {
    };

    pub const TextureCombinerState = extern struct {
        texture_combiners: [*]const mango.TextureCombiner,
        texture_combiners_len: usize,

        texture_combiner_buffer_sources: [*]const mango.TextureCombiner.BufferSources,
        texture_combiner_buffer_sources_len: usize,

        pub fn init(texture_combiners: []const mango.TextureCombiner, texture_combiner_buffer_sources: []const mango.TextureCombiner.BufferSources) TextureCombinerState {
            return .{
                .texture_combiners = texture_combiners.ptr,
                .texture_combiners_len = texture_combiners.len,

                .texture_combiner_buffer_sources = texture_combiner_buffer_sources.ptr,
                .texture_combiner_buffer_sources_len = texture_combiner_buffer_sources.len,
            };
        }

        pub fn write(combiner_state: TextureCombinerState, queue: *cmd3d.Queue) void {
            const combiners = combiner_state.texture_combiners[0..combiner_state.texture_combiners_len];
            const combiner_buffer_sources = combiner_state.texture_combiner_buffer_sources[0..combiner_state.texture_combiner_buffer_sources_len];

            std.debug.assert(combiners.len > 0 and combiners.len <= 6);
            std.debug.assert(combiners.len == 1 or (combiners.len > 1 and combiner_buffer_sources.len == combiners.len - 1));

            var update_buffer: gpu.Registers.Internal.TextureCombiners.UpdateBuffer = .{
                .fog_mode = .disabled,
                .shading_density_source = .plain,
                .tex_combiner_1_color_buffer_src = .previous,
                .tex_combiner_2_color_buffer_src = .previous,
                .tex_combiner_3_color_buffer_src = .previous,
                .tex_combiner_4_color_buffer_src = .previous,
                .tex_combiner_1_alpha_buffer_src = .previous,
                .tex_combiner_2_alpha_buffer_src = .previous,
                .tex_combiner_3_alpha_buffer_src = .previous,
                .tex_combiner_4_alpha_buffer_src = .previous,
                .z_flip = false,
            };

            for (combiner_buffer_sources, 0..) |buffer_sources, index| {
                update_buffer.setColorBufferSource(@enumFromInt(index), @enumFromInt(@intFromEnum(buffer_sources.color_buffer_src)));
                update_buffer.setAlphaBufferSource(@enumFromInt(index), @enumFromInt(@intFromEnum(buffer_sources.alpha_buffer_src)));
            }

            queue.add(internal_regs, &internal_regs.texture_combiners.update_buffer, update_buffer);

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

                if(i < combiners.len) {
                    const defined_combiner = combiners[i];

                    queue.addIncremental(internal_regs, .{
                        &current_combiner_reg.sources,
                        &current_combiner_reg.factors,
                        &current_combiner_reg.operations,
                        &current_combiner_reg.color,
                        &current_combiner_reg.scales,
                    }, .{
                        .{
                            .color_src_0 = @enumFromInt(@intFromEnum(defined_combiner.color_src[0])),
                            .color_src_1 = @enumFromInt(@intFromEnum(defined_combiner.color_src[1])),
                            .color_src_2 = @enumFromInt(@intFromEnum(defined_combiner.color_src[2])),
                            .alpha_src_0 = @enumFromInt(@intFromEnum(defined_combiner.alpha_src[0])),
                            .alpha_src_1 = @enumFromInt(@intFromEnum(defined_combiner.alpha_src[1])),
                            .alpha_src_2 = @enumFromInt(@intFromEnum(defined_combiner.alpha_src[2])),
                        },
                        .{
                            .color_factor_0 = @enumFromInt(@intFromEnum(defined_combiner.color_factor[0])),
                            .color_factor_1 = @enumFromInt(@intFromEnum(defined_combiner.color_factor[1])),
                            .color_factor_2 = @enumFromInt(@intFromEnum(defined_combiner.color_factor[2])),
                            .alpha_factor_0 = @enumFromInt(@intFromEnum(defined_combiner.alpha_factor[0])),
                            .alpha_factor_1 = @enumFromInt(@intFromEnum(defined_combiner.alpha_factor[1])),
                            .alpha_factor_2 = @enumFromInt(@intFromEnum(defined_combiner.alpha_factor[2])),
                        },
                        .{
                            .color_op = @enumFromInt(@intFromEnum(defined_combiner.color_op)),
                            .alpha_op = @enumFromInt(@intFromEnum(defined_combiner.alpha_op)),
                        },
                        defined_combiner.constant,
                        .{
                            .color_scale = @enumFromInt(@intFromEnum(defined_combiner.color_scale)),
                            .alpha_scale = @enumFromInt(@intFromEnum(defined_combiner.alpha_scale)),
                        }
                    });
                } else {
                    queue.addIncremental(internal_regs, .{
                        &current_combiner_reg.sources,
                        &current_combiner_reg.factors,
                        &current_combiner_reg.operations,
                    }, .{
                        .{
                            .color_src_0 = .previous,
                            .color_src_1 = .previous,
                            .color_src_2 = .previous,
                            .alpha_src_0 = .previous,
                            .alpha_src_1 = .previous,
                            .alpha_src_2 = .previous,
                        },
                        .{
                            .color_factor_0 = .src_color,
                            .color_factor_1 = .src_color,
                            .color_factor_2 = .src_color,
                            .alpha_factor_0 = .src_alpha,
                            .alpha_factor_1 = .src_alpha,
                            .alpha_factor_2 = .src_alpha,
                        },
                        .{
                            .color_op = .replace,
                            .alpha_op = .replace,
                        },
                    });
                    queue.add(internal_regs, &current_combiner_reg.scales, .{
                        .color_scale = .@"1x",
                        .alpha_scale = .@"1x",
                    });
                }
            }
        }
    };

    pub const AlphaDepthStencilState = extern struct {
        pub const StencilOperationState = extern struct {
            fail_op: mango.StencilOperation,
            pass_op: mango.StencilOperation,
            depth_fail_op: mango.StencilOperation,
            compare_op: mango.CompareOperation,
            compare_mask: u8,
            write_mask: u8,
            reference: u8,
        };

        alpha_test_enable: bool,
        alpha_test_compare_op: mango.CompareOperation,
        alpha_test_reference: u8,

        depth_test_enable: bool,
        depth_write_enable: bool,
        depth_compare_op: mango.CompareOperation,

        stencil_test_enable: bool,
        back_front: StencilOperationState,  
    };

    pub const ColorBlendState = extern struct {
        pub const Attachment = extern struct {
            blend_enable: bool,
            src_color_blend_factor: mango.BlendFactor,
            dst_color_blend_factor: mango.BlendFactor,
            color_blend_op: mango.BlendOperation,
            src_alpha_blend_factor: mango.BlendFactor,
            dst_alpha_blend_factor: mango.BlendFactor,
            alpha_blend_op: mango.BlendOperation,

            color_write_mask: mango.ColorComponentFlags,
            color_write_enable: bool,
        };

        logic_op_enable: bool,
        logic_op: mango.LogicOperation,
        
        attachment: Attachment,
        blend_constants: [4]u8,
    };

    pub const DynamicState = packed struct(u32) {
        viewport: bool = false,
        scissor: bool = false,

        depth_mode: bool = false,
        depth_bias_enable: bool = false,
        depth_bias: bool = false,

        cull_mode: bool = false,
        front_face: bool = false,

        depth_test_enable: bool = false,
        depth_write_enable: bool = false,
        depth_compare_op: bool = false,

        stencil_compare_mask: bool = false,
        stencil_write_mask: bool = false,
        stencil_reference: bool = false,
        stencil_test: bool = false,
        stencil_test_operation: bool = false, 

        logic_op_enable: bool = false,
        logic_op: bool = false,

        blend_enable: bool = false,
        blend_equation: bool = false,

        alpha_test: bool = false,
        alpha_test_operation: bool = false,
        alpha_test_reference: bool = false,
        
        color_write_mask: bool = false,
        color_write: bool = false,
        primitive_topology: bool = false,

        texture_combiner: bool = false,

        _: u6 = 0,
    };

    rendering_info: RenderingInfo,
    vertex_input_state: ?*const VertexInputState,
    input_assembly_state: ?*const InputAssemblyState,
    viewport_state: ?*const ViewportState,
    rasterization_state: ?*const RasterizationState,
    alpha_depth_stencil_state: ?*const AlphaDepthStencilState,
    lighting_state: ?*const LightingState,
    texture_combiner_state: ?*const TextureCombinerState,
    color_blend_state: ?*const ColorBlendState,
    dynamic_state: DynamicState,

    /// Writes non-dynamic state from a `CreateGraphics` to a hardware 3D CommandQueue.
    ///
    /// This function performs numerous checks to optimize the written
    /// commands so try to minimize calls to this function!
    pub fn writeStaticState(create: CreateGraphics, queue: *cmd3d.Queue) void {
        const dyn = create.dynamic_state;

        create.vertex_input_state.?.write(queue);

        // NOTE: It doesn't make sense to set internal_regs.geometry_pipeline.start_draw_function to config mode always, what do you do more, pipeline changes or drawcalls bro? (silly question)
        
        // queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .config);
        // TODO: write shader state here
        // queue.add(internal_regs, &internal_regs.geometry_pipeline.start_draw_function, .drawing);

        if(!dyn.primitive_topology) {
            const topo = create.input_assembly_state.?.topology;

            queue.add(internal_regs, &internal_regs.geometry_pipeline.primitive_config, .{
                .total_vertex_outputs = 0, // TODO: shaders
                .topology = topo.native(),
            });

            queue.add(internal_regs, &internal_regs.geometry_pipeline.config, .{
                .geometry_shader_usage = .disabled,
                .drawing_triangles = topo == .triangle_list,
                .use_reserved_geometry_subdivision = false,
            });

            queue.addMasked(internal_regs, &internal_regs.geometry_pipeline.config_2, .{
                .drawing_triangles = topo == .triangle_list,
            }, 0b0010);
        }

        if(!dyn.texture_combiner) {
            create.texture_combiner_state.?.write(queue);
        }

        if(!dyn.viewport) {
            const static_viewport = create.viewport_state.?.viewport.?;
            const flt_width: f32 = @floatFromInt(static_viewport.rect.extent.width);
            const flt_height: f32 = @floatFromInt(static_viewport.rect.extent.height);

            if(!dyn.scissor) {
                const static_scissor = create.viewport_state.?.scissor.?;

                if(!dyn.front_face and !dyn.cull_mode) {
                    const raster_state = create.rasterization_state.?;

                    queue.addIncremental(internal_regs, .{
                        &internal_regs.rasterizer.faceculling_config,
                        &internal_regs.rasterizer.viewport_h_scale,
                        &internal_regs.rasterizer.viewport_h_step,
                        &internal_regs.rasterizer.viewport_v_scale,
                        &internal_regs.rasterizer.viewport_v_step,
                    }, .{
                        .init(raster_state.cull_mode.native(raster_state.front_face)),
                        .init(.of(flt_width / 2.0)),
                        .init(.of(2.0 / flt_width)),
                        .init(.of(flt_height / 2.0)),
                        .init(.of(2.0 / flt_height)),
                    });
                } else {
                    static_viewport.writeViewportParameters(queue);
                }
                
                queue.addIncremental(internal_regs, .{
                    &internal_regs.rasterizer.scissor_config,
                    &internal_regs.rasterizer.scissor_start,
                    &internal_regs.rasterizer.scissor_end,
                    &internal_regs.rasterizer.viewport_xy,
                }, .{
                    .init(static_scissor.mode.native()),
                    @bitCast(static_scissor.rect.offset),
                    .{ .x = static_scissor.rect.offset.x + static_scissor.rect.extent.width, .y = static_scissor.rect.offset.y + static_scissor.rect.extent.height },
                    .{ .x = static_viewport.rect.offset.x, .y = static_viewport.rect.offset.y },
                });
            } else static_viewport.writeViewportParameters(queue);

            if(!dyn.depth_bias_enable and !dyn.depth_bias) {
                const depth_map_scale = (static_viewport.min_depth - static_viewport.max_depth); 
                const depth_map_offset = static_viewport.min_depth + (if(create.rasterization_state.?.depth_bias_enable)
                    create.rasterization_state.?.depth_bias_constant
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
        } else {
            if(!dyn.scissor) {
                create.viewport_state.?.scissor.?.write(queue);
            }

            if(!dyn.front_face and !dyn.cull_mode) {
                const raster_state = create.rasterization_state.?;

                queue.add(internal_regs, &internal_regs.rasterizer.faceculling_config, .init(raster_state.cull_mode.native(raster_state.front_face)));
            }
        }

        // NOTE: could be merged above after earlydepth_data which is after viewport_xy when implemented
        if(!dyn.depth_mode) {
            queue.add(internal_regs, &internal_regs.rasterizer.depth_map_mode, .init(create.rasterization_state.?.depth_mode.native()));
        }

        // zig fmt: off
        if(!dyn.logic_op_enable
        and (!dyn.blend_enable or create.color_blend_state.?.logic_op_enable)
        and !dyn.alpha_test
        and !dyn.stencil_test
        and !dyn.depth_test_enable) {
        // zig fmt: on
            const color_blend = create.color_blend_state.?;
            const alpha_depth_stencil = create.alpha_depth_stencil_state.?;

            const color_writing_enabled = create.rendering_info.color_attachment_format != .undefined and !dyn.color_write_mask and !dyn.color_write and color_blend.attachment.color_write_enable;
            const color_write_mask = color_blend.attachment.color_write_mask;

            const depth_writing_enabled = create.rendering_info.depth_stencil_attachment_format != .undefined and (!dyn.depth_write_enable and alpha_depth_stencil.depth_write_enable) and alpha_depth_stencil.depth_test_enable;

            queue.addIncremental(internal_regs, .{
                &internal_regs.framebuffer.color_operation,
                &internal_regs.framebuffer.blend_config,
                &internal_regs.framebuffer.logic_operation,
                &internal_regs.framebuffer.blend_color,
                &internal_regs.framebuffer.fragment_operation_alpha_test,
                &internal_regs.framebuffer.stencil_test,
                &internal_regs.framebuffer.stencil_operation,
                &internal_regs.framebuffer.depth_color_mask,
            }, .{
                .{
                    .fragment_operation = .default,
                    .mode = if(color_blend.logic_op_enable or !color_blend.attachment.blend_enable) .logic else .blend,
                },
                .{
                    .color_op = @enumFromInt(@intFromEnum(color_blend.attachment.color_blend_op)),
                    .alpha_op = @enumFromInt(@intFromEnum(color_blend.attachment.alpha_blend_op)),
                    .color_src_factor = @enumFromInt(@intFromEnum(color_blend.attachment.src_color_blend_factor)),
                    .color_dst_factor = @enumFromInt(@intFromEnum(color_blend.attachment.dst_color_blend_factor)),
                    .alpha_src_factor = @enumFromInt(@intFromEnum(color_blend.attachment.src_alpha_blend_factor)),
                    .alpha_dst_factor = @enumFromInt(@intFromEnum(color_blend.attachment.dst_alpha_blend_factor)),
                }, 
                .init(if(!dyn.logic_op or !color_blend.logic_op_enable) .copy else @enumFromInt(@intFromEnum(color_blend.logic_op))),
                color_blend.blend_constants,
                .{
                    .enable = alpha_depth_stencil.alpha_test_enable,
                    .op = if(!dyn.alpha_test_operation) @enumFromInt(@intFromEnum(alpha_depth_stencil.alpha_test_compare_op)) else .never,
                    .reference = if(!dyn.alpha_test_reference) alpha_depth_stencil.alpha_test_reference else 0,
                },
                .{
                    .enable = alpha_depth_stencil.stencil_test_enable,
                    .op = if(!dyn.stencil_test_operation) @enumFromInt(@intFromEnum(alpha_depth_stencil.back_front.compare_op)) else .never,
                    .compare_mask = if(!dyn.stencil_compare_mask) alpha_depth_stencil.back_front.compare_mask else 0x00,
                    .reference = if(!dyn.stencil_reference) alpha_depth_stencil.back_front.reference else 0x00,
                    .write_mask = if(!dyn.stencil_write_mask) alpha_depth_stencil.back_front.write_mask else 0x00,
                },
                if(!dyn.stencil_test_operation) .{
                    .fail_op = @enumFromInt(@intFromEnum(alpha_depth_stencil.back_front.fail_op)), 
                    .depth_fail_op = @enumFromInt(@intFromEnum(alpha_depth_stencil.back_front.depth_fail_op)), 
                    .pass_op = @enumFromInt(@intFromEnum(alpha_depth_stencil.back_front.pass_op)), 
                } else .{
                    .fail_op = .zero,
                    .depth_fail_op = .zero,
                    .pass_op = .zero, 
                },
                .{
                    .enable_depth_test = alpha_depth_stencil.depth_test_enable,
                    .depth_op = if(!dyn.depth_compare_op) @enumFromInt(@intFromEnum(alpha_depth_stencil.depth_compare_op)) else .never,
                    .r_write_enable = if(color_writing_enabled) color_write_mask.r_enable else false,
                    .g_write_enable = if(color_writing_enabled) color_write_mask.g_enable else false,
                    .b_write_enable = if(color_writing_enabled) color_write_mask.b_enable else false,
                    .a_write_enable = if(color_writing_enabled) color_write_mask.a_enable else false,
                    .depth_write_enable = depth_writing_enabled,
                }
            });

            const all_channels_same = color_write_mask.r_enable == color_write_mask.g_enable and color_write_mask.g_enable == color_write_mask.b_enable and color_write_mask.b_enable == color_write_mask.a_enable;
            const color_buffer_write_needed = color_writing_enabled and (!all_channels_same or color_write_mask.r_enable);

            const color_buffer_read_needed = color_writing_enabled and (!all_channels_same or (color_blend.attachment.blend_enable or (color_blend.logic_op_enable and (!dyn.logic_op and switch (color_blend.logic_op) {
                .clear, .set, .copy, .copy_inverted => false,
                else => true,
            }))));

            const depth_buffer_read_needed = alpha_depth_stencil.depth_test_enable and (!dyn.depth_compare_op and (switch (alpha_depth_stencil.depth_compare_op) {
                .never, .always => false,
                else => true,
            }));

            queue.addIncremental(internal_regs, .{
                &internal_regs.framebuffer.color_buffer_reading,
                &internal_regs.framebuffer.color_buffer_writing,
                &internal_regs.framebuffer.depth_buffer_reading,
                &internal_regs.framebuffer.depth_buffer_writing,
                &internal_regs.framebuffer.depth_buffer_format,
                &internal_regs.framebuffer.color_buffer_format,
            }, .{
                if(color_buffer_read_needed) .enable else .disable,
                if(color_buffer_write_needed) .enable else .disable,
                .{
                    .depth_enable = depth_buffer_read_needed,
                    .stencil_enable = false, // TODO: stencil test reading enable
                },
                .{
                    .depth_enable = depth_writing_enabled,
                    .stencil_enable = false, // TODO: stencil test writing enable
                },
                .init(if(create.rendering_info.depth_stencil_attachment_format != .undefined) create.rendering_info.depth_stencil_attachment_format.nativeDepthStencilFormat() else .d16),
                .init(if(create.rendering_info.color_attachment_format != .undefined) create.rendering_info.color_attachment_format.nativeColorFormat() else .abgr8888),
            });
        }

        queue.add(internal_regs, &internal_regs.framebuffer.render_buffer_block_size, .{ .mode = .@"8x8" });
    }
};

// TODO: Shadow pass pipeline (its literally another mode)

// TODO: Wtf is Gas? Not even azahar implements it.

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
