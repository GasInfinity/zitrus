//! NOTE: Deprecated and won't be updated, a new DOD layout engine and imgui is being cooked!
//!
//! I cannot stand how inefficient this is, almost 40 drawcalls for simple UI...

pub const kind: dvui.enums.Backend = .custom;

const max_batched_vertices = (std.math.maxInt(u16) + 1);
const max_batched_vertices_byte_size = max_batched_vertices * @sizeOf(dvui.Vertex);
const default_batched_indices = (std.math.maxInt(u16) + 1);
const default_batched_indices_byte_size = default_batched_indices * @sizeOf(u16);

// XXX: Needed as we cannot align it directly.
const dvui_shader_storage align(@sizeOf(u32)) = @embedFile("dvui.psh").*;
const dvui_shader = &dvui_shader_storage;

// XXX: Upstream issue about this, not ideal...
var alloc: std.mem.Allocator = undefined;

pub const CombinerState = enum {
    solid,
    textured,
};

pub const Statistics = struct {
    pub const empty: Statistics = .{};

    draw_calls: u32 = 0,
    combiner_state_changes: u32 = 0,
};

gpa: std.mem.Allocator,
device: mango.Device,
pipeline: mango.Pipeline,

sema: mango.Semaphore,
sema_index: u64,

cmd: mango.CommandBuffer,
flushed_pipeline: bool,
inside_renderpass: bool,
combiner_state: ?CombinerState,

/// Real size, without applying rotation
root_render_size: [2]u16,
root_color_attachment: mango.ImageView,

current_render_size: [2]u16,
current_color_attachment: mango.ImageView,

// XXX: We're currently doing a drawcall and NOT batching anything but thats fine for now.
vertex_memory: mango.DeviceMemory,
index_memory: mango.DeviceMemory,
vertex_buffer: mango.Buffer,
index_buffer: mango.Buffer,

mapped_vertices: []dvui.Vertex,
mapped_indices: []u16,

current_vertex: usize,
current_index: usize,

linear_sampler: mango.Sampler,
nearest_sampler: mango.Sampler,
textures: std.ArrayList(Texture),

root_projection_matrix: [4][4]f32,
current_projection_matrix: [4][4]f32,

/// If rotated 90º counter clockwise (used for the screens mainly)
root_rotate: bool,
current_rotate: bool,

/// Logical size, i.e: for touch, `windowSize`, etc...
root_size: [2]u16,
last_touch: ?[2]f32,

stats: Statistics,

const Texture = struct {
    linear: bool,
    memory_size: mango.DeviceSize,
    memory: mango.DeviceMemory,
    image: mango.Image,
    view: mango.ImageView,
};

pub const InitOptions = struct {
    gpa: std.mem.Allocator,
    device: mango.Device,

    /// The format the color attachments and render targets will have,
    /// `null` means it will be dynamic state.
    color_attachment_format: ?mango.Format,
};

