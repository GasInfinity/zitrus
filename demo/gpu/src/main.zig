// NOTE: mango is not finished. It is designed with a vulkan-like api
// TODO: Document everything when finished

const simple_vtx = @embedFile("simple.zpsh");

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = horizon.heap.page_allocator;
    };
};

pub const std_options: std.Options = .{
    .page_size_min = horizon.heap.page_size_min,
    .page_size_max = horizon.heap.page_size_max,
    .logFn = log,
    .log_level = .debug,
};

pub fn log(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const prefix = std.fmt.bufPrint(&buf, "[{s}] ({s}): ", .{@tagName(message_level), @tagName(scope)}) catch {
        horizon.outputDebugString("fatal: logged message prefix does not fit into the buffer. message skipped!");
        return;
    };

    const message = std.fmt.bufPrint(buf[prefix.len..], format, args) catch buf[prefix.len..];
    horizon.outputDebugString(buf[0..(prefix.len + message.len)]);
}

pub fn main() !void {
    // var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    // defer _ = gpa_state.deinit();

    const gpa = horizon.heap.page_allocator;

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

    const raw_command_queue = try horizon.heap.linear_page_allocator.alignedAlloc(u32, 8, 4096);
    defer horizon.heap.linear_page_allocator.free(raw_command_queue);

    const Vertex = extern struct {
        color: [3]u8,
        pos: [4]i8,
    };

    var device: mango.Device = .initTodo(&gsp);

    const bottom_presentable_image_memory = try device.allocateMemory(&.{
        .memory_type = 0,
        .allocation_size = 320 * 240 * 3 * 2,
    }, gpa);
    defer device.freeMemory(bottom_presentable_image_memory, gpa);

    const top_presentable_image_memory = try device.allocateMemory(&.{
        .memory_type = 1,
        .allocation_size = 400 * 240 * 3,
    }, gpa);
    defer device.freeMemory(top_presentable_image_memory, gpa);

    const top_presentable_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .linear,
        .usage = .{
            .transfer_dst = true,
        },
        .extent = .{
            .width = 240,
            .height = 400,
        },
        .format = .b8g8r8_unorm,
        // FIXME: These values are currently ignored
        .mip_levels = 1,
        .array_layers = 1,  
    }, gpa);
    defer device.destroyImage(top_presentable_image, gpa);
    try device.bindImageMemory(top_presentable_image, top_presentable_image_memory, 0);

    // XXX: As we block, we dont need synchronization but it'll be a must!
    // NOTE: See we're using memory_type 1? Its a MUST for clearing images, they must be in DEVICE_LOCAL memory.
    try device.clearColorImage(top_presentable_image, &@splat(255));

    const bottom_presentable_images: [2]mango.Image = .{
        try device.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .linear,
            .usage = .{
                .transfer_dst = true,
            },
            .extent = .{
                .width = 240,
                .height = 320,
            },
            .format = .b8g8r8_unorm,
            // FIXME: These values are currently ignored
            .mip_levels = 1,
            .array_layers = 1,
        }, gpa),
        try device.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .linear,
            .usage = .{
                .transfer_dst = true,
            },
            .extent = .{
                .width = 240,
                .height = 320,
            },
            .format = .b8g8r8_unorm,
            // FIXME: These values are currently ignored
            .mip_levels = 1,
            .array_layers = 1,
        }, gpa),
    };

    defer for (bottom_presentable_images) |image| {
        device.destroyImage(image, gpa);
    };

    for (0..2) |i| {
        try device.bindImageMemory(bottom_presentable_images[i], bottom_presentable_image_memory, i * (320 * 240 * 3));
    }

    const vtx_buffer_memory = try device.allocateMemory(&.{
        .memory_type = 0,
        .allocation_size = @sizeOf(Vertex) * 4,
    }, gpa);
    defer device.freeMemory(vtx_buffer_memory, gpa);

    const index_buffer_memory = try device.allocateMemory(&.{
        .memory_type = 0,
        .allocation_size = 4,
    }, gpa);
    defer device.freeMemory(index_buffer_memory, gpa);

    {
        // TODO: DeviceSize and whole_size in it
        const mapped_vtx = try device.mapMemory(vtx_buffer_memory, 0, std.math.maxInt(u32)); 
        defer device.unmapMemory(vtx_buffer_memory);

        // TODO: return slices for better safety
        const mapped_idx = try device.mapMemory(index_buffer_memory, 0, std.math.maxInt(u32));
        defer device.unmapMemory(index_buffer_memory);

        const vtx_data: *[4]Vertex = @ptrCast(mapped_vtx);
        const idx_data: *[4]u8 = @ptrCast(mapped_idx);

        vtx_data.* = .{
            .{ .pos = .{ -1, -1, 0, 1 }, .color = .{ 0, 0, 0 } },
            .{ .pos = .{ 1, -1, 0, 1 }, .color = .{ 1, 1, 0 } },
            .{ .pos = .{ -1, 1, 0, 1 }, .color = .{ 0, 1, 1 } },
            .{ .pos = .{ 1, 1, 0, 1 }, .color = .{ 0, 1, 0 } },
        };
        idx_data.* = .{ 0, 1, 2, 3 };

        try device.flushMappedMemoryRanges(&.{
            .{
                .memory = vtx_buffer_memory,
                .offset = 0,
                .size = @sizeOf(Vertex) * 4,
            },
            .{
                .memory = index_buffer_memory,
                .offset = 0,
                .size = 4,
            }
        });
    }

    const color_attachment_image_memory = try device.allocateMemory(&.{
        .memory_type = 1,
        .allocation_size = 320 * 240 * 4,
    }, gpa);
    defer device.freeMemory(color_attachment_image_memory, gpa);

    const index_buffer = try device.createBuffer(.{
        .size = 0x4,
        .usage = .{
            .index_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(index_buffer, gpa);
    try device.bindBufferMemory(index_buffer, index_buffer_memory, 0);

    const vtx_buffer = try device.createBuffer(.{
        .size = @sizeOf(Vertex) * 4,
        .usage = .{
            .vertex_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(vtx_buffer, gpa);
    try device.bindBufferMemory(vtx_buffer, vtx_buffer_memory, 0);

    const color_attachment_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_src = true,
            .color_attachment = true,
        },
        .extent = .{
            .width = 240,
            .height = 320,
        },
        .format = .a8b8g8r8_unorm,
        // FIXME: These values are currently ignored
        .mip_levels = 1,
        .array_layers = 1,
    }, gpa);
    defer device.destroyImage(color_attachment_image, gpa);
    try device.bindImageMemory(color_attachment_image, color_attachment_image_memory, 0);

    try device.clearColorImage(color_attachment_image, &@splat(255));

    const color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = color_attachment_image,
    }, gpa);
    defer device.destroyImageView(color_attachment_image_view, gpa);

    var cmdbuf: mango.CommandBuffer = .{
        .queue = .initBuffer(raw_command_queue),
    };

    const simple_pipeline = try device.createGraphicsPipeline(.{
        .rendering_info = &.{
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
        .vertex_shader_state = &.init(simple_vtx, "main"),
        .geometry_shader_state = null,
        .input_assembly_state = &.{
            .topology = .triangle_strip,
        },
        .viewport_state = null,
        .rasterization_state = &.{
            .front_face = .ccw,
            .cull_mode = .none,

            .depth_mode = .z_buffer,
            .depth_bias_constant = 0.0,
        },
        .alpha_depth_stencil_state = &.{
            .alpha_test_enable = false,
            .alpha_test_compare_op = .never,
            .alpha_test_reference = 0,

            // (!) Disabling depth tests also disables depth writes like in every other graphics api
            .depth_test_enable = false,
            .depth_write_enable = false,
            .depth_compare_op = .gt,

            .stencil_test_enable = false,
            .back_front = std.mem.zeroes(mango.GraphicsPipelineCreateInfo.AlphaDepthStencilState.StencilOperationState),
        },
        .texture_sampling_state = null,
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
                .blend_equation = .{
                    .src_color_factor = .one,
                    .dst_color_factor = .zero,
                    .color_op = .add,
                    .src_alpha_factor = .one,
                    .dst_alpha_factor = .zero,
                    .alpha_op = .add,
                },
                .color_write_mask = .rgba,
            },
            .blend_constants = .{ 0, 0, 0, 0 },
        },
        .dynamic_state = .{
            .viewport = true,
            .scissor = true,

            .texture_combiner = true,
        },
    }, gpa);
    defer device.destroyPipeline(simple_pipeline, gpa);

    {
        cmdbuf.begin();
        defer cmdbuf.end();

        cmdbuf.bindIndexBuffer(index_buffer, 0, .u8);
        cmdbuf.bindVertexBuffersSlice(0, &.{vtx_buffer}, &.{0});
        cmdbuf.bindPipeline(.graphics, simple_pipeline);

        // Disabling depth test in mango ALSO disables depth writes.
        cmdbuf.setViewport(&.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = 240, .height = 320 },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmdbuf.setScissor(&.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 320 } }));

        // TODO: Compiler texture combiners in the pipeline, remove this dynamic state from this example.
        cmdbuf.setTextureCombiners(1, &.{
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
        }, 0, &.{});

        //  TODO: Texturing
        // cmdbuf.setTextureEnable(&.{ true, false, false, false });

        {
            // We'll render to the bottom screen, images are 240x320 physically.
            cmdbuf.beginRendering(&.{
                .color_attachment = color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmdbuf.endRendering();

            cmdbuf.drawIndexed(4, 0, 0);
        }
    }

    // TODO: Say goodbye to using the gsp directly, use mango.
    while (true) {
        const interrupts = try gsp.waitInterrupts();

        if (interrupts.get(.vblank_top) > 0) {
            break;
        }
    }

    // Flush entire linear memory again just in case before main loop...
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

        // XXX: This blocks currently as we don't have synchronization primitives.
        device.submit(&.init(&.{ &cmdbuf }));

        // XXX: Technically VRAM is not host visible, this is an implementation detail and with proper debug checks WILL panic :D
        try device.blitImage(color_attachment_image, bottom_presentable_images[0]);

        // try framebuffer.flushBuffers(&gsp);
        // try framebuffer.present(&gsp);
        while (true) {
            const interrupts = try gsp.waitInterrupts();

            if (interrupts.get(.vblank_top) > 0) {
                break;
            }
        }

        {
            const mapped_bottom_presentable = try device.mapMemory(bottom_presentable_image_memory, 0, 320 * 240 * 3);
            defer device.unmapMemory(bottom_presentable_image_memory);

            const mapped_top_presentable = try device.mapMemory(top_presentable_image_memory, 0, 400 * 240 * 3);
            defer device.unmapMemory(top_presentable_image_memory);

            _ = try gsp.presentFramebuffer(.top, .{
                .active = @enumFromInt(0),
                .color_format = .bgr888,
                .left_vaddr = mapped_top_presentable,
                .right_vaddr = mapped_top_presentable,
                .stride = pica.ColorFormat.bgr888.bytesPerPixel() * pica.Screen.bottom.width(),
                .dma_size = .@"128",
            });
            _ = try gsp.presentFramebuffer(.bottom, .{
                .active = @enumFromInt(0),
                .color_format = .bgr888,
                .left_vaddr = mapped_bottom_presentable,
                .right_vaddr = mapped_bottom_presentable,
                .stride = pica.ColorFormat.bgr888.bytesPerPixel() * pica.Screen.bottom.width(),
                .dma_size = .@"128",
            });
        }
    }
}

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;
const Framebuffer = zitrus.pica.Framebuffer;

const mango = zitrus.mango;

const pica = zitrus.pica;
const F7_16x4 = pica.F7_16x4;
const cmd3d = pica.cmd3d;

pub const panic = zitrus.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
}
