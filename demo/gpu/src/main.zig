// NOTE: mango is not finished. It is designed with a vulkan-like api,
// you should be looking at the `mango` directory. This is not friendly for new users.

// TODO: Document everything when finished

// NOTE: as you can see, the shader address must be aligned to 32-bits
const simple_vtx_storage align(@sizeOf(u32)) = @embedFile("simple.zpsh").*;
const simple_vtx = &simple_vtx_storage;

const test_bgr = @embedFile("test.bgr");

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
    const prefix = std.fmt.bufPrint(&buf, "[{s}] ({s}): ", .{ @tagName(message_level), @tagName(scope) }) catch {
        horizon.outputDebugString("fatal: logged message prefix does not fit into the buffer. message skipped!");
        return;
    };

    const message = std.fmt.bufPrint(buf[prefix.len..], format, args) catch buf[prefix.len..];
    horizon.outputDebugString(buf[0..(prefix.len + message.len)]);
}

pub const Scene = struct {
    const Vertex = extern struct {
        pos: [3]f32,
        norm: [3]f32,
        uv: [2]f32,
    };

    const cube_faces = 6;
    const face_vertices = 4;
    const face_indices = 6;

    const cube_indices: [cube_faces * face_indices]u8 = blk: {
        var indices: [cube_faces * face_indices]u8 = undefined;
        var i = 0;

        for (0..6) |face| {
            indices[i + 0] = face * 4 + 0;
            indices[i + 1] = face * 4 + 1;
            indices[i + 2] = face * 4 + 2;
            indices[i + 3] = face * 4 + 2;
            indices[i + 4] = face * 4 + 3;
            indices[i + 5] = face * 4 + 0;
            i += 6;
        }

        break :blk indices;
    };

    const cube_vertices: [cube_faces * face_vertices]Vertex = .{
        // front face (z = +1)
        .{ .pos = .{ -1, -1, 1 }, .norm = .{ 0, 0, 1 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ 1, -1, 1 }, .norm = .{ 0, 0, 1 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ 1, 1, 1 }, .norm = .{ 0, 0, 1 }, .uv = .{ 1, 1 } },
        .{ .pos = .{ -1, 1, 1 }, .norm = .{ 0, 0, 1 }, .uv = .{ 0, 1 } },

        // back face (z = -1)
        .{ .pos = .{ -1, -1, -1 }, .norm = .{ 0, 0, -1 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ -1, 1, -1 }, .norm = .{ 0, 0, -1 }, .uv = .{ 1, 1 } },
        .{ .pos = .{ 1, 1, -1 }, .norm = .{ 0, 0, -1 }, .uv = .{ 0, 1 } },
        .{ .pos = .{ 1, -1, -1 }, .norm = .{ 0, 0, -1 }, .uv = .{ 0, 0 } },

        // left face (x = -1)
        .{ .pos = .{ -1, -1, -1 }, .norm = .{ -1, 0, 0 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ -1, -1, 1 }, .norm = .{ -1, 0, 0 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ -1, 1, 1 }, .norm = .{ -1, 0, 0 }, .uv = .{ 1, 1 } },
        .{ .pos = .{ -1, 1, -1 }, .norm = .{ -1, 0, 0 }, .uv = .{ 0, 1 } },

        // right face (x = +1)
        .{ .pos = .{ 1, -1, -1 }, .norm = .{ 1, 0, 0 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ 1, 1, -1 }, .norm = .{ 1, 0, 0 }, .uv = .{ 1, 1 } },
        .{ .pos = .{ 1, 1, 1 }, .norm = .{ 1, 0, 0 }, .uv = .{ 0, 1 } },
        .{ .pos = .{ 1, -1, 1 }, .norm = .{ 1, 0, 0 }, .uv = .{ 0, 0 } },

        // top face (y = +1)
        .{ .pos = .{ -1, 1, -1 }, .norm = .{ 0, 1, 0 }, .uv = .{ 0, 1 } },
        .{ .pos = .{ -1, 1, 1 }, .norm = .{ 0, 1, 0 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ 1, 1, 1 }, .norm = .{ 0, 1, 0 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ 1, 1, -1 }, .norm = .{ 0, 1, 0 }, .uv = .{ 1, 1 } },

        // bottom face (y = -1)
        .{ .pos = .{ -1, -1, -1 }, .norm = .{ 0, -1, 0 }, .uv = .{ 1, 1 } },
        .{ .pos = .{ 1, -1, -1 }, .norm = .{ 0, -1, 0 }, .uv = .{ 0, 1 } },
        .{ .pos = .{ 1, -1, 1 }, .norm = .{ 0, -1, 0 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ -1, -1, 1 }, .norm = .{ 0, -1, 0 }, .uv = .{ 1, 0 } },
    };

    semaphore: mango.Semaphore,
    current_timeline: u64,

    pipeline: mango.Pipeline,

    top_renderbuffer: Renderbuffer,
    cube_mesh: Mesh,

    command_pool: mango.CommandPool,
    cmd: mango.CommandBuffer,

    zero_test_image: SingleImage,
    simple_sampler: mango.Sampler,
    time: f32 = 0.0,

    pub fn init(device: mango.Device, gpa: std.mem.Allocator) !Scene {
        const sema = try device.createSemaphore(.{
            .initial_value = 0,
        }, gpa);
        errdefer device.destroySemaphore(sema, gpa);

        const pipeline = try device.createGraphicsPipeline(.{
            .rendering_info = &.{
                .color_attachment_format = .a8b8g8r8_unorm,
                .depth_stencil_attachment_format = .d24_unorm,
            },
            .vertex_input_state = &.init(&.{
                .{
                    .stride = @sizeOf(Vertex),
                },
            }, &.{
                .{
                    .location = .v0,
                    .binding = .@"0",
                    .format = .r32g32b32_sfloat,
                    .offset = @offsetOf(Vertex, "pos"),
                },
                .{
                    .location = .v1,
                    .binding = .@"0",
                    .format = .r32g32b32_sfloat,
                    .offset = @offsetOf(Vertex, "norm"),
                },
                .{
                    .location = .v2,
                    .binding = .@"0",
                    .format = .r32g32_sfloat,
                    .offset = @offsetOf(Vertex, "uv"),
                },
            }, &.{}),
            .vertex_shader_state = &.init(simple_vtx, "main"),
            .geometry_shader_state = null,
            .input_assembly_state = &.{
                .topology = .triangle_list,
            },
            .viewport_state = null,
            .rasterization_state = &.{
                .front_face = .ccw,

                // NOTE: This is done in purpose to show that depth tests WORK!
                .cull_mode = .none,

                .depth_mode = .z_buffer,
                .depth_bias_constant = 0.0,
            },
            .alpha_depth_stencil_state = &.{
                .alpha_test_enable = false,
                .alpha_test_compare_op = .never,
                .alpha_test_reference = 0,

                // (!) Disabling depth tests also disables depth writes like in every other graphics api
                .depth_test_enable = true,
                .depth_write_enable = true,
                .depth_compare_op = .lt,

                .stencil_test_enable = false,
                .back_front = std.mem.zeroes(mango.GraphicsPipelineCreateInfo.AlphaDepthStencilState.StencilOperationState),
            },
            .texture_sampling_state = &.{
                .texture_enable = .{ true, false, false, false },

                .texture_2_coordinates = .@"2",
                .texture_3_coordinates = .@"2",
            },
            .lighting_state = &.{
                .enable = true,
            },
            .texture_combiner_state = &.init(&.{ .{
                .color_src = .{ .fragment_primary_color, .fragment_secondary_color, .previous },
                .alpha_src = @splat(.primary_color),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .add,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0),
            }, .{
                .color_src = .{ .previous, .texture_0, .previous },
                .alpha_src = @splat(.primary_color),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .modulate,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0),
            } }, &.{.previous}),
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
            },
        }, gpa);
        errdefer device.destroyPipeline(pipeline, gpa);

        const top_renderbuffer: Renderbuffer = try .init(device, gpa, 240, 400, .a8b8g8r8_unorm, .d24_unorm);
        errdefer top_renderbuffer.deinit(device, gpa);

        const cube_mesh: Mesh = try .init(device, gpa, .u8, &cube_indices, std.mem.sliceAsBytes(&cube_vertices));
        errdefer cube_mesh.deinit(device, gpa);

        const pool = try device.createCommandPool(.{}, gpa);
        errdefer device.destroyCommandPool(pool, gpa);

        var cmd: [1]mango.CommandBuffer = undefined;
        try device.allocateCommandBuffers(.{
            .pool = pool,
            .command_buffer_count = 1,
        }, &cmd);
        errdefer device.freeCommandBuffers(pool, &cmd);

        const zero_test_image: SingleImage = try .initLinear(device, gpa, 64, 64, .b8g8r8_unorm, test_bgr, sema, 0);
        errdefer zero_test_image.deinit(device, gpa);

        const simple_sampler = try device.createSampler(.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mip_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .lod_bias = 0.0,
            .min_lod = 0,
            .max_lod = 7,
            .border_color = @splat(0),
        }, gpa);
        defer device.destroySampler(simple_sampler, gpa);

        return .{
            .semaphore = sema,
            .current_timeline = 1,

            .pipeline = pipeline,

            .top_renderbuffer = top_renderbuffer,
            .cube_mesh = cube_mesh,

            .command_pool = pool,
            .cmd = cmd[0],

            .zero_test_image = zero_test_image,
            .simple_sampler = simple_sampler,
        };
    }

    pub fn deinit(scene: *Scene, device: mango.Device, gpa: std.mem.Allocator) void {
        device.destroySampler(scene.simple_sampler, gpa);
        scene.zero_test_image.deinit(device, gpa);
        device.freeCommandBuffers(scene.command_pool, @ptrCast(&scene.cmd));
        device.destroyCommandPool(scene.command_pool, gpa);
        scene.cube_mesh.deinit(device, gpa);
        scene.top_renderbuffer.deinit(device, gpa);
        device.destroyPipeline(scene.pipeline, gpa);
        device.destroySemaphore(scene.semaphore, gpa);
    }

    pub fn update(scene: *Scene) !void {
        scene.time += 1.0 / 60.0;
    }

    pub fn render(scene: *Scene) !void {
        const cmd = scene.cmd;

        try cmd.begin();

        scene.cube_mesh.bind(cmd);
        cmd.bindPipeline(.graphics, scene.pipeline);
        cmd.bindCombinedImageSamplers(0, &.{.{
            .image = scene.zero_test_image.view,
            .sampler = scene.simple_sampler,
        }});

        // Render to the top screen
        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = 240, .height = 400 },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 400 } }));

        {
            cmd.beginRendering(.{
                .color_attachment = scene.top_renderbuffer.color.view,
                .depth_stencil_attachment = scene.top_renderbuffer.depth.view,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            const sin_time = @sin(scene.time / 4);

            const model_rotation_axis, _ = zmath.vec.normalize(3, f32, .{ 1, 1, 1 });
            const model_rotation = zmath.quat.axisAngleV(f32, model_rotation_axis, std.math.pi * scene.time / 2.0);

            const model_matrix = zmath.mat.scaleRotateTranslateV(.{ 1, 1, 1 }, model_rotation, .{ 0, 0, -2.5 - (@abs(sin_time)) * 4 });

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(.right, std.math.degreesToRadians(90.0), 240.0 / 400.0, 0.8, 100));
            cmd.bindFloatUniforms(.vertex, 4, &model_matrix);

            scene.cube_mesh.draw(cmd);
        }

        try cmd.end();
    }

    pub fn submitPresent(scene: *Scene, device: mango.Device, top_swap: DoubleBufferedSwapchain, top_idx: u8, bottom_swap: DoubleBufferedSwapchain, bottom_idx: u8) !void {
        const transfer_queue = device.getQueue(.transfer);
        const fill_queue = device.getQueue(.fill);
        const submit_queue = device.getQueue(.submit);
        const present_queue = device.getQueue(.present);

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(scene.semaphore, scene.current_timeline),
            .image = bottom_swap.images[bottom_idx],
            .color = @splat(0x22),
            .subresource_range = .full,
            .signal_semaphore = &.init(scene.semaphore, scene.current_timeline + 1),
        });
        scene.current_timeline += 1;

        // We're not rendering to the bottom screen, we can present now.
        try bottom_swap.present(present_queue, bottom_idx, &.init(scene.semaphore, scene.current_timeline));

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(scene.semaphore, scene.current_timeline),
            .image = scene.top_renderbuffer.color.image,
            .color = @splat(0x11),
            .subresource_range = .full,
            .signal_semaphore = &.init(scene.semaphore, scene.current_timeline + 1),
        });
        scene.current_timeline += 1;

        try fill_queue.clearDepthStencilImage(.{
            .wait_semaphore = &.init(scene.semaphore, scene.current_timeline),
            .image = scene.top_renderbuffer.depth.image,
            .depth = 1.0,
            .stencil = 0x00,
            // .subresource_range = .full,
            .signal_semaphore = &.init(scene.semaphore, scene.current_timeline + 1),
        });
        scene.current_timeline += 1;

        try submit_queue.submit(.{
            .wait_semaphore = &.init(scene.semaphore, scene.current_timeline),
            .command_buffer = scene.cmd,
            .signal_semaphore = &.init(scene.semaphore, scene.current_timeline + 1),
        });
        scene.current_timeline += 1;

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(scene.semaphore, scene.current_timeline),
            .src_image = scene.top_renderbuffer.color.image,
            .dst_image = top_swap.images[top_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(scene.semaphore, scene.current_timeline + 1),
        });
        scene.current_timeline += 1;

        try top_swap.present(present_queue, top_idx, &.init(scene.semaphore, scene.current_timeline));

        // We must wait as we're using a single image to render.
        try device.waitSemaphore(.{
            .semaphore = scene.semaphore,
            .value = scene.current_timeline,
        }, -1);
    }
};

