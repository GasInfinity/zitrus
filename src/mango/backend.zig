/// All index / vertex buffers provided to the gpu are relative to this address
pub const global_attribute_buffer_base: zitrus.PhysicalAddress = .fromAddress(zitrus.memory.arm11.vram_begin);

/// At most, this amount of commands can be buffered simultaneously by the driver.
/// OutOfMemory will be returned if the driver can not queue more.
pub const max_buffered_queue_commands = 32;

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
    try testing.expectEqual(0, bq.header.raw.index);
    try testing.expectEqual(1, bq.header.raw.len);

    const should_be_7 = bq.popBack();
    try testing.expectEqual(7, should_be_7);

    try testing.expectEqual(1, bq.header.raw.index);
    try testing.expectEqual(0, bq.header.raw.len);
}

test "SingleProducerSingleConsumerBoundedQueue is a FIFO" {
    var bq: TestingSpScBoundedQueue = .initEmpty;

    bq.pushFrontAssumeCapacity(7);
    bq.pushFrontAssumeCapacity(8);
    bq.pushFrontAssumeCapacity(2);
    bq.pushFrontAssumeCapacity(1);

    try testing.expectEqual(0, bq.header.raw.index);
    try testing.expectEqual(4, bq.header.raw.len);

    const should_be_7 = bq.popBack();
    try testing.expectEqual(7, should_be_7);

    const should_be_8 = bq.popBack();
    try testing.expectEqual(8, should_be_8);

    const should_be_2 = bq.popBack();
    try testing.expectEqual(2, should_be_2);

    const should_be_1 = bq.popBack();
    try testing.expectEqual(1, should_be_1);

    try testing.expectEqual(0, bq.header.raw.index);
    try testing.expectEqual(0, bq.header.raw.len);
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
