// XXX: THIS IS A PLAYGROUND, NOT EVEN USABLE UNLESS YOU KNOW WHAT YOU'RE DOING!
// MISSING APT HOME AND SLEEP HANDLING, DON'T TRY TO GO HOME NOR PUT THE 3DS TO SLEEP
// EXIT THE APP FIRST
// Won't happen anything to you 3ds but you'll loose 30secs of your life hard-resetting your console

// TODO: Rewrite this when the assembler is finished and a basic abstraction is written :D

pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    var apt = try Applet.init(srv);
    defer apt.deinit(srv);

    var hid = try Hid.init(srv);
    defer hid.deinit();

    var gsp = try GspGpu.init(srv);
    defer gsp.deinit();

    var framebuffer = try Framebuffer.init(.{
        .double_buffer = .init(.{
            .top = false,
            .bottom = false,
        }),
        .color_format = .init(.{
            .top = .bgr8,
            .bottom = .bgr8,
        }),
        .phys_linear_allocator = horizon.heap.linear_page_allocator,
    });
    defer framebuffer.deinit();

    const top = framebuffer.currentFramebuffer(.top);
    const bottom = framebuffer.currentFramebuffer(.bottom);
    @memset(top, 0xFF);
    @memset(bottom, 0xFF);

    const bot_renderbuf = @as([*]align(8) u8, @ptrFromInt(horizon.memory.vram_a_begin))[0 .. 320 * 240 * 4];
    // defer horizon.heap.linear_page_allocator.free(bot_renderbuf);

    const internal = &horizon.memory.gpu_registers.internal;
    const commandBuffer = try horizon.heap.linear_page_allocator.alignedAlloc(u32, 8, 4096);
    defer horizon.heap.linear_page_allocator.free(commandBuffer);

    const at_buf = try horizon.heap.linear_page_allocator.alignedAlloc(u8, 16, 8 * 4);
    defer horizon.heap.linear_page_allocator.free(at_buf);

    // For rendering with arrays
    const s_at_buf: []i8 = @ptrCast(at_buf);
    s_at_buf[0..4].* = .{ -0x7F, -0x7F, 0, 0x7F };
    at_buf[4..7].* = .{ 255, 0, 0 };
    s_at_buf[7..11].* = .{ 0x7F, -0x7F, 0, 0x7F };
    at_buf[11..14].* = .{ 0, 255, 0 };
    s_at_buf[14..18].* = .{ -0x7F, 0x7F, 0, 0x7F };
    at_buf[18..21].* = .{ 0, 0, 255 };
    s_at_buf[21..25].* = .{ 0x7F, 0x7F, 0, 0x7F };
    at_buf[25..28].* = .{ 0, 255, 255 };

    try gsp.sendFlushDataCache(at_buf);
    // const aligned_base = @intFromEnum(horizon.memory.toPhysical(@intFromPtr(at_buf.ptr))) >> 3;

    // For fixed attributes
    const as_fixed_attr: [8]F7_16x4 = .{
        .pack(.of(1), .of(0), .of(1), .of(1)),
        .pack(.of(-1), .of(-1), .of(0), .of(1)),

        .pack(.of(1),  .of(1), .of(0), .of(1)),
        .pack(.of(1), .of(-1), .of(0), .of(1)),

        .pack(.of(0), .of(1), .of(1), .of(1)),
        .pack(.of(-1), .of(1), .of(0), .of(1)),

        .pack(.of(0), .of(1), .of(0), .of(1)),
        .pack(.of(1), .of(1), .of(0), .of(1)),
    };

    // Learn the hard way that memory fills only work with vram.
    // 3dbrew GSP Shared memory: "Addresses should be aligned to 8 bytes and must be in linear, QTM or VRAM memory"
    // 3dbrew MemoryFill registers: "The addresses must be part of VRAM."
    try gsp.submitMemoryFill(.{ .init(bot_renderbuf, .fill32(0xCCAACCFF)), null }, .none);
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.contains(.psc0)) {
            break;
        }
    }

    // Initial display transfer (only used for debugging purposes). You cannot draw directly to the framebuffer as you must do a tiled->linear transformation.
    try gsp.submitDisplayTransfer(bot_renderbuf.ptr, bottom.ptr, .abgr8, .{ .x = 240, .y = 320 }, .bgr8, .{ .x = 240, .y = 320 }, .none, .none);
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.contains(.ppf)) {
            break;
        }
    }

    var queue: command.Queue = .initBuffer(commandBuffer);

    // Adapted from https://problemkaputt.de/gbatek.htm#3dsgputriangledrawingsamplecode but writing through commandlists instead of doing it directly and some more fixes (texenv0, lighting disable)
    // TODO: This is VERY low level. Needs API
    queue.add(internal, &internal.framebuffer.render_buffer_invalidate, .trigger);
    queue.add(internal, &internal.framebuffer.depth_buffer_location, .fromPhysical(horizon.memory.toPhysical(@intFromPtr(bot_renderbuf.ptr))));
    queue.add(internal, &internal.framebuffer.color_buffer_location, .fromPhysical(horizon.memory.toPhysical(@intFromPtr(bot_renderbuf.ptr))));
    // We'll render to the bottom screen, thats why 320x240 (physically they are 240x320)
    queue.add(internal, &internal.framebuffer.render_buffer_dimensions, .init(240, 320, true));
    queue.add(internal, &internal.rasterizer.faceculling_config, .{ .mode = .none });
    queue.add(internal, &internal.rasterizer.viewport_h_scale, .fromFloat(.of(240.0 / 2.0)));
    queue.add(internal, &internal.rasterizer.viewport_v_scale, .fromFloat(.of(320.0 / 2.0)));
    queue.add(internal, &internal.rasterizer.viewport_h_step, .fromFloat(.of(2.0 / 240.0)));
    queue.add(internal, &internal.rasterizer.viewport_v_step, .fromFloat(.of(2.0 / 320.0)));
    queue.add(internal, &internal.rasterizer.viewport_xy, .{ .x = 0, .y = 0 });
    queue.add(internal, &internal.rasterizer.scissor_config, .{ .mode = .disable });
    queue.add(internal, &internal.framebuffer.color_operation, .{
        .fragment_operation = .default,
        .mode = .blend,
    });
    // Basically replace the color: Ofb = 1*src + 0*dst
    queue.add(internal, &internal.framebuffer.blend_config, .{
        .rgb_equation = .add,
        .alpha_equation = .add,
        .rgb_src_function = .one,
        .rgb_dst_function = .zero,
        .alpha_src_function = .one,
        .alpha_dst_function = .zero,
    });
    queue.add(internal, &internal.framebuffer.fragment_operation_alpha_test, .{
        .enable = false,
        .function = .never,
        .reference_value = 0,
    });
    queue.add(internal, &internal.framebuffer.stencil_test, .{
        .enable = false,
        .function = .never,
        .src_mask = 0,
        .dst_mask = 0,
        .value = 0,
    });
    queue.add(internal, &internal.framebuffer.logic_operation, .{ .operation = .clear });
    queue.add(internal, &internal.framebuffer.depth_color_mask, .{
        .enable_depth_test = false,
        .depth_function = .never,
        .r_write_enable = true,
        .g_write_enable = true,
        .b_write_enable = true,
        .a_write_enable = true,
        .depth_write_enable = false,
    });
    queue.add(internal, &internal.framebuffer.color_buffer_reading, .enable);
    queue.add(internal, &internal.framebuffer.color_buffer_writing, .enable);
    queue.add(internal, &internal.framebuffer.depth_buffer_reading, .disable);
    queue.add(internal, &internal.framebuffer.depth_buffer_writing, .disable);
    queue.add(internal, &internal.framebuffer.color_buffer_format, .{ .pixel_size = .@"32", .format = .abgr8 });
    queue.add(internal, &internal.framebuffer.depth_buffer_format, .{ .format = .f16 });
    queue.add(internal, &internal.framebuffer.render_buffer_block_size, .{ .mode = .@"8x8" });
    queue.add(internal, &internal.framebuffer.early_depth_test_2, .disable);
    queue.add(internal, &internal.rasterizer.early_depth_test_1, .disable);
    queue.add(internal, &internal.rasterizer.depth_map_enable, .enable);
    queue.add(internal, &internal.rasterizer.depth_map_scale, .fromFloat(.of(-1.0)));
    queue.add(internal, &internal.rasterizer.depth_map_offset, .fromFloat(.of(0.0)));
    // Just in case, 
    queue.add(internal, &internal.texturing.lighting_enable, .disable);
    queue.add(internal, &internal.fragment_lighting.disable, .disable);
    // enable texture environment 0 to just replace the color. PLEASE, unless you want to get black output and debug it for 12h :D
    queue.add(internal, &internal.texturing_environment.texture_environment_0.source, .{
        .rgb_source_0 = .primary_color,
        .rgb_source_1 = .primary_color,
        .rgb_source_2 = .primary_color,
        .alpha_source_0 = .primary_color,
        .alpha_source_1 = .primary_color,
        .alpha_source_2 = .primary_color,
    });
    queue.add(internal, &internal.texturing_environment.texture_environment_0.combiner, .{
        .rgb_combine = .replace,
        .alpha_combine = .replace,
    });
    queue.add(internal, &internal.texturing_environment.update_buffer, .{
        .fog_mode = .disabled,
        .shading_density_source = .plain,
        .tex_env_1_rgb_buffer_input = .previous_buffer,
        .tex_env_2_rgb_buffer_input = .previous_buffer,
        .tex_env_3_rgb_buffer_input = .previous_buffer,
        .tex_env_4_rgb_buffer_input = .previous_buffer,
        .tex_env_1_alpha_buffer_input = .previous_buffer,
        .tex_env_2_alpha_buffer_input = .previous_buffer,
        .tex_env_3_alpha_buffer_input = .previous_buffer,
        .tex_env_4_alpha_buffer_input = .previous_buffer,
        .z_flip  = false,
    });
    queue.add(internal, &internal.geometry_pipeline.start_draw_function, .config);
    queue.add(internal, &internal.rasterizer.shader_output_map_total, .{ .num = 2 });
    queue.add(internal, &internal.vertex_shader.output_map_mask, .{
        .o0_enabled = true,
        .o1_enabled = true,
    });
    queue.add(internal, &internal.rasterizer.shader_output_map_output[0..2].*, .{ .{
        .x = .color_r,
        .y = .color_g,
        .z = .color_b,
        .w = .color_a,
    }, .{
        .x = .position_x,
        .y = .position_y,
        .z = .position_z,
        .w = .position_w,
    }});
    queue.add(internal, &internal.rasterizer.shader_output_attribute_clock, .{
        .position_z_present = true,
        .color_present = true,
    });
    queue.add(internal, &internal.rasterizer.shader_output_attribute_mode, .{ .use_texture_coordinates = false });
    queue.add(internal, &internal.geometry_pipeline.vertex_shader_input_attributes, .initTotal(2 - 1));
    queue.add(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_1, .initTotal(2 - 1));
    queue.add(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_2, .initTotal(2 - 1));

    // don't use geometry shader + 2 input registers
    queue.add(internal, &internal.geometry_pipeline.enable_geometry_shader_configuration, .disable);
    queue.add(internal, &internal.vertex_shader.input_buffer_config, .{
        .num_input_attributes = (2 - 1),
        .enabled_for_vertex_0 = true,
        .enabled_for_vertex_1 = true,
    });

    queue.add(internal, &internal.geometry_pipeline.primitive_config, .{
        .total_vertex_outputs = (2 - 1),
        .mode = .triangle_strip,
    });

    // identity map attributes to input registers
    queue.add(internal, &internal.vertex_shader.attribute_permutation_low, .{});
    queue.add(internal, &internal.vertex_shader.attribute_permutation_high, .{});

    // enable o0 o1
    queue.add(internal, &internal.vertex_shader.code_transfer_index, .initIndex(0));
    queue.add(internal, &internal.vertex_shader.code_transfer_data[0..3].*, .{
        .{ .register = .{
            .operand_descriptor_id = 0,
            .dst = .o0,
            .src1 = .v0,
            .src2 = .v0,
            .opcode = .mov,
        }},
        .{ .register = .{
            .operand_descriptor_id = 0,
            .dst = .o1,
            .src1 = .v1,
            .src2 = .v0,
            .opcode = .mov,
        }},
        .{ .unparametized = .{ .opcode = .end } },
    });
    queue.add(internal, &internal.vertex_shader.code_transfer_end, .trigger);

    queue.add(internal, &internal.vertex_shader.operand_descriptors_index, .initIndex(0));
    // mask xyzw, selector xyzw
    queue.add(internal, &internal.vertex_shader.operand_descriptors_data[0], .{});
    // lower 16 bits, entrypoint starts at instruction 0
    queue.add(internal, &internal.vertex_shader.entrypoint, .initEntry(0));
    
    // drawing triangle strips
    queue.add(internal, &internal.geometry_pipeline.config, .{});
    // drawing triangle strips + inputting vtx data
    queue.add(internal, &internal.geometry_pipeline.config_2, .{
        .inputting_vertices_or_draw_arrays = true,
    });
    // immediate mode start
    queue.add(internal, &internal.geometry_pipeline.restart_primitive, .trigger);
    // start drawing
    queue.add(internal, &internal.geometry_pipeline.start_draw_function, .drawing);
    queue.add(internal, &internal.geometry_pipeline.fixed_attribute_index, .immediate_mode);
    inline for (0..8) |i| {
        queue.add(internal, &internal.geometry_pipeline.fixed_attribute_data, as_fixed_attr[i]);
    }
    queue.add(internal, &internal.geometry_pipeline.start_draw_function, .config);
    queue.add(internal, &internal.geometry_pipeline.clear_post_vertex_cache, .trigger);
    queue.add(internal, &internal.framebuffer.render_buffer_flush, .trigger);

    // TODO: use attribute buffers and rewrite with add()
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_base), aligned_base);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_format_low), 0x9C); // low word
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_format_high), @as(u32, 1) << 28); // high word
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer[0].offset), 0);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer[0].config_low), 0x76543210); // low word
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer[0].config_high), (@as(u32, 2) << 28) + (@as(u32, 4 + 3) << 16) + 0xBA98); // low word
    
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_num_vertices), 4);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_first_index), 0);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.start_draw_function), 0);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.attribute_buffer_draw_arrays), 1);
    // queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.start_draw_function), 1);
    queue.finalize();

    // TODO: This is currently not that great...
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.contains(.vblank_top)) {
            break;
        }
    }

    // Flush entire linear memory again just in case before main loop...
    try gsp.sendFlushDataCache(@as([*]u8, @ptrFromInt(horizon.memory.linear_heap_begin))[0..(horizon.memory.linear_heap_end - horizon.memory.linear_heap_begin)]);

    try framebuffer.flushBuffers(&gsp);
    try framebuffer.present(&gsp);

    try gsp.sendSetLcdForceBlack(false);
    defer if (gsp.has_right) gsp.sendSetLcdForceBlack(true) catch {};

    var running = true;
    while (running) {
        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => running = false,
            else => {},
        };

        while (try apt.pollEvent(srv, &gsp)) |e| switch (e) {
            else => {},
        };

        const input = hid.readPadInput();

        if (input.current.start) {
            break;
        }

        try gsp.submitProcessCommandList(@alignCast(queue.buffer[0..queue.current_index]), .none, .flush, .none);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.contains(.p3d)) {
                break;
            }
        }

        try gsp.submitDisplayTransfer(bot_renderbuf.ptr, bottom.ptr, .abgr8, .{ .x = 240, .y = 320 }, .bgr8, .{ .x = 240, .y = 320 }, .none, .none);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.contains(.ppf)) {
                break;
            }
        }

        try framebuffer.flushBuffers(&gsp);
        try framebuffer.present(&gsp);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.contains(.vblank_top)) {
                break;
            }
        }

        running = running and !apt.flags.should_close;
    }
}

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Framebuffer = zitrus.gpu.Framebuffer;

const gpu = zitrus.gpu;
const F7_16x4 = gpu.F7_16x4;
const command = gpu.command;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