pub const DoubleBufferedSwapchain = struct {
    swapchain_memory: mango.DeviceMemory,
    swapchain: mango.Swapchain,
    images: [2]mango.Image,

    pub fn initBgr888(device: mango.Device, surface: mango.Surface, gpa: std.mem.Allocator) !DoubleBufferedSwapchain {
        const w: u32, const h: u32 = switch (surface) {
            .top_240x400 => .{ 240, 400 },
            .top_240x800 => .{ 240, 800 },
            .bottom_240x320 => .{ 240, 320 },
            else => unreachable,
        };

        const memory = try device.allocateMemory(.{
            .memory_type = .vram_a,
            .allocation_size = .size(w * h * 3 * 2),
        }, gpa);
        errdefer device.freeMemory(memory, gpa);

        const swapchain = try device.createSwapchain(.{
            .surface = surface,
            .present_mode = .fifo,
            .image_format = .b8g8r8_unorm,
            .image_array_layers = .@"1",
            .image_count = 2,
            .image_usage = .{
                .transfer_dst = true,
            },
            .image_memory_info = &.{
                .{ .memory = memory, .memory_offset = .size(0) },
                .{ .memory = memory, .memory_offset = .size(w * h * 3) },
            },
        }, gpa);

        var images: [2]mango.Image = undefined;
        _ = device.getSwapchainImages(swapchain, &images);

        return .{
            .swapchain_memory = memory,
            .swapchain = swapchain,
            .images = images,
        };
    }

    pub fn deinit(chain: DoubleBufferedSwapchain, device: mango.Device, gpa: std.mem.Allocator) void {
        device.destroySwapchain(chain.swapchain, gpa);
        device.freeMemory(chain.swapchain_memory, gpa);
    }

    pub fn acquireNext(chain: DoubleBufferedSwapchain, device: mango.Device) !u8 {
        return device.acquireNextImage(chain.swapchain, -1);
    }

    pub fn present(chain: DoubleBufferedSwapchain, present_queue: mango.Queue, index: u8, wait: ?*const mango.SemaphoreOperation) !void {
        try present_queue.present(.{
            .wait_semaphore = wait,
            .swapchain = chain.swapchain,
            .image_index = index,
            .flags = .{},
        });
    }
};

