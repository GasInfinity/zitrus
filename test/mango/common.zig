pub const TmpContext = struct {
    device: mango.Device,

    pub fn init() !TmpContext {
        const dev = try mango.createHorizonBackedDevice(.{
            .gsp = htesting.gsp,
            .arbiter = htesting.arbiter,
        }, testing.allocator);
        errdefer dev.destroy();

        return .{
            .device = dev,
        };
    }

    pub fn cleanup(ctx: *TmpContext) void {
        ctx.device.destroy();
    }

    pub fn transfer(ctx: *TmpContext, size: u32) !TransferTmpContext {
        return try .init(ctx, size);
    }

    pub fn fill(ctx: *TmpContext, size: u32) !FillTmpContext {
        return try .init(ctx, size);
    }

    pub fn render(ctx: *TmpContext, width: u16, height: u16, color: mango.Format, depth: mango.Format) !RenderingTmpContext {
        return try .init(ctx, width, height, color, depth);
    }
};

pub const TransferTmpContext = struct {
    base: *TmpContext,
    sema: mango.Semaphore,
    sema_current: u64,
    a: mango.DeviceMemory,
    b: mango.DeviceMemory,

    pub fn init(ctx: *TmpContext, size: u32) !TransferTmpContext {
        const dev = ctx.device;
        const sema = try dev.createSemaphore(.initial_zero, null);
        errdefer dev.destroySemaphore(sema, null);

        const a = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(size),
        }, null);
        errdefer dev.freeMemory(a, null);

        const b = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(size),
        }, null);
        errdefer dev.freeMemory(b, null);

        return .{
            .base = ctx,
            .sema = sema,
            .sema_current = 0,
            .a = a,
            .b = b,
        };
    }

    pub fn cleanup(ctx: *TransferTmpContext) void {
        const dev = ctx.base.device;
        dev.freeMemory(ctx.b, null);
        dev.freeMemory(ctx.a, null);
        dev.destroySemaphore(ctx.sema, null);
        ctx.* = undefined;
    }

    pub fn copySource(ctx: *TransferTmpContext, offset: u32, data: []const u8) !void {
        const dev = ctx.base.device;
        const mapped = try dev.mapMemory(ctx.a, .size(offset), .size(data.len)); 
        defer dev.unmapMemory(ctx.a);

        @memcpy(mapped, data);
        try dev.flushMappedMemoryRanges(&.{
            .{
                .memory = ctx.a,
                .offset = .size(offset),
                .size = .size(data.len),
            }
        });
    }

    pub fn bufferToBuffer(ctx: *TransferTmpContext, offset: usize, len: usize) !void {
        const dev = ctx.base.device;
        const a_buf = try dev.createBuffer(.{
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
            },
            .size = .size(len),
        }, null);
        defer dev.destroyBuffer(a_buf, null);
        try dev.bindBufferMemory(a_buf, ctx.a, .size(0));

        const b_buf = try dev.createBuffer(.{
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
            },
            .size = .size(len),
        }, null);
        defer dev.destroyBuffer(b_buf, null);
        try dev.bindBufferMemory(b_buf, ctx.b, .size(0));
        const queue = ctx.base.device.getQueue(.transfer);

        try queue.copyBuffer(.{
            .wait_semaphore = &.init(ctx.sema, ctx.sema_current),
            .src_buffer = a_buf,
            .src_offset = .size(offset),
            .dst_buffer = b_buf,
            .dst_offset = .size(offset),
            .size = .size(len),
            .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
        });

        ctx.sema_current += 1;
        try dev.waitSemaphores(.init(&.{ctx.sema}, &.{ctx.sema_current}), std.math.maxInt(u64));
    }

    pub fn result(ctx: *TransferTmpContext, offset: u32, len: u32) ![]const u8 {
        const dev = ctx.base.device;
        const mapped = try dev.mapMemory(ctx.b, .size(offset), .size(len));
        try dev.invalidateMappedMemoryRanges(&.{
            .{
                .memory = ctx.b,
                .offset = .size(0),
                .size = .whole,
            }
        });

        return mapped;
    }

    pub fn cleanupResult(ctx: *TransferTmpContext) void {
        ctx.base.device.unmapMemory(ctx.b);
    }
};