pub fn init(options: InitOptions) !Backend {
    const gpa = options.gpa;
    const device = options.device;

    const sema = try device.createSemaphore(.initial_zero, options.gpa);
    errdefer device.destroySemaphore(sema, gpa);

    const nearest_sampler = try device.createSampler(.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
        .mip_filter = .nearest, // We don't use mips however.
        .address_mode_u = .clamp_to_border,
        .address_mode_v = .clamp_to_border,
        .lod_bias = 0.0,
        .min_lod = 0,
        .max_lod = 7,
        .border_color = @splat(64),
    }, gpa);
    errdefer device.destroySampler(nearest_sampler, gpa);

    const linear_sampler = try device.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .linear,
        .mip_filter = .linear,
        .address_mode_u = .clamp_to_border,
        .address_mode_v = .clamp_to_border,
        .lod_bias = 0.0,
        .min_lod = 0,
        .max_lod = 7,
        .border_color = @splat(64), 
    }, gpa);
    errdefer device.destroySampler(linear_sampler, gpa);

    const vertex_memory = try device.allocateMemory(.{
        .allocation_size = .size(max_batched_vertices_byte_size),
        .memory_type = .fcram_cached,
    }, gpa);
    errdefer device.freeMemory(vertex_memory, gpa);

    const index_memory = try device.allocateMemory(.{
        .allocation_size = .size(default_batched_indices_byte_size),
        .memory_type = .fcram_cached, 
    }, gpa);
    errdefer device.freeMemory(index_memory, gpa);

    const vertex_buffer = try device.createBuffer(.{
        .size = .size(max_batched_vertices_byte_size),
        .usage = .{
            .vertex_buffer = true,
        }, 
    }, gpa);
    errdefer device.destroyBuffer(vertex_buffer, gpa);
    try device.bindBufferMemory(vertex_buffer, vertex_memory, .size(0));

    const index_buffer = try device.createBuffer(.{
        .size = .size(default_batched_indices_byte_size),
        .usage = .{
            .index_buffer = true,
        }, 
    }, gpa);
    errdefer device.destroyBuffer(index_buffer, gpa);
    try device.bindBufferMemory(index_buffer, index_memory, .size(0));

    const mapped_vertices = try device.mapMemory(vertex_memory, 0, .whole);
    const mapped_indices= try device.mapMemory(index_memory, 0, .whole);
    alloc = gpa;

    const pipeline = try device.createGraphicsPipeline(.{
        .rendering_info = &.{
            // NOTE: Its safe to set it to undefined as when the formats are dynamic this is ignored!
            .color_attachment_format = options.color_attachment_format orelse .undefined,
            .depth_stencil_attachment_format = .undefined,
        },
        .vertex_shader_state = &.init(dvui_shader, "main"),
        .geometry_shader_state = null,

        .vertex_input_state = &.init(&.{
            .{
                .stride = @sizeOf(dvui.Vertex), // XXX: Not really extern compatible...
            }
        }, &.{
           .{
               .location = .v0,
               .binding = .@"0",
               .format = .r32g32_sfloat,
               .offset = @offsetOf(dvui.Vertex, "pos"), 
           },
           .{
               .location = .v1,
               .binding = .@"0",
               .format = .r8g8b8a8_uscaled,
               .offset = @offsetOf(dvui.Vertex, "col"), 
           },
           .{
               .location = .v2,
               .binding = .@"0",
               .format = .r32g32_sfloat,
               .offset = @offsetOf(dvui.Vertex, "uv"), 
           },
        }, &.{}),
        .input_assembly_state = &.{
            .topology = .triangle_list,
        },
        .viewport_state = null, // dynamic
        .rasterization_state = &.{
            .front_face = .ccw,
            .cull_mode = .none,

            .depth_mode = .z_buffer,
            .depth_bias_constant = 0.0,
        },
        .alpha_depth_stencil_state = &.{
            .alpha_test_enable = false,
            .depth_test_enable = false,
            .stencil_test_enable = false,
        },
        .texture_sampling_state = &.{
            .texture_2_coordinates = .@"2",
            .texture_3_coordinates = .@"2",
        },
        .lighting_state = &.{
            .enable = false,
        },
        .texture_combiner_state = null, // dynamic
        .color_blend_state = &.{
            .logic_op_enable = false,

            .attachment = .{
                .blend_equation = .{
                    .src_color_factor = .one,
                    .dst_color_factor = .one_minus_src_alpha,
                    .color_op = .add,
                    .src_alpha_factor = .one,
                    .dst_alpha_factor = .one_minus_src_alpha,
                    .alpha_op = .add,
                },
                .color_write_mask = .rgba, 
            },
            .blend_constants = @splat(0),
        },
        .dynamic_state = .{
            .viewport = true,
            .scissor = true,
            // dvui may want to draw with AND without textures
            .texture_combiner = true,
        }, 
    }, gpa);
    errdefer device.destroyPipeline(pipeline, gpa);

    return .{
        .gpa = options.gpa,
        .device = device,

        .pipeline = pipeline,
        .sema = sema,
        .sema_index = 0,

        .cmd = .null,
        .flushed_pipeline = false,
        .inside_renderpass = false,
        .combiner_state = null,

        .root_render_size = @splat(0),
        .root_color_attachment = .null,

        .current_render_size = @splat(0),
        .current_color_attachment = .null,

        .vertex_memory = vertex_memory,
        .index_memory = index_memory,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,

        // NOTE: These @alignCasts will ALWAYS be valid, mango guarantees that memory allocated
        // will have the minimum alignment required for any gpu operation.
        .mapped_vertices = @alignCast(std.mem.bytesAsSlice(dvui.Vertex, mapped_vertices)),
        .mapped_indices = @alignCast(std.mem.bytesAsSlice(u16, mapped_indices)),

        .current_vertex = 0,
        .current_index = 0,

        .nearest_sampler = nearest_sampler,
        .linear_sampler = linear_sampler,

        .textures = .empty,

        .root_projection_matrix = undefined,
        .current_projection_matrix = undefined,

        .root_rotate = false,
        .current_rotate = false,
        .root_size = @splat(0),

        .last_touch = null,

        .stats = .empty,
    };
}