pub const Renderbuffer = struct {
    color: SingleImage,
    depth: SingleImage,

    pub fn init(device: mango.Device, gpa: std.mem.Allocator, w: u16, h: u16, color_fmt: mango.Format, depth_fmt: mango.Format) !Renderbuffer {
        return .{
            .color = if (color_fmt != .undefined) try .initUninitialized(device, gpa, w, h, color_fmt, .vram_a, false) else .empty,
            .depth = if (depth_fmt != .undefined) try .initUninitialized(device, gpa, w, h, depth_fmt, .vram_b, false) else .empty,
        };
    }

    pub fn deinit(render: Renderbuffer, device: mango.Device, gpa: std.mem.Allocator) void {
        if (render.color.image != .null) {
            render.color.deinit(device, gpa);
        }

        if (render.depth.image != .null) {
            render.depth.deinit(device, gpa);
        }
    }
};

// NOTE: Not the most efficient implementation, works for demonstration purposes.
pub const SingleImage = struct {
    pub const empty: SingleImage = .{ .memory = .null, .image = .null, .view = .null };

    memory: mango.DeviceMemory,
    image: mango.Image,
    view: mango.ImageView,

    pub fn initUninitialized(device: mango.Device, gpa: std.mem.Allocator, w: u16, h: u16, format: mango.Format, mem_type: mango.KnownMemoryType, sampled: bool) !SingleImage {
        const memory = try device.allocateMemory(.{
            .memory_type = mem_type,
            .allocation_size = .size(format.scale(@as(usize, w) * h)),
        }, gpa);
        errdefer device.freeMemory(memory, gpa);

        const image = try device.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .optimal,
            .usage = .{
                .transfer_dst = true,
                .sampled = sampled,
            },
            .extent = .{
                .width = w,
                .height = h,
            },
            .format = format,
            .mip_levels = .@"1",
            .array_layers = .@"1",
        }, gpa);
        errdefer device.destroyImage(image, gpa);
        try device.bindImageMemory(image, memory, .size(0));

        const view = try device.createImageView(.{
            .type = .@"2d",
            .format = format,
            .image = image,
            .subresource_range = .full,
        }, gpa);
        errdefer device.destroyImageView(view, gpa);

        return .{
            .memory = memory,
            .image = image,
            .view = view,
        };
    }

    // NOTE: Again, this is a demo. Its much better to load ETC images.
    pub fn initLinear(device: mango.Device, gpa: std.mem.Allocator, w: u16, h: u16, format: mango.Format, data: []const u8, semaphore: mango.Semaphore, current: u64) !SingleImage {
        const single: SingleImage = try .initUninitialized(device, gpa, w, h, format, .vram_a, true);
        errdefer single.deinit(device, gpa);

        const memory = try device.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(data.len),
        }, gpa);
        defer device.freeMemory(memory, gpa);

        {
            const mapped = try device.mapMemory(memory, 0, .whole);
            defer device.unmapMemory(memory);

            @memcpy(mapped[0..data.len], data);

            try device.flushMappedMemoryRanges(&.{.{
                .memory = memory,
                .offset = .size(0),
                .size = .whole,
            }});
        }

        const staging = try device.createBuffer(.{
            .usage = .{
                .transfer_src = true,
            },
            .size = .size(data.len),
        }, gpa);
        defer device.destroyBuffer(staging, gpa);
        try device.bindBufferMemory(staging, memory, .size(0));

        try device.getQueue(.transfer).copyBufferToImage(.{
            .wait_semaphore = &.init(semaphore, current),
            .src_buffer = staging,
            .src_offset = .size(0),
            .dst_image = single.image,
            .dst_subresource = .full,
            .signal_semaphore = &.init(semaphore, current + 1),
        });

        return single;
    }

    pub fn deinit(tex: SingleImage, device: mango.Device, gpa: std.mem.Allocator) void {
        device.destroyImageView(tex.view, gpa);
        device.destroyImage(tex.image, gpa);
        device.freeMemory(tex.memory, gpa);
    }
};