pub const FillTmpContext = struct {
    base: *TmpContext,
    sema: mango.Semaphore,
    sema_current: u64,
    filling: mango.DeviceMemory,
    host_visible: mango.DeviceMemory,

    pub fn init(ctx: *TmpContext, size: u32) !FillTmpContext {
        const dev = ctx.device;
        const sema = try dev.createSemaphore(.initial_zero, null);
        errdefer dev.destroySemaphore(sema, null);

        const filling = try dev.allocateMemory(.{
            .memory_type = .vram_a,
            .allocation_size = .size(size),
        }, null);
        errdefer dev.freeMemory(filling, null);

        const host_visible = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(size),
        }, null);
        errdefer dev.freeMemory(host_visible, null);

        return .{
            .base = ctx,
            .sema = sema,
            .sema_current = 0,
            .filling = filling,
            .host_visible = host_visible,
        };
    }

    pub fn cleanup(ctx: *FillTmpContext) void {
        const dev = ctx.base.device;
        dev.freeMemory(ctx.host_visible, null);
        dev.freeMemory(ctx.filling, null);
        dev.destroySemaphore(ctx.sema, null);
        ctx.* = undefined;
    }

    pub fn fillBuffer(ctx: *FillTmpContext, offset: u32, len: u32, pattern_type: mango.FillPatternType, pattern: u32) !void {
        const dev = ctx.base.device;
        const filling_buf = try dev.createBuffer(.{
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
            },
            .size = .size(len),
        }, null);
        defer dev.destroyBuffer(filling_buf, null);
        try dev.bindBufferMemory(filling_buf, ctx.filling, .size(0));

        const host_visible_buf = try dev.createBuffer(.{
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
            },
            .size = .size(len),
        }, null);
        defer dev.destroyBuffer(host_visible_buf, null);
        try dev.bindBufferMemory(host_visible_buf, ctx.host_visible, .size(0));

        const fill = ctx.base.device.getQueue(.fill);
        const transfer = ctx.base.device.getQueue(.transfer);

        try fill.fillBuffer(.{
            .wait_semaphore = &.init(ctx.sema, ctx.sema_current), 
            .buffer = filling_buf,
            .offset = .size(offset),
            .size = .size(len),
            .pattern_type = pattern_type,
            .pattern = pattern,
            .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
        });

        try transfer.copyBuffer(.{
            .wait_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
            .src_buffer = filling_buf,
            .src_offset = .size(offset),
            .dst_buffer = host_visible_buf,
            .dst_offset = .size(offset),
            .size = .size(len),
            .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 2),
        });

        ctx.sema_current += 2;
        try dev.waitSemaphores(.init(&.{ctx.sema}, &.{ctx.sema_current}), std.math.maxInt(u64));
    }

    pub fn result(ctx: *FillTmpContext, offset: u32, len: u32) ![]const u8 {
        const dev = ctx.base.device;
        const mapped = try dev.mapMemory(ctx.host_visible, .size(offset), .size(len));
        errdefer dev.unmapMemory(ctx.host_visible);

        try dev.invalidateMappedMemoryRanges(&.{
            .{
                .memory = ctx.host_visible,
                .offset = .size(0),
                .size = .whole,
            }
        });

        return mapped;
    }

    pub fn cleanupResult(ctx: *FillTmpContext) void {
        ctx.base.device.unmapMemory(ctx.host_visible);
    }
};

