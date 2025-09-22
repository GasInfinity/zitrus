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

// TODO: Finish rendering this cube.
/// Uses a RH coordinate system.
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

    render_buffer_memory: mango.DeviceMemory,
    top_color_buffer: mango.Image,
    top_color_buffer_view: mango.ImageView,
    top_depth_buffer: mango.Image,

    vertex_index_memory: mango.DeviceMemory,
    vertex_buffer: mango.Buffer,
    index_buffer: mango.Buffer,

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
                .cull_mode = .back,

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
                .depth_compare_op = .gt,

                .stencil_test_enable = false,
                .back_front = std.mem.zeroes(mango.GraphicsPipelineCreateInfo.AlphaDepthStencilState.StencilOperationState),
            },
            .texture_sampling_state = &.{
                .texture_enable = .{ true, false, false, false },

                .texture_2_coordinates = .@"2",
                .texture_3_coordinates = .@"2",
            },
            .lighting_state = &.{},
            .texture_combiner_state = &.init(&.{.{
                .color_src = @splat(.texture_0),
                .alpha_src = @splat(.primary_color),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .replace,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0),
            }}, &.{}),
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

        return .{
            .semaphore = sema,
            .current_timeline = 0,

            .pipeline = pipeline,
        };
    }

    pub fn deinit(scene: *Scene, device: mango.Device, gpa: std.mem.Allocator) void {
        _ = scene;
        _ = device;
        _ = gpa;
    }

    pub fn update(scene: *Scene) void {
        _ = scene;
    }

    pub fn render(scene: *Scene, buffer: mango.CommandBuffer) !void {
        _ = scene;
        _ = buffer;
    }

    pub fn submit(device: mango.Device, current_top_image: mango.Image, current_bottom_image: mango.Image) !void {
        _ = device;
        _ = current_top_image;
        _ = current_bottom_image;
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
        device.destroySwapchain(chain.swapchain, gpa);
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
    color_memory: mango.DeviceMemory,
    color: mango.Image,
    color_view: mango.ImageView,

    depth_memory: mango.DeviceMemory,
    depth: mango.Image,
    depth_view: mango.ImageView,

    // TODO: RenderBuffer abstraction for this demo
    // pub fn init(device: mango.Device, gpa: std.mem.Allocator, w: u16, h: u16, color_bpp: usize, depth_bpp: usize, color: mango.Format, depth: mango.Format) !Renderbuffer {
    //     const color_mem = try device.allocateMemory(.{
    //         .memory_type = .vram_a,
    //         .allocation_size = .size(color_bpp * w * h),
    //     }, gpa);
    //     errdefer device.freeMemory(color_mem, gpa);
    //
    //     return .{
    //
    //     };
    // }

    pub fn deinit(render: Renderbuffer, device: mango.Device, gpa: std.mem.Allocator) void {
        device.destroyImageView(render.color_view, gpa);
        device.destroyImage(render.color, gpa);
        device.freeMemory(render.color_memory, gpa);

        if (render.depth != .null) {
            device.destroyImageView(render.depth_view, gpa);
            device.destroyImage(render.depth, gpa);
            device.freeMemory(render.depth_memory, gpa);
        }
    }
};