pub fn deinit(bd: *Backend) void {
    bd.device.destroyPipeline(bd.pipeline, bd.gpa);
    bd.device.destroyBuffer(bd.index_buffer, bd.gpa);
    bd.device.destroyBuffer(bd.vertex_buffer, bd.gpa);
    bd.device.unmapMemory(bd.index_memory);
    bd.device.unmapMemory(bd.vertex_memory);
    bd.device.freeMemory(bd.index_memory, bd.gpa);
    bd.device.freeMemory(bd.vertex_memory, bd.gpa);
    bd.device.destroySampler(bd.linear_sampler, bd.gpa);
    bd.device.destroySampler(bd.nearest_sampler, bd.gpa);
}

pub fn begin(_: *Backend, arena: std.mem.Allocator) !void {
    _ = arena;
}

pub fn end(_: *Backend) !void {
}

// XXX: This shouldn't be here, dvui should split rendering and event handling!
pub fn addAllEvents(bd: *Backend, win: *dvui.Window, input: horizon.services.Hid.Input) !bool {
    const touch = input.pollTouch();

    if(touch.pressed) {
        const x: f32 = @floatFromInt(touch.x);
        const y: f32 = @floatFromInt(touch.y);

        const x_norm = x / @as(f32, @floatFromInt(bd.root_size[0]));
        const y_norm = y / @as(f32, @floatFromInt(bd.root_size[1]));

        if(bd.last_touch) |last| {
            const dx = x_norm - last[0];
            const dy = y_norm - last[1];

            _ = try win.addEventTouchMotion(.touch0, x_norm, y_norm, dx, dy); 
        } else {
            _ = try win.addEventPointer(.{
                .button = .touch0,
                .action = .press,
                .xynorm = .{
                    .x = x_norm, 
                    .y = y_norm,
                },
            });
        }

        bd.last_touch = .{ x_norm, y_norm };
    } else if(bd.last_touch) |last| {
        _ = try win.addEventPointer(.{
            .button = .touch0,
            .action = .release,
            .xynorm = .{
                .x = last[0],
                .y = last[1],
            },
        });

        bd.last_touch = null;
    }

    return false;
}

pub fn preferredColorScheme(_: Backend) ?dvui.enums.ColorScheme {
    return null;
}

pub fn refresh(_: Backend) void {
}

pub fn pixelSize(bd: Backend) dvui.Size.Physical {
    return .{ .w = @floatFromInt(bd.root_size[0]), .h = @floatFromInt(bd.root_size[1]) };
}

pub fn windowSize(bd: Backend) dvui.Size.Natural {
    return .cast(bd.pixelSize());
}

pub fn contentScale(_: Backend) f32 {
    return 0.7;
}

pub fn cursorShow(_: Backend, value: ?bool) !void {
    _ = value;
}

pub fn setCursor(_: Backend, cursor: dvui.enums.Cursor) !void {
    _ = cursor;
}

pub const RenderingOptions = struct {
    pub const RootRotation = enum { identity, ccw90 };

    /// The app still owns the `mango.CommandBuffer` but it is forbidden to do anything with it until `endRendering`
    cmd: mango.CommandBuffer,

    color_attachment: mango.ImageView, 
    render_size: [2]u16,

    /// Whether contents should be rotated for the root view (e.g: when rendering to 3DS screens)
    rotate: RootRotation,
    /// If there's already a renderpass happening in `cmd` with `root_view` as a color attachment.
    /// The backend owns the renderpass if inherited.
    inside_pass: bool,
};