pub const RenderingTmpContext = struct {
    base: *TmpContext,
    sema: mango.Semaphore,
    sema_current: u64 = 0,
    
    width: u16,
    height: u16,

    color_size: u32,
    depth_size: u32,

    tiled: mango.DeviceMemory,
    tiled_depth: mango.DeviceMemory,
    linear: mango.DeviceMemory,
    quad: mango.DeviceMemory,

    color_image: mango.Image,
    depth_image: mango.Image,
    color_image_view: mango.ImageView,
    depth_image_view: mango.ImageView,

    linear_color_image: mango.Image,
    linear_depth_image: mango.Image,
    quad_vtx: mango.Buffer,
    quad_idx: mango.Buffer,

    pos_shader: mango.Shader,
    pos_vertex_input: mango.VertexInputLayout,

    pool: mango.CommandPool,
    cmd: mango.CommandBuffer,

    pub fn init(ctx: *TmpContext, width: u16, height: u16, color: mango.Format, depth: mango.Format) !RenderingTmpContext {
        const dev = ctx.device;
        const sema = try dev.createSemaphore(.initial_zero, null);
        errdefer dev.destroySemaphore(sema, null);

        // NOTE: technically apps shouldn't use this function but we can be lazy
        const color_size = if (color != .undefined) color.scale(@as(u32, width) * height) else 0;
        const depth_size = if (depth != .undefined) depth.scale(@as(u32, width) * height) else 0;

        const tiled: mango.DeviceMemory = if (color_size > 0) try dev.allocateMemory(.{
            .memory_type = .vram_a,
            .allocation_size = .size(color_size),
        }, null) else .null;
        errdefer if (color_size > 0) dev.freeMemory(tiled, null);

        const tiled_depth: mango.DeviceMemory = if (depth_size > 0) try dev.allocateMemory(.{
            .memory_type = .vram_b,
            .allocation_size = .size(depth_size),
        }, null) else .null;
        errdefer if (depth_size > 0) dev.freeMemory(tiled_depth, null);

        const linear = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(@max(color_size, depth_size)),
        }, null);
        errdefer dev.freeMemory(linear, null);

        const quad = try dev.allocateMemory(.{
            .memory_type = .fcram_cached,
            .allocation_size = .size(@sizeOf(f32) * 4 + 6),
        }, null);
        errdefer dev.freeMemory(quad, null);

        const quad_vtx = try dev.createBuffer(.{
            .usage = .{
                .vertex_buffer = true,
            },
            .size = .size(@sizeOf([2]f32) * 4),
        }, null);
        try dev.bindBufferMemory(quad_vtx, quad, .size(0));
        errdefer dev.destroyBuffer(quad_vtx, null);

        const quad_idx = try dev.createBuffer(.{
            .usage = .{
                .index_buffer = true,
            },
            .size = .size(6),
        }, null);
        try dev.bindBufferMemory(quad_idx, quad, .size(@sizeOf([2]f32) * 4));
        errdefer dev.destroyBuffer(quad_idx, null);

        {
            const mapped = try dev.mapMemory(quad, .size(0), .whole);
            defer dev.unmapMemory(quad);

            const vtx: *[4][2]f32 = @alignCast(@ptrCast(mapped[0..@sizeOf([4][2]f32)]));
            const idx: *[6]u8 = @ptrCast(mapped[@sizeOf([4][2]f32)..]);

            vtx.* = .{
                .{ -1, -1 },
                .{ 1, -1 },
                .{ -1, 1 },
                .{ 1, 1 },
            };

            idx.* = .{ 0, 1, 2, 2, 1, 3 };

            try dev.flushMappedMemoryRanges(&.{
                .{
                    .memory = quad,
                    .offset = .size(0),
                    .size = .whole,
                }
            });
        }

        const color_image: mango.Image = if (tiled != .null) try dev.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .optimal,
            .usage = .{
                .transfer_src = true,
                .color_attachment = true,
            },
            .extent = .{
                .width = width,
                .height = height,
            },
            .format = color,
            .mip_levels = .@"1",
            .array_layers = .@"1", 
        }, null) else .null;
        if (color_image != .null) try dev.bindImageMemory(color_image, tiled, .size(0));
        errdefer if (color_image != .null) dev.destroyImage(color_image, null);

        const color_image_view: mango.ImageView = if (tiled != .null) try dev.createImageView(.{
            .type = .@"2d",
            .format = color,
            .image = color_image,
            .subresource_range = .full,
        }, null) else .null;
        errdefer if (color_image_view != .null) dev.destroyImageView(color_image_view, null);

        const depth_image: mango.Image = if (tiled_depth != .null) try dev.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .optimal,
            .usage = .{
                .transfer_src = true,
                .depth_stencil_attachment = true,
            },
            .extent = .{
                .width = width,
                .height = height,
            },
            .format = depth,
            .mip_levels = .@"1",
            .array_layers = .@"1", 
        }, null) else .null;
        if (depth_image != .null) try dev.bindImageMemory(depth_image, tiled_depth, .size(0));
        errdefer if (depth_image != .null) dev.destroyImage(depth_image, null);

        const depth_image_view: mango.ImageView = if (tiled_depth != .null) try dev.createImageView(.{
            .type = .@"2d",
            .format = depth,
            .image = depth_image,
            .subresource_range = .full,
        }, null) else .null;
        errdefer if (depth_image_view != .null) dev.destroyImageView(depth_image_view, null);

        const linear_color_image: mango.Image = if (color_size > 0) try dev.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .linear,
            .usage = .{
                .transfer_dst = true,
            },
            .extent = .{
                .width = width,
                .height = height,
            },
            .format = color,
            .mip_levels = .@"1",
            .array_layers = .@"1", 
        }, null) else .null;
        if (linear_color_image != .null) try dev.bindImageMemory(linear_color_image, linear, .size(0));
        errdefer if (linear_color_image != .null) dev.destroyImage(linear_color_image, null);

        const linear_depth_image: mango.Image = if (depth_size > 0) try dev.createImage(.{
            .flags = .{},
            .type = .@"2d",
            .tiling = .linear,
            .usage = .{
                .transfer_dst = true,
            },
            .extent = .{
                .width = width,
                .height = height,
            },
            .format = depth,
            .mip_levels = .@"1",
            .array_layers = .@"1", 
        }, null) else .null;
        if (linear_depth_image != .null) try dev.bindImageMemory(linear_depth_image, linear, .size(0));
        errdefer if (linear_depth_image != .null) dev.destroyImage(linear_depth_image, null);

        const pos_shader = try dev.createShader(.init(.psh, @embedFile("pos.psm"), "main"), null);
        errdefer dev.destroyShader(pos_shader, null);

        const pos_layout = try dev.createVertexInputLayout(.init(&.{
            .{
                .stride = @sizeOf([2]f32),
            }
        }, &.{
            .{
                .location = .v0,
                .binding = .@"0",
                .offset = 0,
                .format = .r32g32_sfloat,
            }
        }, &.{}), null);
        errdefer dev.destroyVertexInputLayout(pos_layout, null);

        const pool = try dev.createCommandPool(.no_preheat, null);
        errdefer dev.destroyCommandPool(pool, null);

        const cmd = blk: {
            var cmd: [1]mango.CommandBuffer = undefined;
            try dev.allocateCommandBuffers(.{
                .pool = pool,
                .command_buffer_count = 1,
            }, &cmd);
            break :blk cmd[0];
        };
        errdefer dev.freeCommandBuffers(pool, &.{cmd});

        return .{
            .base = ctx,
            .sema = sema,
            .sema_current = 0,

            .width = width,
            .height = height,

            .color_size = color_size,
            .depth_size = depth_size,

            .tiled = tiled,
            .tiled_depth = tiled_depth,
            .linear = linear,
            .quad = quad,

            .quad_vtx = quad_vtx,
            .quad_idx = quad_idx,

            .color_image = color_image,
            .depth_image = depth_image,
            .color_image_view = color_image_view,
            .depth_image_view = depth_image_view,

            .linear_color_image = linear_color_image,
            .linear_depth_image = linear_depth_image,

            .pos_shader = pos_shader,
            .pos_vertex_input = pos_layout,

            .pool = pool,
            .cmd = cmd,
        };
    }

    pub fn cleanup(ctx: *RenderingTmpContext) void {
        const dev = ctx.base.device;
        dev.freeCommandBuffers(ctx.pool, &.{ctx.cmd});
        dev.destroyCommandPool(ctx.pool, null);

        dev.destroyVertexInputLayout(ctx.pos_vertex_input, null);
        dev.destroyShader(ctx.pos_shader, null);

        if (ctx.linear_depth_image != .null) dev.destroyImage(ctx.linear_depth_image, null);
        if (ctx.linear_color_image != .null) dev.destroyImage(ctx.linear_color_image, null);
        if (ctx.depth_image_view != .null) dev.destroyImageView(ctx.depth_image_view, null); 
        if (ctx.depth_image != .null) dev.destroyImage(ctx.depth_image, null);
        if (ctx.color_image_view != .null) dev.destroyImageView(ctx.color_image_view, null); 
        if (ctx.color_image != .null) dev.destroyImage(ctx.color_image, null);

        dev.destroyBuffer(ctx.quad_idx, null);
        dev.destroyBuffer(ctx.quad_vtx, null);

        dev.freeMemory(ctx.quad, null);
        if (ctx.linear != .null) dev.freeMemory(ctx.linear, null);
        if (ctx.tiled != .null) dev.freeMemory(ctx.tiled, null);
        if (ctx.tiled_depth != .null) dev.freeMemory(ctx.tiled_depth, null);
        dev.destroySemaphore(ctx.sema, null);
        ctx.* = undefined;
    }
    
    pub fn beginDefaultState(ctx: *RenderingTmpContext) !void {
        const dev = ctx.base.device;
        const fill = dev.getQueue(.fill); 

        if (ctx.color_image != .null) {
            try fill.clearColorImage(.{
                .wait_semaphore = &.init(ctx.sema, ctx.sema_current),
                .image = ctx.color_image,
                .color = @splat(0),
                .subresource_range = .full,
                .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
            });
            ctx.sema_current += 1;
        }

        if (ctx.depth_image != .null) {
            try fill.clearDepthStencilImage(.{
                .wait_semaphore = &.init(ctx.sema, ctx.sema_current),
                .image = ctx.depth_image,
                .depth = 1.0,
                .stencil = 0,
                .subresource_range = .full,
                .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
            });
            ctx.sema_current += 1;
        }

        const cmd = ctx.cmd;

        try cmd.begin();
        cmd.setLightingEnable(false);
        cmd.setLogicOpEnable(false);
        cmd.setAlphaTestEnable(false);
        cmd.setDepthTestEnable(false);
        cmd.setDepthWriteEnable(true);
        cmd.setDepthMode(.z_buffer);
        cmd.setDepthCompareOp(.lt);
        cmd.setDepthBias(0.0);
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
                .color_src = @splat(.constant),
                .alpha_src = @splat(.constant),
                .color_factor = @splat(.src_color),
                .alpha_factor = @splat(.src_alpha),
                .color_op = .replace,
                .alpha_op = .replace,

                .color_scale = .@"1x",
                .alpha_scale = .@"1x",

                .constant = @splat(0xFF),
            },
        }, &.{});
        cmd.bindShaders(&.{.vertex}, &.{ctx.pos_shader});
        cmd.setVertexInput(ctx.pos_vertex_input);
        
        cmd.setViewport(.{
            .rect = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = ctx.width, .height = ctx.height },
            },
            .min_depth = 0.0,
            .max_depth = 1.0,
        });
        cmd.setScissor(.inside(.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = ctx.width, .height = ctx.height },
        }));

        cmd.beginRendering(.{
            .color_attachment = ctx.color_image_view,
            .depth_stencil_attachment = ctx.depth_image_view,
        });
    }

    pub fn drawQuad(ctx: *RenderingTmpContext) void {
        const cmd = ctx.cmd;

        cmd.bindIndexBuffer(ctx.quad_idx, 0, .u8);
        cmd.bindVertexBuffersSlice(0, &.{ctx.quad_vtx}, &.{0});
        cmd.drawIndexed(6, 0, 0);
    }

    pub fn endSubmit(ctx: *RenderingTmpContext) !void {
        const dev = ctx.base.device;
        const cmd = ctx.cmd;
        cmd.endRendering();
        try cmd.end();
        
        const submit = dev.getQueue(.submit);

        try submit.submit(.{
            .wait_semaphore = &.init(ctx.sema, ctx.sema_current),
            .command_buffer = ctx.cmd,
            .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
        });

        ctx.sema_current += 1;
    }

    pub fn result(ctx: *RenderingTmpContext, depth: bool) ![]const u8 {
        const dev = ctx.base.device;
        const transfer = dev.getQueue(.transfer);

        try transfer.blitImage(.{
            .wait_semaphore = &.init(ctx.sema, ctx.sema_current),
            .src_image = if (depth) ctx.depth_image else ctx.color_image,
            .dst_image = if (depth) ctx.linear_depth_image else ctx.linear_color_image,
            .src_subresource = .full, // We only have one layer and level
            .dst_subresource = .full,
            .signal_semaphore = &.init(ctx.sema, ctx.sema_current + 1),
        });

        ctx.sema_current += 1;
        try dev.waitSemaphores(.init(&.{ctx.sema}, &.{ctx.sema_current}), std.math.maxInt(u64));

        // Now the juicy memory should be available!
        const mapped = try dev.mapMemory(ctx.linear, .size(0), .size(if (depth) ctx.depth_size else ctx.color_size));
        errdefer dev.unmapMemory(ctx.linear);

        try dev.invalidateMappedMemoryRanges(&.{
            .{
                .memory = ctx.linear,
                .offset = .size(0),
                .size = .whole,
            }
        });

        return mapped;
    }

    pub fn cleanupResult(ctx: *RenderingTmpContext) void {
        ctx.base.device.unmapMemory(ctx.linear);
    }
};

const testing = std.testing;
const horizon = zitrus.horizon;
const htesting = horizon.testing;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