pub const Mesh = struct {
    mesh_memory: mango.DeviceMemory,
    vertex_buffer: mango.Buffer,
    index_buffer: mango.Buffer,
    index_type: mango.IndexType,
    index_count: usize,

    pub fn init(device: mango.Device, gpa: std.mem.Allocator, index_type: mango.IndexType, index_data: []const u8, vertex_data: []const u8) !Mesh {
        const mesh_memory = try device.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(index_data.len + vertex_data.len),
        }, gpa);
        errdefer device.freeMemory(mesh_memory, gpa);

        {
            const mapped = try device.mapMemory(mesh_memory, 0, .whole);
            defer device.unmapMemory(mesh_memory);

            @memcpy(mapped[0..vertex_data.len], vertex_data);
            @memcpy(mapped[vertex_data.len..][0..index_data.len], index_data);

            try device.flushMappedMemoryRanges(&.{.{
                .memory = mesh_memory,
                .offset = .size(0),
                .size = .whole,
            }});
        }

        const vertex = try device.createBuffer(.{
            .size = .size(vertex_data.len),
            .usage = .{
                .vertex_buffer = true,
            },
        }, gpa);
        errdefer device.destroyBuffer(vertex, gpa);
        try device.bindBufferMemory(vertex, mesh_memory, .size(0));

        const index = try device.createBuffer(.{
            .size = .size(index_data.len),
            .usage = .{
                .index_buffer = true,
            },
        }, gpa);
        errdefer device.destroyBuffer(index, gpa);
        try device.bindBufferMemory(index, mesh_memory, .size(vertex_data.len));

        return .{
            .mesh_memory = mesh_memory,
            .vertex_buffer = vertex,
            .index_buffer = index,
            .index_type = index_type,
            .index_count = index_data.len >> @intCast(@intFromEnum(index_type)),
        };
    }

    pub fn deinit(mesh: Mesh, device: mango.Device, gpa: std.mem.Allocator) void {
        device.destroyBuffer(mesh.vertex_buffer, gpa);
        device.destroyBuffer(mesh.index_buffer, gpa);
        device.freeMemory(mesh.mesh_memory, gpa);
    }

    /// Binds its index buffer and vertex buffer.
    pub fn bind(mesh: Mesh, cmd: mango.CommandBuffer) void {
        cmd.bindIndexBuffer(mesh.index_buffer, 0, mesh.index_type);
        cmd.bindVertexBuffersSlice(0, &.{mesh.vertex_buffer}, &.{0});
    }

    /// Assumes that a proper rendering setup has been done
    /// and that `bind` has been called.
    ///
    /// Issues a draw call.
    pub fn draw(mesh: Mesh, cmd: mango.CommandBuffer) void {
        cmd.drawIndexed(mesh.index_count, 0, 0);
    }
};