/// Begins rendering into the specified `mango.CommandBuffer` and view.
///
/// Between `beginRendering` and `endRendering` the `mango.CommandBuffer` must be in a render pass already.
///
/// Any bound `mango.Pipeline` is invalidated after this function is called, this includes dynamic state.
/// It is forbidden to bind a new `mango.Pipeline` or modify dynamic state between `beginRendering` and `endRendering`.
pub fn beginRendering(
    bd: *Backend, 
    options: RenderingOptions,
) !void {
    if(bd.cmd != .null) {
        log.err("Our `mango.CommandBuffer` is not `.null`, are you really calling `endRendering`?", .{}); 
    }

    bd.cmd = options.cmd;
    bd.flushed_pipeline = false;
    bd.inside_renderpass = options.inside_pass;
    bd.combiner_state = null;

    bd.root_color_attachment = options.color_attachment;
    bd.root_render_size = options.render_size;

    bd.current_color_attachment = options.color_attachment;
    bd.current_render_size = options.render_size;

    bd.current_vertex = 0;
    bd.current_index = 0;

    bd.root_projection_matrix = switch(options.rotate) {
        // NOTE: Remember we have OGL conventions, origin is bottom-left
        .identity => zitrus.math.mat.ortho(0, @floatFromInt(options.render_size[1]), @floatFromInt(options.render_size[0]), 0, 0, 1),
        .ccw90 => zitrus.math.mat.orthoRotate90Cw(0, @floatFromInt(options.render_size[0]), @floatFromInt(options.render_size[1]), 0, 0, 1),
    };

    bd.current_projection_matrix = bd.root_projection_matrix;

    bd.root_rotate = options.rotate == .ccw90;
    bd.current_rotate = options.rotate == .ccw90;

    bd.root_size = switch(options.rotate) {
        .identity => options.render_size,
        .ccw90 => .{ options.render_size[1], options.render_size[0] },
    };
    log.info("Begin!", .{});
}

/// Must be called and ends the render pass.
///
/// You're safe to do whatever you need with the `mango.CommandBuffer`.
pub fn endRendering(bd: *Backend) !mango.CommandBuffer {
    defer {
        bd.cmd = .null;
        bd.flushed_pipeline = false;
        bd.inside_renderpass = false;
        bd.combiner_state = null;

        bd.root_color_attachment = .null;
        bd.root_render_size = undefined;
        bd.current_color_attachment = .null;
        bd.current_render_size = undefined;

        bd.current_vertex = 0;
        bd.current_index = 0;

        bd.root_projection_matrix = undefined;
        bd.current_projection_matrix = undefined;
    }

    if(bd.flushed_pipeline) {
        // NOTE: This means we've at least done one drawcall!
        try bd.device.flushMappedMemoryRanges(&.{
            .{
                .memory = bd.vertex_memory,
                .offset = .size(0),
                .size = .size(bd.current_vertex * @sizeOf(dvui.Vertex)),
            },
            .{
                .memory = bd.index_memory,
                .offset = .size(0),
                .size = .size(bd.current_index * @sizeOf(u16)),
            }
        });
    }

    if(bd.inside_renderpass) bd.cmd.endRendering();

    log.info("End!", .{});
    // XXX: Fine for now but we need to come up with a way to not wait for the gpu to finish texture uploads!
    try bd.device.waitSemaphore(.{
        .semaphore = bd.sema,
        .value = bd.sema_index,
    }, -1);
    return bd.cmd;
}

