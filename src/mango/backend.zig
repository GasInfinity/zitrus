/// All index / vertex buffers provided to the gpu are relative to this address
pub const global_attribute_buffer_base: zitrus.PhysicalAddress = .fromAddress(zitrus.memory.arm11.vram_begin);

/// At most, this amount of commands can be buffered simultaneously by the driver.
/// OutOfMemory will be returned if the driver can not queue more.
pub const max_buffered_queue_items = 12;

/// It is asserted that at most, this amount of swapchain image layers are supported.
pub const max_swapchain_image_layers = 2;

/// It is asserted that at most, this amount of swapchain images are supported.
pub const max_swapchain_images = 3;

pub const max_present_queue_items = max_swapchain_images * max_swapchain_image_layers;

pub const PresentationEngine = @import("PresentationEngine.zig");

pub const Device = @import("Device.zig");
pub const Queue = @import("Queue.zig");
pub const Semaphore = @import("Semaphore.zig");
pub const DeviceMemory = @import("DeviceMemory.zig");
pub const Buffer = @import("Buffer.zig");
pub const Image = @import("Image.zig");
pub const ImageView = @import("ImageView.zig");
pub const Pipeline = @import("Pipeline.zig");
pub const CommandPool = @import("CommandPool.zig");
pub const CommandBuffer = @import("CommandBuffer.zig");
pub const Sampler = @import("Sampler.zig");
pub const Surface = @import("Surface.zig");
pub const Swapchain = @import("Swapchain.zig");

pub const GraphicsState = @import("GraphicsState.zig");
pub const RenderingState = @import("RenderingState.zig");
pub const VertexInputLayout = @import("VertexInputLayout.zig");

/// Calculates the size of a specific mip level.
pub inline fn imageLevelSize(size: usize, base_mip_level: usize) usize {
    return size >> @intCast(base_mip_level);
}

/// Calculates the offset of a specific mip level.
pub inline fn imageLevelOffset(size: usize, level_size: usize) usize {
    return @divExact((size - level_size) << 2, 3);
}

/// Calculates the image size including all mip levels of the chain.
pub fn imageLayerSize(size: usize, mip_levels: usize) usize {
    return @divExact(((size << 2) - imageLevelSize(size, (mip_levels - 1) << 1)), 3);
}

pub fn SingleProducerSingleConsumerBoundedQueue(comptime T: type, comptime capacity: u16) type {
    return struct {
        pub const Header = packed struct(u32) {
            index: u16,
            len: u16,
        };

        pub const initEmpty: SpScQueue = .{
            .header = .init(.{
                .index = 0,
                .len = 0,
            }),
            .items = undefined,
        };

        header: std.atomic.Value(Header),
        items: [capacity]T,

        pub fn pushFront(queue: *SpScQueue, item: T) !void {
            const hdr = queue.header.load(.monotonic);

            if (hdr.len == capacity) {
                // NOTE: We're returning OutOfMemory even if we're not allocating memory.
                return error.OutOfMemory;
            }

            return queue.pushFrontAssumeCapacity(item);
        }

        pub fn pushFrontAssumeCapacity(queue: *SpScQueue, item: T) void {
            const hdr = queue.header.load(.monotonic);
            std.debug.assert(hdr.len < capacity);

            const next_index: u16 = @intCast((hdr.index + hdr.len) % capacity);
            queue.items[next_index] = item;

            _ = @atomicRmw(u16, &queue.header.raw.len, .Add, 1, .release);
        }

        pub fn peekBack(queue: *SpScQueue) ?T {
            const initial_hdr = queue.header.load(.acquire);

            if (initial_hdr.len == 0) {
                return null;
            }

            return queue.items[initial_hdr.index];
        }

        pub fn popBack(queue: *SpScQueue) ?T {
            const initial_hdr = queue.header.load(.acquire);

            if (initial_hdr.len == 0) {
                return null;
            }

            defer {
                var hdr = initial_hdr;
                while (queue.header.cmpxchgWeak(hdr, .{
                    .index = if (hdr.index == (capacity - 1)) 0 else hdr.index + 1,
                    .len = hdr.len - 1,
                }, .monotonic, .monotonic) != null) {
                    hdr = queue.header.load(.monotonic);
                }
            }

            return queue.items[initial_hdr.index];
        }

        pub fn clear(queue: *SpScQueue) void {
            queue.header.store(.{
                .index = 0,
                .len = 0,
            }, .monotonic);
        }

        const SpScQueue = @This();
    };
}

