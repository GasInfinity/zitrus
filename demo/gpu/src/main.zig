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
    const asb = std.mem.asBytes;
    const f24 = gpu.F7_16.Float;
    const vtx_buf = std.mem.bytesAsSlice(u32, &(
                    asb(&f24.of(1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++
                    asb(&f24.of(-1))[0..3].* ++ asb(&f24.of(-1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++

                    asb(&f24.of(1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++
                    asb(&f24.of(1))[0..3].* ++ asb(&f24.of(-1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++

                    asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++
                    asb(&f24.of(-1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++

                    asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].* ++
                    asb(&f24.of(1))[0..3].* ++ asb(&f24.of(1))[0..3].* ++ asb(&f24.of(0))[0..3].* ++ asb(&f24.of(1))[0..3].*));

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
    // TODO: Obviously this is NOT an API. Abstracting this will be fun
    const buf_phys = @intFromEnum(horizon.memory.toPhysical(@intFromPtr(bot_renderbuf.ptr))) >> 3;
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.render_buffer_invalidate), 1);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.depth_buffer_location), buf_phys + bot_renderbuf.len);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.color_buffer_location), buf_phys);
    // We'll render to the bottom screen
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.render_buffer_dimensions), ((@as(u32, 1) << 24) + (320 - 1) * 0x1000 + 240));
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.render_buffer_dimensions_1), ((@as(u32, 1) << 24) + (320 - 1) * 0x1000 + 240));
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.faceculling_config), 0);
    // 320 / 2 | 240 / 2 | 2 / 320 | 2 / 240
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.viewport_v_scale), 0x0045E000);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.viewport_h_scale), 0x00464000);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.viewport_v_step), 0x38111100);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.viewport_h_step), 0x37999900);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.viewport_xy), 0);
    // Disable everything, only enable basic color (no alpha)
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.scissor_config), 0);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.color_operation), 0x00E40100);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.blend_config), 0x06020000);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.fragment_operation_alpha), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.stencil_test), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.logic_operation), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.depth_color_mask), 0x1F00);
    // Enable reading and writing rgba
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.color_buffer_reading), 0x0F);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.color_buffer_writing), 0x0F);
    // Don't write to the depth buffer
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.depth_buffer_reading), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.depth_buffer_writing), 0x00);
    // rgba8 32bits pixel size
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.color_buffer_format), 0x02);
    // irrelevant, we don't write to the depth buffer
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.depth_buffer_format), 0x03);
    // 8x8 tile size
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.render_buffer_block_size), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.early_depth_test_2), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.early_depth_test_1), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.depth_map_enable), 0x01);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.depth_map_scale), 0x00bf0000);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.depth_map_offset), 0x00000000);
    // Just in case, 
    queue.addCommand(.fromRegister(internal, &internal.texturing.lighting_enable), 0);
    queue.addCommand(.fromRegister(internal, &internal.fragment_lighting.disable), 1);
    // enable texture environment 0 to just replace the color. PLEASE, unless you want to get black output and debug it for 12h :D
    queue.addCommand(.fromRegister(internal, &internal.texturing_environment.texture_environment_0.source), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.texturing_environment.texture_environment_0.combiner), 0x00);
    queue.addCommand(.fromRegister(internal, &internal.texturing_environment.update_buffer), 0);

    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.start_draw_function), 1);
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.shader_output_map_total), 2);
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.output_map_mask), 0b11);
    // color.rgba
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.shader_output_map_output[0]), 0x0B0A0908);
    // position.xyzw
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.shader_output_map_output[1]), 0x03020100);
    // position.z + color present
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.shader_output_attribute_clock), 0b11);
    // don't use texture coordinates
    queue.addCommand(.fromRegister(internal, &internal.rasterizer.shader_output_attribute_mode), 0x00);
    // 2 regs (regs - 1)
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.vertex_shader_num_attributes), 1);
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_1), 1);
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_2), 1);

    // don't use geometry shader + 2 input registers
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.input_buffer_config), (@as(u32, 0xA0) << 24) | 1);

    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.vertex_shader_common_mode), 0);
    // triangle strip + 2 output registers
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.primitive_config), (@as(u32, 1) << 8) | 1);

    // identity map vtx attribute to input register index
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.attribute_permutation_low), 0x76543210);
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.attribute_permutation_high), 0xfedcba98);
    // enable o0 o1
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.code_transfer_index), 0);
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.code_transfer_data[0]), 0x4C000000); // mov o0, v0  color
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.code_transfer_data[1]), 0x4C201000); // mov o1, v1  pos 
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.code_transfer_data[2]), 0x88000000); // end
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.code_transfer_end), 1);

    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.operand_descriptors_index), 0);
    // mask xyzw, selector xyzw
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.operand_descriptors_data[0]), 0x0000036F);
    // lower 16 bits, entrypoint starts at instruction 0
    queue.addCommand(.fromRegister(internal, &internal.vertex_shader.entrypoint), 0x7fff0000);
    
    // drawing triangle strips
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.config), (@as(u32, 1) << 8));
    // drawing triangle strips + inputting vtx data
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.config_2), (@as(u32, 1) << 8) | 1);
    // immediate mode start
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.restart_primitive), 1);
    // start drawing
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.start_draw_function), 0);
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.fixed_attribute_index), 0xF);
    inline for (0..8) |i| {
        queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.fixed_attribute_data[0]), vtx_buf[i*3+2]);
        queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.fixed_attribute_data[1]), vtx_buf[i*3+1]);
        queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.fixed_attribute_data[2]), vtx_buf[i*3]);
    }
    // in config again
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.start_draw_function), 1);
    // Clear post vertex cache
    queue.addCommand(.fromRegister(internal, &internal.geometry_pipeline.post_vertex_cache_num), 1);
    // Flush changes to vram
    queue.addCommand(.fromRegister(internal, &internal.framebuffer.render_buffer_flush), 1);

    // Drawing to 
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
const command = gpu.command;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