pub fn main() !void {
    // var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    // defer _ = gpa_state.deinit();

    const gpa = horizon.heap.page_allocator; // gpa_state.allocator();

    var app: horizon.application.Accelerated = try .init(.default, gpa);
    defer app.deinit(gpa);

    const device: mango.Device = app.device;

    const top_swap: DoubleBufferedSwapchain = try .initBgr888(device, .top_240x400, gpa);
    defer top_swap.deinit(device, gpa);

    const bottom_swap: DoubleBufferedSwapchain = try .initBgr888(device, .bottom_240x320, gpa);
    defer bottom_swap.deinit(device, gpa);

    defer device.waitIdle() catch unreachable;

    var scene: Scene = try .init(device, gpa);
    defer scene.deinit(device, gpa);

    // TODO: unfill lcds when swapchains have at least 1 present instead of here.
    try app.gsp.sendSetLcdForceBlack(false);
    defer if (!app.apt_app.flags.must_close) app.gsp.sendSetLcdForceBlack(true) catch {}; // NOTE: Could fail if we don't have right?

    main_loop: while (true) {
        while (try app.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        const bottom_image_idx = try bottom_swap.acquireNext(device);
        const top_image_idx = try top_swap.acquireNext(device);

        try scene.update();
        try scene.render();
        try scene.submitPresent(device, top_swap, top_image_idx, bottom_swap, bottom_image_idx);
    }
}

const horizon = zitrus.horizon;
const ServiceManager = horizon.ServiceManager;
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
const Hid = horizon.services.Hid;

const mango = zitrus.mango;

pub const panic = zitrus.horizon.panic;
const zitrus = @import("zitrus");
const std = @import("std");

comptime {
    _ = zitrus;
    // _ = zitrus.c;
}