const testing = std.testing;
const TestingSpScBoundedQueue = SingleProducerSingleConsumerBoundedQueue(u8, 4);

test "SingleProducerSingleConsumerBoundedQueue pushFront -> popBack correct state" {
    var bq: TestingSpScBoundedQueue = .initEmpty;

    bq.pushFrontAssumeCapacity(7);
    try testing.expect(0 == bq.header.raw.index);
    try testing.expect(1 == bq.header.raw.len);

    const should_be_7 = bq.popBack();
    try testing.expect(7 == should_be_7);

    try testing.expect(1 == bq.header.raw.index);
    try testing.expect(0 == bq.header.raw.len);
}

test "SingleProducerSingleConsumerBoundedQueue is a FIFO" {
    var bq: TestingSpScBoundedQueue = .initEmpty;

    bq.pushFrontAssumeCapacity(7);
    bq.pushFrontAssumeCapacity(8);
    bq.pushFrontAssumeCapacity(2);
    bq.pushFrontAssumeCapacity(1);

    try testing.expect(0 == bq.header.raw.index);
    try testing.expect(4 == bq.header.raw.len);

    const should_be_7 = bq.popBack();
    try testing.expect(7 == should_be_7);

    const should_be_8 = bq.popBack();
    try testing.expect(8 == should_be_8);

    const should_be_2 = bq.popBack();
    try testing.expect(2 == should_be_2);

    const should_be_1 = bq.popBack();
    try testing.expect(1 == should_be_1);

    try testing.expect(0 == bq.header.raw.index);
    try testing.expect(0 == bq.header.raw.len);
}

test imageLevelSize {
    try testing.expect(imageLevelSize(256, 2) == 64);
}

test imageLevelOffset {
    try testing.expect(imageLevelOffset(1024 * 1024, 512 * 512) == 1024 * 1024);
    try testing.expect(imageLevelOffset(1024 * 1024, 128 * 128) == 1024 * 1024 + 512 * 512 + 256 * 256);
}

test imageLayerSize {
    try testing.expect(imageLayerSize(1024 * 1024, 1) == 1024 * 1024);
    try testing.expect(imageLayerSize(1024 * 1024, 2) == 1024 * 1024 + 512 * 512);
    try testing.expect(imageLayerSize(1024 * 1024, 3) == 1024 * 1024 + 512 * 512 + 256 * 256);
    try testing.expect(imageLayerSize(1024 * 1024, 4) == 1024 * 1024 + 512 * 512 + 256 * 256 + 128 * 128);
    try testing.expect(imageLayerSize(1024 * 1024, 5) == 1024 * 1024 + 512 * 512 + 256 * 256 + 128 * 128 + 64 * 64);
    try testing.expect(imageLayerSize(1024 * 1024, 6) == 1024 * 1024 + 512 * 512 + 256 * 256 + 128 * 128 + 64 * 64 + 32 * 32);
    try testing.expect(imageLayerSize(1024 * 1024, 7) == 1024 * 1024 + 512 * 512 + 256 * 256 + 128 * 128 + 64 * 64 + 32 * 32 + 16 * 16);
    try testing.expect(imageLayerSize(1024 * 1024, 8) == 1024 * 1024 + 512 * 512 + 256 * 256 + 128 * 128 + 64 * 64 + 32 * 32 + 16 * 16 + 8 * 8);
}

comptime {
    _ = Device;
    _ = Queue;
    _ = Semaphore;
    _ = DeviceMemory;
    _ = Buffer;
    _ = Image;
    _ = ImageView;
    _ = Pipeline;
    _ = CommandPool;
    _ = CommandBuffer;
    _ = Sampler;
    _ = Surface;
    _ = Swapchain;
}

const std = @import("std");
const zitrus = @import("zitrus");
