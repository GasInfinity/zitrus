pub const Framebuffer = @import("Framebuffer.zig");
pub const State = @import("State.zig");

pub fn Batcher(comptime Vertex: type) type {
    return struct {
        pub const empty: Batch = .{
            .vertices = .empty,
            .vertices_gpu = .empty,
            .indices = .empty,
            .indices_gpu = .empty,
        };

        vertices: std.ArrayList(Vertex),
        vertices_gpu: mango.DeviceSlice,
        indices: std.ArrayList(u16),
        indices_gpu: mango.DeviceSlice,

        pub fn deinit(bat: *Batch, linear_gpa: std.mem.Allocator) void {
            bat.vertices.deinit(linear_gpa);
            bat.indices.deinit(linear_gpa);
        }

        pub fn reset(bat: *Batch) void {
            bat.vertices.clearRetainingCapacity();
            bat.indices.clearRetainingCapacity();
        }

        pub fn addQuadAssumeCapacity(bat: *Batch) []Vertex {
            // XXX: This will overflow eventually but demos won't fill it too much.
            // We'll have to add a separate draw call ArrayList for this (as we support vertex offsets in drawcalls :D!)
            const first: u16 = @intCast(bat.vertices.items.len);
            bat.indices.appendSliceAssumeCapacity(&.{first, first + 1, first + 2, first + 2, first + 3, first});
            return bat.vertices.addManyAsSliceAssumeCapacity(4);
        }

        pub fn ensureQuads(bat: *Batch, linear_gpa: std.mem.Allocator, n: usize) !void {
            try bat.vertices.ensureUnusedCapacity(linear_gpa, 4 * n);
            try bat.indices.ensureUnusedCapacity(linear_gpa, 6 * n); 
        }

        pub fn addQuad(bat: *Batch, linear_gpa: std.mem.Allocator) ![]Vertex {
            try bat.ensureQuads(linear_gpa, 1);
            return bat.addQuadAssumeCapacity();
        }

        pub fn flush(bat: *Batch, dev: mango.Device) !void {
            bat.vertices_gpu = try dev.hostToDevice(@ptrCast(bat.vertices.items));
            bat.indices_gpu = try dev.hostToDevice(@ptrCast(bat.indices.items));
            try dev.flushCachedMemoryRanges(&.{ @ptrCast(bat.vertices.items), @ptrCast(bat.indices.items) });
        }

        const Batch = @This();
    };
}

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const horizon = zitrus.horizon;