pub const SimpleTexture = struct {
    memory: mango.DeviceMemory,
    image: mango.Image,
    view: mango.ImageView,

    // TODO: Our images are not tiled, we need to use a staging buffer before using this.
    pub fn init(device: mango.Device, gpa: std.mem.Allocator, w: u16, h: u16, format: mango.Format, data: []const u8) SimpleTexture {
        const memory = try device.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(data.len),
        }, gpa);
        errdefer device.freeMemory(memory, gpa);

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

        const image = try device.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .optimal,
            .usage = .{
                .transfer_dst = true,
                .sampled = true,
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

    pub fn deinit(tex: SimpleTexture, device: mango.Device, gpa: std.mem.Allocator) void {
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

    const transfer_queue = device.getQueue(.transfer);
    const fill_queue = device.getQueue(.fill);
    const submit_queue = device.getQueue(.submit);
    const present_queue = device.getQueue(.present);

    const global_semaphore = try device.createSemaphore(.{
        .initial_value = 0,
    }, gpa);
    defer device.destroySemaphore(global_semaphore, gpa);
    var global_sync_counter: u64 = 0;

    const top_swap: DoubleBufferedSwapchain = try .initBgr888(device, .top_240x400, gpa);
    defer top_swap.deinit(device, gpa);

    const bottom_swap: DoubleBufferedSwapchain = try .initBgr888(device, .bottom_240x320, gpa);
    defer bottom_swap.deinit(device, gpa);

    const Vertex = extern struct {
        pos: [4]i8,
        uv: [2]u8,
    };

    const indices: []const u8 = &.{ 0, 1, 2, 3 };
    const vertices: []const Vertex = &.{
        .{ .pos = .{ -1, -1, 2, 1 }, .uv = .{ 0, 0 } },
        .{ .pos = .{ 1, -1, 2, 1 }, .uv = .{ 1, 0 } },
        .{ .pos = .{ -1, 1, 4, 1 }, .uv = .{ 0, 1 } },
        .{ .pos = .{ 1, 1, 4, 1 }, .uv = .{ 1, 1 } },
    };

    var quad_mesh: Mesh = try .init(device, gpa, .u8, indices, std.mem.sliceAsBytes(vertices));
    defer quad_mesh.deinit(device, gpa);

    const color_attachment_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(320 * 240 * 4 + 400 * 240 * 4 * 2),
    }, gpa);
    defer device.freeMemory(color_attachment_image_memory, gpa);

    const top_color_attachment_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_src = true,
            .color_attachment = true,
        },
        .extent = .{
            .width = 240,
            .height = 400,
        },
        .format = .a8b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(top_color_attachment_image, gpa);
    try device.bindImageMemory(top_color_attachment_image, color_attachment_image_memory, .size(320 * 240 * 4));

    const bottom_color_attachment_image = try device.createImage(.{
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
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(bottom_color_attachment_image, gpa);
    try device.bindImageMemory(bottom_color_attachment_image, color_attachment_image_memory, .size(0));

    const staging_buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(64 * 64 * 3),
    }, gpa);
    defer device.freeMemory(staging_buffer_memory, gpa);

    const staging_buffer = try device.createBuffer(.{
        .size = .size(64 * 64 * 3),
        .usage = .{
            .transfer_src = true,
        },
    }, gpa);
    defer device.destroyBuffer(staging_buffer, gpa);
    try device.bindBufferMemory(staging_buffer, staging_buffer_memory, .size(0));

    {
        const mapped_staging = try device.mapMemory(staging_buffer_memory, 0, .whole);
        defer device.unmapMemory(staging_buffer_memory);

        @memcpy(mapped_staging[0..(64 * 64 * 3)], test_bgr);

        try device.flushMappedMemoryRanges(&.{.{
            .memory = staging_buffer_memory,
            .offset = .size(0),
            .size = .size(64 * 64 * 3),
        }});
    }

    const test_sampled_image_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(64 * 64 * 3),
    }, gpa);
    defer device.freeMemory(test_sampled_image_memory, gpa);

    const test_sampled_image = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_dst = true,
            .sampled = true,
        },
        .extent = .{
            .width = 64,
            .height = 64,
        },
        .format = .b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    defer device.destroyImage(test_sampled_image, gpa);
    try device.bindImageMemory(test_sampled_image, test_sampled_image_memory, .size(0));

    try transfer_queue.copyBufferToImage(.{
        .src_buffer = staging_buffer,
        .src_offset = .size(0),
        .dst_image = test_sampled_image,
        .dst_subresource = .full,
        .signal_semaphore = &.init(global_semaphore, global_sync_counter + 1),
    });

    global_sync_counter += 1;

    const test_sampled_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .b8g8r8_unorm,
        .image = test_sampled_image,
        .subresource_range = .{
            .base_mip_level = .@"0",
            .level_count = .@"1",
            .base_array_layer = .@"0",
            .layer_count = .@"1",
        },
    }, gpa);
    defer device.destroyImageView(test_sampled_image_view, gpa);

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

    const bottom_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = bottom_color_attachment_image,
        .subresource_range = .full,
    }, gpa);
    defer device.destroyImageView(bottom_color_attachment_image_view, gpa);

    const top_color_attachment_image_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = top_color_attachment_image,
        .subresource_range = .full,
    }, gpa);
    defer device.destroyImageView(top_color_attachment_image_view, gpa);

    const simple_pipeline = try device.createGraphicsPipeline(.{
        .rendering_info = &.{
            .color_attachment_format = .a8b8g8r8_unorm,
            .depth_stencil_attachment_format = .undefined,
        },
        .vertex_input_state = &.init(&.{
            .{
                .stride = @sizeOf(Vertex),
            },
        }, &.{
            .{
                .location = .v0,
                .binding = .@"0",
                .format = .r8g8b8a8_sscaled,
                .offset = 0,
            },
            .{
                .location = .v1,
                .binding = .@"0",
                .format = .r8g8_uscaled,
                .offset = 4,
            },
        }, &.{}),
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
        .texture_sampling_state = &.{
            .texture_enable = .{ true, false, false, false },

            .texture_2_coordinates = .@"2",
            .texture_3_coordinates = .@"2",
        },
        .lighting_state = &.{},
        .texture_combiner_state = &.init(&.{.{
            .color_src = @splat(.texture_0),
            .alpha_src = @splat(.primary_color),
            .color_factor = @splat(.src_color),
            .alpha_factor = @splat(.src_alpha),
            .color_op = .replace,
            .alpha_op = .replace,

            .color_scale = .@"1x",
            .alpha_scale = .@"1x",

            .constant = @splat(0),
        }}, &.{}),
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
    defer device.destroyPipeline(simple_pipeline, gpa);

    const command_pool = try device.createCommandPool(.{}, gpa);
    defer device.destroyCommandPool(command_pool, gpa);

    const cmd = blk: {
        var cmd: mango.CommandBuffer = undefined;
        try device.allocateCommandBuffers(.{
            .pool = command_pool,
            .command_buffer_count = 1,
        }, @ptrCast(&cmd));
        break :blk cmd;
    };
    defer device.freeCommandBuffers(command_pool, @ptrCast(&cmd));

    // TODO: unfill lcds when swapchains have at least 1 present instead of here.
    try app.gsp.sendSetLcdForceBlack(false);
    defer if (!app.apt_app.flags.must_close) app.gsp.sendSetLcdForceBlack(true) catch {}; // NOTE: Could fail if we don't have right?

    // XXX: Bad, but we know this is not near graphicaly intensive and we'll always be near 60 FPS.
    const default_delta_time = 1.0 / 60.0;
    var current_time: f32 = 0.0;
    // var current_scale: f32 = 1.0;
    main_loop: while (true) {
        defer current_time += default_delta_time;

        while (try app.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = app.input.pollPad();

        if (pad.current.start) {
            break :main_loop;
        }

        // if(input.current.up) {
        //     current_scale += 1.0 * default_delta_time * 5;
        // } else if(input.current.down) {
        //     current_scale -= 1.0 * default_delta_time * 5;
        // }
        // current_scale = std.math.clamp(current_scale, -1.0, 1.0);

        const bottom_image_idx = try bottom_swap.acquireNext(device);
        const top_image_idx = try top_swap.acquireNext(device);

        try cmd.begin();

        quad_mesh.bind(cmd);
        cmd.bindPipeline(.graphics, simple_pipeline);
        cmd.bindCombinedImageSamplers(0, &.{.{
            .image = test_sampled_image_view,
            .sampler = simple_sampler,
        }});

        // Render to the bottom screen
        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = 240, .height = 320 },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmd.setScissor(.inside(.{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = 240, .height = 320 } }));

        {
            cmd.beginRendering(.{
                .color_attachment = bottom_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(.left, std.math.degreesToRadians(90.0), 240.0 / 320.0, 1, 1000));

            const current_scale = 1; //@sin(current_time);
            cmd.bindFloatUniforms(.vertex, 4, &zmath.mat.scale(current_scale, @abs(current_scale), 1));
            quad_mesh.draw(cmd);
        }

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
                .color_attachment = top_color_attachment_image_view,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            const zmath = zitrus.math;

            cmd.bindFloatUniforms(.vertex, 0, &zmath.mat.perspRotate90Cw(.left, std.math.degreesToRadians(90.0), 240.0 / 400.0, 1, 1000));

            const current_scale = 1; //@sin(-current_time);
            cmd.bindFloatUniforms(.vertex, 4, &zmath.mat.scaleTranslate(current_scale, @abs(current_scale), 1, 0, 0, 0));

            // NOTE: We haven't changed vertex and index buffers, that's why we don't bind() again!
            quad_mesh.draw(cmd);
        }

        try cmd.end();

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter),
            .image = bottom_color_attachment_image,
            .color = @splat(0x33),
            .subresource_range = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 1),
        });

        try fill_queue.clearColorImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 1),
            .image = top_color_attachment_image,
            .color = @splat(0x22),
            .subresource_range = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 2),
        });

        try submit_queue.submit(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 2),
            .command_buffer = cmd,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 3),
        });

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 3),
            .src_image = bottom_color_attachment_image,
            .dst_image = bottom_swap.images[bottom_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 4),
        });

        try transfer_queue.blitImage(.{
            .wait_semaphore = &.init(global_semaphore, global_sync_counter + 4),
            .src_image = top_color_attachment_image,
            .dst_image = top_swap.images[top_image_idx],
            .src_subresource = .full,
            .dst_subresource = .full,
            .signal_semaphore = &.init(global_semaphore, global_sync_counter + 5),
        });

        try bottom_swap.present(present_queue, bottom_image_idx, &.init(global_semaphore, global_sync_counter + 4));
        try top_swap.present(present_queue, top_image_idx, &.init(global_semaphore, global_sync_counter + 5));

        // We're currently using one color attachment so even though we're double-buffered on the swapchain,
        // we only have a single buffer to work on. We must wait until we finished with the color buffer.
        try device.waitSemaphore(.{
            .semaphore = global_semaphore,
            .value = global_sync_counter + 5,
        }, -1);
        global_sync_counter += 5;
    }

    try device.waitIdle();
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
    _ = zitrus.c;
}