pub fn drawClippedTriangles(bd: *Backend, maybe_texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, maybe_clip: ?dvui.Rect.Physical) !void {
    const initial_vertex_offset = bd.current_vertex;
    const initial_index_offset = bd.current_index;

    // XXX: See above, we could allocate dynamically memory and buffers but currently is NOT worth the extra complexity.
    if(initial_vertex_offset + vtx.len > max_batched_vertices) {
        log.err("Out of vertices, discarding drawcall! ({} vertices, {} indices)", .{vtx.len, idx.len});
        return;
    }

    if(initial_index_offset + idx.len > default_batched_indices) {
        log.err("Out of indices, discarding drawcall! ({} vertices, {} indices)", .{vtx.len, idx.len});
        return;
    }

    @memcpy(bd.mapped_vertices[initial_vertex_offset..][0..vtx.len], vtx);
    bd.current_vertex += vtx.len;

    @memcpy(bd.mapped_indices[initial_index_offset..][0..idx.len], idx);
    bd.current_index += idx.len;

    const cmd = bd.cmd;
    const scissor_rect: mango.Rect2D = if(maybe_clip) |clip| blk: {
        const clip_x: u16 = @intFromFloat(clip.x);
        const clip_y: u16 = @intFromFloat(clip.y);
        const clip_w: u16 = @intFromFloat(clip.w);
        const clip_h: u16 = @intFromFloat(clip.h);

        break :blk if(bd.current_rotate) .{
            .offset = .{ .x = (bd.current_render_size[0] - (clip_h + clip_y)), .y = (bd.current_render_size[1] - (clip_x + clip_w)) },
            .extent = .{ .width = clip_h, .height = clip_w },
        } else .{
            .offset = .{ .x = clip_x, .y = (bd.current_render_size[1] - (clip_y + clip_h)) },
            .extent = .{ .width = clip_w, .height = clip_h },
        };
    } else .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = bd.current_render_size[0], .height = bd.current_render_size[1] },
    };

    if(!bd.flushed_pipeline) {
        cmd.bindPipeline(.graphics, bd.pipeline);

        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = bd.current_render_size[0], .height = bd.current_render_size[1] },
            },
            .min_depth = 0,
            .max_depth = 1.0,
        });

        cmd.bindFloatUniforms(.vertex, 0, &bd.current_projection_matrix);

        bd.flushed_pipeline = true;
    }

    if(!bd.inside_renderpass) {
        cmd.beginRendering(.{
            .color_attachment = bd.current_color_attachment,
            .depth_stencil_attachment = .null,
        });

        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = bd.current_render_size[0], .height = bd.current_render_size[1] },
            },
            .min_depth = 0,
            .max_depth = 1.0,
        });

        cmd.bindFloatUniforms(.vertex, 0, &bd.current_projection_matrix);

        bd.inside_renderpass = true;
    }

    cmd.setScissor(.{
        .mode = .inside,
        .rect = scissor_rect,
    });

    if(maybe_texture) |texture| done: {
        const tex: *const Texture = &bd.textures.items[@intFromPtr(texture.ptr) - 1];

        const width: f32 = @floatFromInt(texture.width);
        const height: f32 = @floatFromInt(texture.height);
        const width_po2: f32 = @floatFromInt(@max(std.math.ceilPowerOfTwoAssert(u32, texture.width), 8));
        const height_po2: f32 = @floatFromInt(@max(std.math.ceilPowerOfTwoAssert(u32, texture.height), 8));

        cmd.bindFloatUniforms(.vertex, 4, &.{.{(width / width_po2), (height / height_po2), 0, 0}, .{0, 0, 0, 0}});
        cmd.bindCombinedImageSamplers(0, &.{
            .{
                .sampler = if(tex.linear) bd.linear_sampler else bd.nearest_sampler,
                .image = tex.view,
            },
        });

        if(bd.combiner_state == .textured) break :done; 
        cmd.setTextureCombiners(&.{
            .{
                .color_src = .{ .primary_color, .texture_0, .previous },
                .alpha_src = .{ .primary_color, .texture_0, .previous },
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .modulate,
                .alpha_op = .modulate,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(255), 
            }
        }, &.{});
        bd.combiner_state = .textured;
        bd.stats.combiner_state_changes += 1;
    } else done: {
        cmd.bindCombinedImageSamplers(0, &.{.none});

        if(bd.combiner_state == .solid) break :done; 
        cmd.setTextureCombiners(&.{
            .{
                .color_src = .{ .primary_color, .previous, .previous },
                .alpha_src = .{ .primary_color, .previous, .previous },
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .replace,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(255), 
            }
        }, &.{});
        bd.combiner_state = .solid;
        bd.stats.combiner_state_changes += 1;
    }

    cmd.bindIndexBuffer(bd.index_buffer, initial_index_offset * @sizeOf(u16), .u16);
    cmd.bindVertexBuffersSlice(0, &.{bd.vertex_buffer}, &.{initial_vertex_offset * @sizeOf(dvui.Vertex)});
    cmd.drawIndexed(@intCast(idx.len), 0, 0);

    bd.stats.draw_calls += 1;
    log.info("Drawcall! {} triangles, texture: {any}, clip: {any}", .{idx.len, maybe_texture, maybe_clip});
}

