// NOTE: as you can see, the shader address must be aligned to 32-bits
const position_vtx_storage align(@sizeOf(u32)) = @embedFile("position_uv.psh").*;
const position_vtx = &position_vtx_storage;

// NOTE: The image is linear, will be unswizzled later.
const test_bgr = @embedFile("test.bgr");

pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

const Vertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
};

const vertices: []const Vertex = &.{
    .{ .pos = .{ -0.5, -0.5 }, .uv = .{ 0, 0 } },
    .{ .pos = .{ 0.5, -0.5 }, .uv = .{ 1, 0 }  },
    .{ .pos = .{ -0.5, 0.5 }, .uv = .{ 0, 1 }  },
    .{ .pos = .{ 0.5, 0.5 }, .uv = .{ 1, 1 }  },
};
const indices: []const u8 = &.{ 0, 1, 2, 2, 1, 3 };

pub fn main(init: horizon.Init.Application.Mango) !void {
    const gpa = init.app.base.gpa;
    const device: mango.Device = init.device;

    var state: State = try .init(device);
    defer state.deinit(device);

    const model_buffer = try device.createBuffer(.{
        .size = .size(@sizeOf(Vertex) * 4 + 6),
        .usage = .{
            .vertex_buffer = true,
            .index_buffer = true,
        },
    }, gpa);
    defer device.destroyBuffer(model_buffer, null);

    const buffer_memory = try device.allocateMemory(.{
        .memory_type = .fcram_cached,
        .allocation_size = .size(@sizeOf(Vertex) * 4 + 6),
    }, null);
    defer device.freeMemory(buffer_memory, null);

    {
        const mapped = try device.mapMemory(buffer_memory, .size(0), .whole);
        defer device.unmapMemory(buffer_memory);

        const vtx_data: *[4]Vertex = @alignCast(std.mem.bytesAsValue([4]Vertex, mapped));
        const idx_data: *[6]u8 = std.mem.bytesAsValue([6]u8, mapped[@sizeOf([4]Vertex)..]);

        @memcpy(vtx_data, vertices);
        @memcpy(idx_data, indices);

        try device.flushMappedMemoryRanges(&.{
            .{
                .memory = buffer_memory,
                .offset = .size(0),
                .size = .whole,
            },
        });
    }
    try device.bindBufferMemory(model_buffer, buffer_memory, .size(0));

    const simple_shader = try device.createShader(.init(.psh, position_vtx, "main"), null);
    defer device.destroyShader(simple_shader, null);

    const vertex_input_layout = try device.createVertexInputLayout(.init(&.{
        .{
            .stride = @sizeOf(Vertex),
        },
    }, &.{
        .{
            .location = .v0,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .location = .v1,
            .binding = .@"0",
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "uv"),
        },
    }, &.{}), null);
    defer device.destroyVertexInputLayout(vertex_input_layout, null);

    const texture_memory = try device.allocateMemory(.{
        .memory_type = .vram_a,
        .allocation_size = .size(64 * 64 * 3),
    }, null);
    defer device.freeMemory(texture_memory, null);

    const texture = try device.createImage(.{
        .flags = .{},
        .type = .@"2d",
        .tiling = .optimal,
        .usage = .{
            .transfer_dst = true,
            .sampled = true,
        },
        .extent = .{ .width = 64, .height = 64 },
        .format = .b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, null);
    defer device.destroyImage(texture, null);
    try device.bindImageMemory(texture, texture_memory, .size(0));

    const texture_view = try device.createImageView(.{
        .type = .@"2d",
        .format = .b8g8r8_unorm,
        .image = texture,
        .subresource_range = .full,
    }, null);
    defer device.destroyImageView(texture_view, null);

    const linear_sampler = try device.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mip_filter = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .lod_bias = 0.0,
        .min_lod = 0,
        .max_lod = 0,
        .border_color = @splat(0),
    }, null);
    defer device.destroySampler(linear_sampler, null);

    {
        const staging_memory = try device.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(64*64*3),
        }, null);
        defer device.freeMemory(staging_memory, null);

        const staging_buffer = try device.createBuffer(.{
            .size = .size(64*64*3), 
            .usage = .{
                .transfer_src = true,
            }
        }, null);
        defer device.destroyBuffer(staging_buffer, null);
        try device.bindBufferMemory(staging_buffer, staging_memory, .size(0));

        const mapped = try device.mapMemory(staging_memory, .size(0), .size(64*64*3));
        defer device.unmapMemory(staging_memory);

        @memcpy(mapped, test_bgr);
        try device.flushMappedMemoryRanges(&.{
            .{
                .memory = staging_memory,
                .offset = .size(0),
                .size = .whole,
            }
        });
        
        try device.getQueue(.transfer).copyBufferToImage(.{
            .wait_semaphore = &.init(state.sema, state.sync),
            .src_buffer = staging_buffer,
            .src_offset = .size(0),
            .dst_image = texture,
            .dst_subresource = .full,
            .signal_semaphore = &.init(state.sema, state.sync + 1),
        });

        state.sync += 1;
        try device.waitSemaphores(.init(&.{state.sema}, &.{state.sync}), std.math.maxInt(u64));
    }

    const input = init.app.input;

    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const pad = input.pollPad();
        if (pad.current.start) break :main_loop;

        const cmd, const color_attachment = try state.acquireNextTarget(device);

        // Same command recording workflow as Vulkan.
        //
        // However, some things change.
        // E.g: We have `bindCombinedImageSamplers`, `bindLightEnvironmentFactors`, `bindLights`, ...
        try cmd.begin();

        // Set the initial state, the validation (in safe modes) will guide you
        cmd.bindShaders(&.{.vertex}, &.{simple_shader});
        cmd.setVertexInput(vertex_input_layout);
        cmd.setLightingEnable(false);
        cmd.setLogicOpEnable(false);
        cmd.setAlphaTestEnable(false);
        cmd.setDepthTestEnable(false);
        cmd.setStencilTestEnable(false);
        cmd.setCullMode(.none);
        cmd.setFrontFace(.ccw);
        cmd.setPrimitiveTopology(.triangle_list);
        cmd.setColorWriteMask(.rgba);
        cmd.setBlendEquation(.{
            .src_color_factor = .one,
            .dst_color_factor = .zero,
            .color_op = .add,
            .src_alpha_factor = .one,
            .dst_alpha_factor = .zero,
            .alpha_op = .add,
        });
        cmd.setTextureCombiners(&.{
            .{
                .color_src = .{.primary_color, .texture_0, .primary_color},
                .alpha_src = @splat(.primary_color),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .modulate,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0),
            },
        }, &.{});

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

        cmd.bindIndexBuffer(model_buffer, @sizeOf([4]Vertex), .u8);
        cmd.bindVertexBuffersSlice(0, &.{model_buffer}, &.{0});
        cmd.bindCombinedImageSamplers(0, &.{
            .{
                .image = texture_view,
                .sampler = linear_sampler,
            }
        });

        {
            cmd.beginRendering(.{
                .color_attachment = color_attachment,
                .depth_stencil_attachment = .null,
            });
            defer cmd.endRendering();

            cmd.drawIndexed(indices.len, 0, 0);
        }
        try cmd.end();
        
        try state.submitBlit(device, @splat(0x22));
    }
}

const common = @import("common");
const State = common.State;

const mango = zitrus.mango;
const horizon = zitrus.horizon;

const zitrus = @import("zitrus");
const std = @import("std");
