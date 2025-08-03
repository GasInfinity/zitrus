// NOTE: mango is not finished. It is designed with a vulkan-like api
// TODO: Document everything when finished

pub fn main() !void {
    var srv = try ServiceManager.init();
    defer srv.deinit();

    var apt = try Applet.init(srv);
    defer apt.deinit();

    var app = try Applet.Application.init(apt, srv);
    defer app.deinit(apt, srv);

    var hid = try Hid.init(srv);
    defer hid.deinit();

    var gsp = try GspGpu.init(srv);
    defer gsp.deinit();

    // TODO: Keep framebuffer for software rendering, use mango for everything else.
    var framebuffer = try Framebuffer.init(.{
        .double_buffer = .init(.{
            .top = false,
            .bottom = false,
        }),
        .color_format = .init(.{
            .top = .bgr888,
            .bottom = .bgr888,
        }),
        .phys_linear_allocator = horizon.heap.linear_page_allocator,
    });
    defer framebuffer.deinit();

    const top = framebuffer.currentFramebuffer(.top);
    const bottom = framebuffer.currentFramebuffer(.bottom);
    @memset(top, 0xFF);
    @memset(bottom, 0xFF);

    // TODO: How do we approach allocating memory
    const bot_renderbuf = @as([*]align(8) u8, @ptrFromInt(horizon.memory.vram_a_begin))[0 .. 320 * 240 * 4];
    // defer horizon.heap.linear_page_allocator.free(bot_renderbuf);

    const internal = &horizon.memory.gpu_registers.internal;
    const raw_command_queue = try horizon.heap.linear_page_allocator.alignedAlloc(u32, 8, 4096);
    defer horizon.heap.linear_page_allocator.free(raw_command_queue);

    // Learn the hard way that memory fills only work with vram.
    // 3dbrew GSP Shared memory: "Addresses should be aligned to 8 bytes and must be in linear, QTM or VRAM memory"
    // 3dbrew MemoryFill registers: "The addresses must be part of VRAM."
    // TODO: use mango.
    try gsp.submitMemoryFill(.{ .init(bot_renderbuf, .fill32(0xCCAACCFF)), null }, .none);
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.get(.psc0) > 0) {
            break;
        }
    }

    // Initial display transfer (only used for debugging purposes). You cannot draw directly to the framebuffer as you must do a tiled->linear transformation.
    // TODO: use mango.
    try gsp.submitDisplayTransfer(bot_renderbuf.ptr, bottom.ptr, .abgr8888, .{ .x = 240, .y = 320 }, .bgr888, .{ .x = 240, .y = 320 }, .none, .none);
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.get(.ppf) > 0) {
            break;
        }
    }

    const Vertex = extern struct {
        color: [3]u8,
        pos: [4]i8,
    };

    // XXX: Little hack for allocating mango.DeviceMemory. This must NEVER be done.
    const vtx_buffer_memory_va = try horizon.heap.linear_page_allocator.alignedAlloc(Vertex, 16, 4);
    defer horizon.heap.linear_page_allocator.free(vtx_buffer_memory_va);

    vtx_buffer_memory_va[0] = .{ .pos = .{ -1, -1, 0, 1 }, .color = .{ 0, 0, 0 } };
    vtx_buffer_memory_va[1] = .{ .pos = .{ 1, -1, 0, 1 }, .color = .{ 1, 1, 0 } };
    vtx_buffer_memory_va[2] = .{ .pos = .{ -1, 1, 0, 1 }, .color = .{ 0, 1, 1 } };
    vtx_buffer_memory_va[3] = .{ .pos = .{ 1, 1, 0, 1 }, .color = .{ 0, 1, 0 } };

    try gsp.sendFlushDataCache(std.mem.sliceAsBytes(vtx_buffer_memory_va));

    const index_buffer_memory_va = try horizon.heap.linear_page_allocator.alloc(u8, 4);
    defer horizon.heap.linear_page_allocator.free(index_buffer_memory_va);
    index_buffer_memory_va[0..4].* = .{ 0, 1, 2, 3 };

    try gsp.sendFlushDataCache(std.mem.sliceAsBytes(index_buffer_memory_va));

    var index_buffer_memory: mango.DeviceMemory = .{
        .virtual = index_buffer_memory_va.ptr,
        .physical = horizon.memory.toPhysical(@intFromPtr(index_buffer_memory_va.ptr)),
        .size = 4,
    };

    var vtx_buffer_memory: mango.DeviceMemory = .{
        .virtual = vtx_buffer_memory_va.ptr,
        .physical = horizon.memory.toPhysical(@intFromPtr(vtx_buffer_memory_va.ptr)),
        .size = @sizeOf(Vertex) * 4,
    };

    var device: mango.Device = .{};
    const index_buffer = try device.createBuffer(.{
        .size = 0x4,
        .usage = .{
            .index_buffer = true,
        },
    }, horizon.heap.linear_page_allocator);
    defer device.destroyBuffer(index_buffer, horizon.heap.linear_page_allocator);
    try device.bindBufferMemory(index_buffer, &index_buffer_memory, 0);

    const vtx_buffer = try device.createBuffer(.{
        .size = @sizeOf(Vertex) * 4,
        .usage = .{
            .vertex_buffer = true,
        },
    }, horizon.heap.linear_page_allocator);
    defer device.destroyBuffer(vtx_buffer, horizon.heap.linear_page_allocator);
    try device.bindBufferMemory(vtx_buffer, &vtx_buffer_memory, 0);

    var cmdbuf: mango.CommandBuffer = .{
        .queue = .initBuffer(raw_command_queue),
    };

    const queue: *cmd3d.Queue = &cmdbuf.queue;
    // Initially adapted from https://problemkaputt.de/gbatek.htm#3dsgputriangledrawingsamplecode but writing through commandlists instead of doing it directly and some more fixes (texenv0, lighting disable)
    // TODO: This is VERY low level. Needs an API
    
    // NOTE: Pipelines are really good as they could cache commands efficiently and binding them would be only one memcpy
    // however, everything will be as dynamic as possible
    const pipeline_create: mango.Pipeline.CreateGraphics = .{
        .rendering_info = .{
            .color_attachment_format = .a8b8g8r8_unorm,
            .depth_stencil_attachment_format = .undefined,
        },
        .vertex_input_state = &.init(
            &.{
                .{
                    .stride = 7,
                },
            },
            &.{
                .{
                    .location = .v0,
                    .binding = .@"0",
                    .format = .r8g8b8_uscaled,
                    .offset = 0,
                },
                .{
                    .location = .v1,
                    .binding = .@"0",
                    .format = .r8g8b8a8_sscaled,
                    .offset = 3,
                },
            },
            &.{}
        ),
        .input_assembly_state = &.{
            // NOTE: Ignored as its dynamic state
            .topology = undefined,
        },
        .viewport_state = &.{
            .scissor = &.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 320 } }),
            .viewport = &.{
                .rect = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = .{ .width = 240, .height = 320 },
                },
                .min_depth = 0.0,
                .max_depth = 1.0,
            },
        },
        .rasterization_state = &.{
            .front_face = .ccw,
            .cull_mode = .none,

            .depth_mode = .z_buffer,
            .depth_bias_enable = false,
            .depth_bias_constant = 0.0,
        },
        .alpha_depth_stencil_state = &.{
            .alpha_test_enable = false,
            .alpha_test_compare_op = .never,
            .alpha_test_reference = 0,

            .depth_test_enable = false,
            .depth_write_enable = false,
            .depth_compare_op = .gt,

            .stencil_test_enable = false,
            .back_front = std.mem.zeroes(mango.Pipeline.CreateGraphics.AlphaDepthStencilState.StencilOperationState),
        },
        .lighting_state = &.{}, 
        .texture_combiner_state = &.init(&.{
            .{
                .color_src = @splat(.primary_color),
                .alpha_src = @splat(.primary_color),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .replace,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0),
            }
        }, &.{}),
        .color_blend_state = &.{
            .logic_op_enable = false,
            .logic_op = .clear,
            
            .attachment = .{
                .blend_enable = false,
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,

                .color_write_mask = .rgba,
                .color_write_enable = true, 
            },
            .blend_constants = .{ 0, 0, 0, 0 },
        },
        .dynamic_state = .{
            .primitive_topology = true,
        },
    };

    // TODO: create pipelines and cache their static state for command buffers
    pipeline_create.writeStaticState(queue);

    // TODO: What to do with early depth?
    queue.add(internal, &internal.rasterizer.early_depth_test_enable_1, .init(false));
    queue.add(internal, &internal.framebuffer.early_depth_test_enable_2, .init(false));
    
    // TODO: Lighting in pipelines
    queue.add(internal, &internal.texturing.lighting_enable, .init(false));
    queue.add(internal, &internal.fragment_lighting.disable, .init(true));

    // TODO: specialized shader format. shbins are not that great? they need to be parsed, we're homebrew, we don't have to abide by the rules.
    // TODO: Shaders in pipeline
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
    queue.add(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_1, .init(2 - 1));
    queue.add(internal, &internal.geometry_pipeline.vertex_shader_output_map_total_2, .init(2 - 1));

    // don't use geometry shader + 2 input registers
    queue.add(internal, &internal.geometry_pipeline.enable_geometry_shader_configuration, .init(false));
    queue.add(internal, &internal.vertex_shader.input_buffer_config, .{
        .num_input_attributes = (2 - 1),
        .enabled_for_vertex_0 = true,
        .enabled_for_vertex_1 = true,
    });
    queue.addMasked(internal, &internal.geometry_pipeline.primitive_config, .{
        .total_vertex_outputs = (2 - 1),
        .topology = .triangle_list,
    }, 0b0001);

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
    queue.add(internal, &internal.vertex_shader.code_transfer_end, .init(.trigger));

    queue.add(internal, &internal.vertex_shader.operand_descriptors_index, .initIndex(0));
    queue.add(internal, &internal.vertex_shader.operand_descriptors_data[0], .{});
    queue.add(internal, &internal.vertex_shader.entrypoint, .initEntry(0));
    
    // We'll render to the bottom screen, thats why 320x240 (physically they are 240x320)
    // queue.add(internal, &internal.rasterizer.scissor_config, .{ .mode = .disable });
    // Basically replace the color: Ofb = 1*src + 0*dst
    // NOTE: mango doesn't expect ANY gpu state in a command buffer (its only local to the cmdbuf), previous state is undefined for us, however here we're writing to the queue directly :p
    queue.add(internal, &internal.geometry_pipeline.start_draw_function, .drawing);
    // TODO: Shaders in pipeline

    // draw a colored quad with vertex and index buffers
   
    {
        cmdbuf.begin();
        defer cmdbuf.end();

        cmdbuf.bindIndexBuffer(index_buffer, 0, .u8);
        cmdbuf.bindVertexBuffersSlice(0, &.{vtx_buffer}, &.{0});

        // Redundant, just to show that dynamic state is supported
        cmdbuf.setPrimitiveTopology(.triangle_strip);

        {
            // We'll render to the bottom screen, thats why 320x240 (physically they are 240x320)
            cmdbuf.beginRendering(&.{
                // TODO: As we still dont have resources this must be done.
                .todo_image_view_extents = .{
                    .width = 240,
                    .height = 320,
                },

                // TODO: Image and ImageView
                .color_attachment = horizon.memory.toPhysical(@intFromPtr(bot_renderbuf.ptr)),
                .depth_stencil_attachment = .fromAddress(0),
            });
            defer cmdbuf.endRendering();

            // index_count, first_index, vertex_offset
            cmdbuf.drawIndexed(4, 0, 0);

            // TODO: How do we approach drawing in immediate mode with mango?
            // Its different from attributes as you can input up to 16 registers instead of 12 so maybe it could have its use cases.

            // const as_fixed_attr: [8]F7_16x4 = .{
            //     .pack(.of(1), .of(0), .of(1), .of(1)),
            //     .pack(.of(-1), .of(-1), .of(0), .of(1)),
            //
            //     .pack(.of(1),  .of(1), .of(0), .of(1)),
            //     .pack(.of(1), .of(-1), .of(0), .of(1)),
            //
            //     .pack(.of(0), .of(1), .of(1), .of(1)),
            //     .pack(.of(-1), .of(1), .of(0), .of(1)),
            //
            //     .pack(.of(0), .of(1), .of(0), .of(1)),
            //     .pack(.of(1), .of(1), .of(0), .of(1)),
            // };
            //
            // // start drawing
            // queue.add(internal, &internal.geometry_pipeline.restart_primitive, .init(.trigger));
            // queue.add(internal, &internal.geometry_pipeline.fixed_attribute_index, .immediate_mode);
            // inline for (0..8) |i| {
            //     queue.add(internal, &internal.geometry_pipeline.fixed_attribute_data, as_fixed_attr[i]);
            // }
            // queue.add(internal, &internal.geometry_pipeline.clear_post_vertex_cache, .init(.trigger));
        }

    }
    // XXX: Homebrew apps expect start_draw_function to start in configuration mode. Or you have a dreaded black screen of death x-x
    queue.add(internal, &internal.geometry_pipeline.start_draw_function, .config);
    queue.finalize();

    // TODO: Say goodbye to using the gsp directly, use mango.

    // TODO: This is currently not that great...
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.get(.vblank_top) > 0) {
            break;
        }
    }

    // Flush entire linear memory again just in case before main loop...
    try gsp.sendFlushDataCache(@as([*]u8, @ptrFromInt(horizon.memory.linear_heap_begin))[0..(horizon.memory.linear_heap_end - horizon.memory.linear_heap_begin)]);

    try framebuffer.flushBuffers(&gsp);
    try framebuffer.present(&gsp);

    try gsp.sendSetLcdForceBlack(false);
    defer if (gsp.has_right) gsp.sendSetLcdForceBlack(true) catch {};

    main_loop: while (true) {
        while (try srv.pollNotification()) |notif| switch (notif) {
            .must_terminate => break :main_loop,
            else => {},
        };

        while (try app.pollNotification(apt, srv)) |n| switch (n) {
            .jump_home, .jump_home_by_power => {
                j_h: switch(try app.jumpToHome(apt, srv, &gsp, .none)) {
                    .resumed => {},
                    .jump_home => continue :j_h (try app.jumpToHome(apt, srv, &gsp, .none)),
                    .must_close => break :main_loop,
                }
            },
            .sleeping => {
                while (try app.waitNotification(apt, srv) != .sleep_wakeup) {}
                try gsp.sendSetLcdForceBlack(false);
            },
            .must_close, .must_close_by_shutdown => break :main_loop,
            .jump_home_rejected => {},
            else => {},
        };

        const input = hid.readPadInput();

        if (input.current.start) {
            break :main_loop;
        }

        try gsp.submitProcessCommandList(@alignCast(queue.buffer[0..queue.current_index]), .none, .flush, .none);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.get(.p3d) > 0) {
                break;
            }
        }

        try gsp.submitDisplayTransfer(bot_renderbuf.ptr, bottom.ptr, .abgr8888, .{ .x = 240, .y = 320 }, .bgr888, .{ .x = 240, .y = 320 }, .none, .none);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.get(.ppf) > 0) {
                break;
            }
        }

        try framebuffer.flushBuffers(&gsp);
        try framebuffer.present(&gsp);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.get(.vblank_top) > 0) {
                break;
            }
        }
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
const cmd3d = gpu.cmd3d;
const mango = gpu.mango;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
    std.testing.refAllDeclsRecursive(mango.Pipeline);
}