pub fn textureCreate(bd: *Backend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    const gpa = bd.gpa;
    const device = bd.device;
    const byte_stride = @as(u32, width) * 4;
    const byte_size = byte_stride * height;

    const width_po2: u16 = @intCast(@max(std.math.ceilPowerOfTwoAssert(u32, width), 8));
    const height_po2: u16 = @intCast(@max(std.math.ceilPowerOfTwoAssert(u32, height), 8));
    const po2_byte_stride = @as(u32, width_po2) * 4;
    const po2_byte_size = po2_byte_stride * height_po2;

    const memory = try device.allocateMemory(.{
        .allocation_size = .size(po2_byte_size),
        // XXX: We may want to promote to VRAM some textures? But its a scarce resource and we don't want for the app to go OOM!
        .memory_type = .fcram_cached,
    }, gpa);
    errdefer device.freeMemory(memory, gpa);

    const mapped = try device.mapMemory(memory, 0, .size(po2_byte_size));
    {
        defer device.unmapMemory(memory);
        pica.morton.convert2(.tile, 8, mapped, pixels[0..byte_size], .{
            .input_x = 0,
            .input_y = 0,
            .input_stride = byte_stride,

            .output_x = 0,
            .output_y = 0,
            .output_stride = po2_byte_stride,

            .width = width,
            .height = height,

            .pixel_size = 4,
        });

        try device.flushMappedMemoryRanges(&.{
            .{
                .memory = memory,
                .offset = .size(0),
                .size = .size(po2_byte_size),
            }
        });
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
            .width = width_po2,
            .height = height_po2,
        },
        .format = .a8b8g8r8_unorm,
        .mip_levels = .@"1",
        .array_layers = .@"1",
    }, gpa);
    errdefer device.destroyImage(image, gpa);
    try device.bindImageMemory(image, memory, .size(0));

    const view = try device.createImageView(.{
        .type = .@"2d",
        .format = .a8b8g8r8_unorm,
        .image = image,
        .subresource_range = .full,
    }, gpa);
    errdefer device.destroyImageView(view, gpa);

    const tid = 1 + bd.textures.items.len;
    try bd.textures.append(bd.gpa, .{
        .linear = interpolation == .linear,
        .memory_size = .size(po2_byte_size),
        .memory = memory,
        .image = image,
        .view = view,
    });

    return .{ .ptr = @ptrFromInt(tid), .width = width, .height = height };
}

pub fn textureCreateTarget(_: *Backend, _: u32, _: u32, _: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    // log.err("TODO: DVUI target create {}x{} interpolated with {}", .{width, height, interpolation});
    // log.info("Backend cmd: {}", .{bd.cmd});
}

pub fn textureFromTarget(bd: *Backend, texture: dvui.TextureTarget) dvui.Texture {
    _ = bd;
    _ = texture;
}

pub fn textureUpdate(bd: *Backend, texture: dvui.Texture, pixels: [*]const u8) !void {
    _ = bd;
    _ = texture;
    _ = pixels;
    horizon.debug.print("DVUI texture update", .{});
}

pub fn renderTarget(bd: *Backend, texture: ?dvui.TextureTarget) !void {
    if(bd.inside_renderpass) {
        bd.cmd.endRendering();
        bd.inside_renderpass = false;
    }

    if(texture) |tex| {
        _ = tex; 
    } else {
        bd.current_render_size = bd.root_render_size; 
        bd.current_color_attachment = bd.root_color_attachment;
    }

    log.err("TODO: DVUI set target", .{});
}

