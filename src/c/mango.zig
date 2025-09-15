//! Mango C API

pub const MgResult = enum(i32) {
    validation_failed = -3,
    out_of_memory = -2,
    unknown = -1,

    success = 0,
    timeout = 1,
};

pub export fn mgDestroyDevice(device: mango.Device, allocator: *const Allocator) void {
    return device.destroy(allocator.allocator());
}

pub export fn mgGetDeviceQueue(device: mango.Device, family: mango.QueueFamily, queue: *mango.Queue) MgResult {
    queue.* = device.getQueue(family);
    return .success;
}

pub export fn mgQueueCopyBuffer(queue: mango.Queue, info: *const mango.CopyBufferInfo) MgResult {
    queue.copyBuffer(info.*) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgQueueCopyBufferToImage(queue: mango.Queue, info: *const mango.CopyBufferToImageInfo) MgResult {
    queue.copyBufferToImage(info.*) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgQueueBlitImage(queue: mango.Queue, info: *const mango.BlitImageInfo) MgResult {
    queue.blitImage(info.*) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgQueueSubmit(queue: mango.Queue, info: *const mango.SubmitInfo) MgResult {
    queue.submit(info.*) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgQueuePresent(queue: mango.Queue, info: *const mango.PresentInfo) MgResult {
    queue.present(info.*) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgAllocateMemory(device: mango.Device, allocate_info: *const mango.MemoryAllocateInfo, allocator: *const Allocator, memory: *mango.DeviceMemory) MgResult {
    memory.* = device.allocateMemory(allocate_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgFreeMemory(device: mango.Device, memory: mango.DeviceMemory, allocator: *const Allocator) void {
    return device.freeMemory(memory, allocator.allocator());
}

pub export fn mgMapMemory(device: mango.Device, memory: mango.DeviceMemory, offset: u32, size: mango.DeviceSize, data: *[*]u8) MgResult {
    data.* = (device.mapMemory(memory, offset, size) catch |err| switch (err) {}).ptr;

    return .success;
}

pub export fn mgUnmapMemory(device: mango.Device, memory: mango.DeviceMemory) void {
    return device.unmapMemory(memory);
}

pub export fn mgFlushMappedMemoryRanges(device: mango.Device, range_count: usize, ranges: [*]const mango.MappedMemoryRange) MgResult {
    device.flushMappedMemoryRanges(ranges[0..range_count]) catch |err| switch (err) {};

    return .success;
}

pub export fn mgCreateSemaphore(device: mango.Device, create_info: *const mango.SemaphoreCreateInfo, allocator: *const Allocator, semaphore: *mango.Semaphore) MgResult {
    semaphore.* = device.createSemaphore(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroySemaphore(device: mango.Device, semaphore: mango.Semaphore, allocator: *const Allocator) void {
    return device.destroySemaphore(semaphore, allocator.allocator());
}

pub export fn mgCreateCommandPool(device: mango.Device, create_info: *const mango.CommandPoolCreateInfo, allocator: *const Allocator, command_pool: *mango.CommandPool) MgResult {
    command_pool.* = device.createCommandPool(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroyCommandPool(device: mango.Device, command_pool: mango.CommandPool, allocator: *const Allocator) void {
    return device.destroyCommandPool(command_pool, allocator.allocator());
}

pub export fn mgResetCommandPool(device: mango.Device, command_pool: mango.CommandPool) void {
    return device.resetCommandPool(command_pool);
}

pub export fn mgTrimCommandPool(device: mango.Device, command_pool: mango.CommandPool) void {
    return device.trimCommandPool(command_pool);
}

pub export fn mgAllocateCommandBuffers(device: mango.Device, allocate_info: mango.CommandBufferAllocateInfo, buffers: [*]mango.CommandBuffer) MgResult {
    device.allocateCommandBuffers(allocate_info, buffers[0..allocate_info.command_buffer_count]) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgFreeCommandBuffers(device: mango.Device, command_pool: mango.CommandPool, buffers: [*]const mango.CommandBuffer, buffers_len: usize) void {
    return device.freeCommandBuffers(command_pool, buffers[0..buffers_len]);
}

pub export fn mgCreateBuffer(device: mango.Device, create_info: *const mango.BufferCreateInfo, allocator: *const Allocator, buffer: *mango.Buffer) MgResult {
    buffer.* = device.createBuffer(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroyBuffer(device: mango.Device, buffer: mango.Buffer, allocator: *const Allocator) void {
    return device.destroyBuffer(buffer, allocator.allocator());
}

pub export fn mgBindBufferMemory(device: mango.Device, buffer: mango.Buffer, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) MgResult {
    device.bindBufferMemory(buffer, memory, memory_offset) catch |err| switch (err) {};

    return .success;
}

pub export fn mgCreateImage(device: mango.Device, create_info: *const mango.ImageCreateInfo, allocator: *const Allocator, image: *mango.Image) MgResult {
    image.* = device.createImage(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroyImage(device: mango.Device, image: mango.Image, allocator: *const Allocator) void {
    return device.destroyImage(image, allocator.allocator());
}

pub export fn mgBindImageMemory(device: mango.Device, image: mango.Image, memory: mango.DeviceMemory, memory_offset: mango.DeviceSize) MgResult {
    device.bindImageMemory(image, memory, memory_offset) catch |err| switch (err) {};

    return .success;
}

pub export fn mgCreateImageView(device: mango.Device, create_info: *const mango.ImageViewCreateInfo, allocator: *const Allocator, image_view: *mango.ImageView) MgResult {
    image_view.* = device.createImageView(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroyImageView(device: mango.Device, image_view: mango.ImageView, allocator: *const Allocator) void {
    return device.destroyImageView(image_view, allocator.allocator());
}

pub export fn mgCreateSampler(device: mango.Device, create_info: *const mango.SamplerCreateInfo, allocator: *const Allocator, sampler: *mango.Sampler) MgResult {
    sampler.* = device.createSampler(create_info.*, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgDestroySampler(device: mango.Device, sampler: mango.Sampler, allocator: *const Allocator) void {
    return device.destroySampler(sampler, allocator.allocator());
}

pub export fn mgCreateGraphicsPipeline(device: mango.Device, create_info: mango.GraphicsPipelineCreateInfo, allocator: *const Allocator, pipeline: *mango.Pipeline) MgResult {
    pipeline.* = device.createGraphicsPipeline(create_info, allocator.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
        error.ValidationFailed => return .validation_failed,
    };

    return .success;
}

pub export fn mgDestroyPipeline(device: mango.Device, pipeline: mango.Pipeline, allocator: *const Allocator) void {
    return device.destroyPipeline(pipeline, allocator.allocator());
}

pub export fn mgCreateSwapchain(device: mango.Device, create_info: mango.SwapchainCreateInfo, allocator: *const Allocator, swapchain: *mango.Swapchain) MgResult {
    swapchain.* = device.createSwapchain(create_info, allocator.allocator()) catch |err| switch (err) {};

    return .success;
}

pub export fn mgDestroySwapchain(device: mango.Device, swapchain: mango.Swapchain, allocator: *const Allocator) void {
    return device.destroySwapchain(swapchain, allocator.allocator());
}

pub export fn mgGetSwapchainImages(device: mango.Device, swapchain: mango.Swapchain, image_count: *usize, images: ?[*]mango.Image) MgResult {
    if (images) |non_null_images| {
        _ = device.getSwapchainImages(swapchain, non_null_images[0..image_count.*]);
        return .success;
    }

    image_count.* = device.getSwapchainImages(swapchain, &.{});
    return .success;
}

pub export fn mgAcquireNextImage(device: mango.Device, swapchain: mango.Swapchain, timeout: i64, next_image: *u8) MgResult {
    next_image.* = device.acquireNextImage(swapchain, timeout) catch |err| switch (err) {
        error.Timeout => return .timeout,
    };

    return .success;
}

pub export fn mgSignalSemaphore(device: mango.Device, signal_info: *const mango.SemaphoreOperation) MgResult {
    device.signalSemaphore(signal_info.*) catch |err| switch (err) {};

    return .success;
}

pub export fn mgWaitSemaphore(device: mango.Device, wait_info: *const mango.SemaphoreOperation, timeout: i64) MgResult {
    device.waitSemaphore(wait_info.*, timeout) catch |err| switch (err) {
        error.Timeout => return .timeout,
    };
    return .success;
}

pub export fn mgDeviceWaitIdle(device: mango.Device) MgResult {
    device.waitIdle() catch |err| switch (err) {};

    return .success;
}

pub export fn mgBeginCommandBuffer(cmd: mango.CommandBuffer) MgResult {
    cmd.begin() catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
    };

    return .success;
}

pub export fn mgEndCommandBuffer(cmd: mango.CommandBuffer) MgResult {
    cmd.end() catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
        else => return .unknown,
    };

    return .success;
}

pub export fn mgResetCommandBuffer(cmd: mango.CommandBuffer) void {
    return cmd.reset();
}

pub export fn mgCmdBindPipeline(cmd: mango.CommandBuffer, bind_point: mango.PipelineBindPoint, pipeline: mango.Pipeline) void {
    return cmd.bindPipeline(bind_point, pipeline);
}

pub export fn mgCmdBindVertexBuffers(cmd: mango.CommandBuffer, first_binding: u32, binding_count: u32, buffers: [*]const mango.Buffer, offsets: [*]const u32) void {
    return cmd.bindVertexBuffers(first_binding, binding_count, buffers, offsets);
}

pub export fn mgCmdBindIndexBuffer(cmd: mango.CommandBuffer, buffer: mango.Buffer, offset: u32, index_type: mango.IndexType) void {
    return cmd.bindIndexBuffer(buffer, offset, index_type);
}

pub export fn mgCmdBindFloatUniforms(cmd: mango.CommandBuffer, stage: mango.ShaderStage, first_uniform: u32, uniforms_count: u32, uniforms: [*]const [4]f32) void {
    return cmd.bindFloatUniforms(stage, first_uniform, uniforms[0..uniforms_count]);
}

pub export fn mgCmdBindCombinedImageSamplers(cmd: mango.CommandBuffer, first_combined: u32, combined_image_samplers_count: u32, combined_image_samplers: [*]const mango.CombinedImageSampler) void {
    return cmd.bindCombinedImageSamplers(first_combined, combined_image_samplers[0..combined_image_samplers_count]);
}

pub export fn mgCmdBeginRendering(cmd: mango.CommandBuffer, rendering_info: mango.RenderingInfo) void {
    return cmd.beginRendering(rendering_info);
}

pub export fn mgCmdEndRendering(cmd: mango.CommandBuffer) void {
    return cmd.endRendering();
}

pub export fn mgCmdDraw(cmd: mango.CommandBuffer, vertex_count: u32, first_vertex: u32) void {
    return cmd.draw(vertex_count, first_vertex);
}

pub export fn mgCmdDrawMulti(cmd: mango.CommandBuffer, draw_count: u32, vertex_info: [*]const mango.MultiDrawInfo, stride: u32) void {
    return cmd.drawMulti(draw_count, vertex_info, stride);
}

pub export fn mgCmdDrawIndexed(cmd: mango.CommandBuffer, index_count: u32, first_index: u32, vertex_offset: i32) void {
    return cmd.drawIndexed(index_count, first_index, vertex_offset);
}

pub export fn mgCmdDrawMultiIndexed(cmd: mango.CommandBuffer, draw_count: u32, index_info: [*]const mango.MultiDrawIndexedInfo, stride: u32) void {
    return cmd.drawMultiIndexed(draw_count, index_info, stride);
}

pub export fn mgCmdSetDepthMode(cmd: mango.CommandBuffer, mode: mango.DepthMode) void {
    return cmd.setDepthMode(mode);
}

pub export fn mgCmdSetCullMode(cmd: mango.CommandBuffer, cull_mode: mango.CullMode) void {
    return cmd.setCullMode(cull_mode);
}

pub export fn mgCmdSetFrontFace(cmd: mango.CommandBuffer, front_face: mango.FrontFace) void {
    return cmd.setFrontFace(front_face);
}

pub export fn mgCmdSetPrimitiveTopology(cmd: mango.CommandBuffer, primitive_topology: mango.PrimitiveTopology) void {
    return cmd.setPrimitiveTopology(primitive_topology);
}

pub export fn mgCmdSetViewport(cmd: mango.CommandBuffer, viewport: *const mango.Viewport) void {
    return cmd.setViewport(viewport.*);
}

pub export fn mgCmdSetScissor(cmd: mango.CommandBuffer, scissor: *const mango.Scissor) void {
    return cmd.setScissor(scissor.*);
}

pub export fn mgCmdSetTextureCombiners(cmd: mango.CommandBuffer, texture_combiners_len: u32, texture_combiners: [*]const mango.TextureCombiner, texture_combiner_buffer_sources_len: u32, texture_combiner_buffer_sources: [*]const mango.TextureCombiner.BufferSources) void {
    return cmd.setTextureCombiners(texture_combiners_len, texture_combiners, texture_combiner_buffer_sources_len, texture_combiner_buffer_sources);
}

pub export fn mgCmdSetBlendEquation(cmd: mango.CommandBuffer, blend_equation: *const mango.ColorBlendEquation) void {
    return cmd.setBlendEquation(blend_equation.*);
}

pub export fn mgCmdSetColorWriteMask(cmd: mango.CommandBuffer, write_mask: mango.ColorComponentFlags) void {
    return cmd.setColorWriteMask(write_mask);
}

pub export fn mgCmdSetDepthTestEnable(cmd: mango.CommandBuffer, enable: bool) void {
    return cmd.setDepthTestEnable(enable);
}

pub export fn mgCmdSetDepthCompareOp(cmd: mango.CommandBuffer, op: mango.CompareOperation) void {
    return cmd.setDepthCompareOp(op);
}

pub export fn mgCmdSetDepthWriteEnable(cmd: mango.CommandBuffer, enable: bool) void {
    return cmd.setDepthWriteEnable(enable);
}

pub export fn mgCmdSetLogicOpEnable(cmd: mango.CommandBuffer, enable: bool) void {
    return cmd.setLogicOpEnable(enable);
}

pub export fn mgCmdSetLogicOp(cmd: mango.CommandBuffer, logic_op: mango.LogicOperation) void {
    return cmd.setLogicOp(logic_op);
}

pub export fn mgCmdSetAlphaTestEnable(cmd: mango.CommandBuffer, enable: bool) void {
    return cmd.setAlphaTestEnable(enable);
}

pub export fn mgCmdSetAlphaTestCompareOp(cmd: mango.CommandBuffer, compare_op: mango.CompareOperation) void {
    return cmd.setAlphaTestCompareOp(compare_op);
}

pub export fn mgCmdSetAlphaTestReference(cmd: mango.CommandBuffer, reference: u8) void {
    return cmd.setAlphaTestReference(reference);
}

pub export fn mgCmdSetStencilEnable(cmd: mango.CommandBuffer, enable: bool) void {
    return cmd.setStencilEnable(enable);
}

pub export fn mgCmdSetStencilOp(cmd: mango.CommandBuffer, fail_op: mango.StencilOperation, pass_op: mango.StencilOperation, depth_fail_op: mango.StencilOperation, op: mango.CompareOperation) void {
    return cmd.setStencilOp(fail_op, pass_op, depth_fail_op, op);
}

pub export fn mgCmdSetStencilCompareMask(cmd: mango.CommandBuffer, compare_mask: u8) void {
    return cmd.setStencilCompareMask(compare_mask);
}

pub export fn mgCmdSetStencilWriteMask(cmd: mango.CommandBuffer, write_mask: u8) void {
    return cmd.setStencilWriteMask(write_mask);
}

pub export fn mgCmdSetStencilReference(cmd: mango.CommandBuffer, reference: u8) void {
    return cmd.setStencilReference(reference);
}

pub export fn mgCmdSetTextureEnable(cmd: mango.CommandBuffer, enable: *const [4]bool) void {
    return cmd.setTextureEnable(enable);
}

pub export fn mgCmdSetTextureCoordinates(cmd: mango.CommandBuffer, texture_2_coordinates: mango.TextureCoordinateSource, texture_3_coordinates: mango.TextureCoordinateSource) void {
    return cmd.setTextureCoordinates(texture_2_coordinates, texture_3_coordinates);
}

pub const Allocator = extern struct {
    pub const vtable: *const std.mem.Allocator.VTable = &.{
        .alloc = wrapAlloc,
        .resize = wrapResize,
        .remap = wrapRemap,
        .free = wrapFree,
    };

    /// Return a pointer to `len` bytes with specified `alignment`, or return
    /// `null` indicating the allocation failed.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    alloc: *const fn (*anyopaque, len: usize, alignment: usize, ret_addr: usize) callconv(.c) ?[*]u8,

    /// Attempt to expand or shrink memory in place.
    ///
    /// `memory.len` must equal the length requested from the most recent
    /// successful call to `alloc`, `resize`, or `remap`. `alignment` must
    /// equal the same value that was passed as the `alignment` parameter to
    /// the original `alloc` call.
    ///
    /// A result of `true` indicates the resize was successful and the
    /// allocation now has the same address but a size of `new_len`. `false`
    /// indicates the resize could not be completed without moving the
    /// allocation to a different address.
    ///
    /// `new_len` must be greater than zero.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    resize: *const fn (*anyopaque, memory_ptr: [*]u8, memory_len: usize, alignment: usize, new_len: usize, ret_addr: usize) callconv(.c) bool,

    /// Free and invalidate a region of memory.
    ///
    /// `memory.len` must equal the length requested from the most recent
    /// successful call to `alloc`, `resize`, or `remap`. `alignment` must
    /// equal the same value that was passed as the `alignment` parameter to
    /// the original `alloc` call.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    free: *const fn (*anyopaque, memory_ptr: [*]u8, memory_len: usize, alignment: usize, ret_addr: usize) callconv(.c) void,

    pub fn allocator(ally: *const Allocator) std.mem.Allocator {
        return .{
            .ptr = @constCast(ally),
            .vtable = vtable,
        };
    }

    fn wrapAlloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const ally: *const Allocator = @ptrCast(@alignCast(ptr));
        return ally.alloc(ptr, len, @intFromEnum(alignment), ret_addr);
    }

    fn wrapResize(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const ally: *const Allocator = @ptrCast(@alignCast(ptr));
        return ally.resize(ptr, memory.ptr, memory.len, @intFromEnum(alignment), new_len, ret_addr);
    }

    fn wrapRemap(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const ally: *const Allocator = @ptrCast(@alignCast(ptr));

        return if (ally.resize(ptr, memory.ptr, memory.len, @intFromEnum(alignment), new_len, ret_addr))
            memory.ptr
        else
            null;
    }

    fn wrapFree(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const ally: *const Allocator = @ptrCast(@alignCast(ptr));
        return ally.free(ptr, memory.ptr, memory.len, @intFromEnum(alignment), ret_addr);
    }
};

const zitrus = @import("zitrus");
const mango = zitrus.mango;

const std = @import("std");