pub fn textureReadTarget(bd: *Backend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    // XXX: For this we NEED to use the device instead of using command buffers -> not great for performance and depends on synchronization.
    _ = bd;
    _ = texture;
    _ = pixels_out;
    return error.Unimplemented;
}

pub fn textureDestroy(bd: *Backend, texture: dvui.Texture) void {
    _ = bd;
    _ = texture;
    // log.info("TODO: texture destroy!", .{});
}

pub fn renderPresent(_: *Backend) !void {
}

pub fn sleep(_: Backend) void {
}

pub fn nanoTime(_: Backend) i128 {
    // XXX: We can abstract this in zitrus
    const tick: f32 = @floatFromInt(horizon.getSystemTick());
    return @intFromFloat(@trunc((tick / 268000000) * 1000000000));
}

pub fn clipboardText(_: *Backend) ![]const u8 {
    return &.{};
}

pub fn clipboardTextSet(_: *Backend, text: []const u8) !void {
    _ = text;
}

pub fn openURL(_: *Backend, url: []const u8, _: bool) !void {
    _ = url;
}

pub fn backend(bd: *Backend) dvui.Backend {
    return dvui.Backend.init(bd);
}

export fn dvui_c_panic(msg: [*:0]const u8) noreturn {
    @panic(std.mem.span(msg));
}

export fn dvui_c_sqrt(x: f64) f64 {
    return @sqrt(x);
}

export fn dvui_c_pow(x: f64, y: f64) f64 {
    return @exp(@log(x) * y);
}

export fn dvui_c_floor(x: f64) f64 {
    return @floor(x);
}

export fn dvui_c_ceil(x: f64) f64 {
    return @ceil(x);
}

export fn dvui_c_fmod(x: f64, y: f64) f64 {
    return @mod(x, y);
}

export fn dvui_c_cos(x: f64) f64 {
    return @cos(x);
}

export fn dvui_c_acos(x: f64) f64 {
    return std.math.acos(x);
}

export fn dvui_c_fabs(x: f64) f64 {
    return @abs(x);
}

export fn dvui_c_strlen(x: [*c]const u8) usize {
    return std.mem.len(x);
}

const builtin = @import("builtin");
export fn dvui_c_alloc(size: usize) ?*anyopaque {
    const buffer = alloc.alignedAlloc(u8, .@"8", size + 8) catch {
        //log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeInt(u64, buffer[0..@sizeOf(u64)], buffer.len, builtin.cpu.arch.endian());
    //log.debug("dvui_c_alloc {*} {d}", .{ buffer.ptr + 8, size });
    return buffer.ptr + 8;
}

pub export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(8) u8, @ptrCast(@alignCast(ptr orelse return))) - 8;
    const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());
    //log.debug("dvui_c_free {?*} {d}", .{ ptr, len - 8 });

    alloc.free(buffer[0..@intCast(len)]);
}

export fn dvui_c_realloc_sized(ptr: ?*anyopaque, oldsize: usize, newsize: usize) ?*anyopaque {
    //_ = oldsize;
    //log.debug("dvui_c_realloc_sized {d} {d}", .{ oldsize, newsize });

    if (ptr == null) {
        return dvui_c_alloc(newsize);
    }

    //const buffer = @as([*]u8, @ptrCast(ptr.?)) - 8;
    //const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());

    //const slice = buffer[0..@intCast(len)];
    //log.debug("dvui_c_realloc_sized buffer {*} {d}", .{ ptr, len });

    //_ = gpa.resize(slice, newsize + 16);
    const newptr = dvui_c_alloc(newsize);
    const newbuf = @as([*]u8, @ptrCast(newptr));
    @memcpy(newbuf[0..oldsize], @as([*]u8, @ptrCast(ptr))[0..oldsize]);
    dvui_c_free(ptr);
    return newptr;

    //std.mem.writeInt(usize, slice[0..@sizeOf(usize)], slice.len, builtin.cpu.arch.endian());
    //return slice.ptr + 16;
}

const Backend = @This();

const log = std.log.scoped(.@"dvui-zitrus");

const std = @import("std");
const dvui = @import("dvui");
const zitrus = @import("zitrus");

const pica = zitrus.hardware.pica;
const mango = zitrus.mango;

const horizon = zitrus.horizon;
