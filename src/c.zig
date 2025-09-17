//! Zitrus C API

pub const horizon = @import("c/horizon.zig");
pub const mango = @import("c/mango.zig");

/// An `std.mem.Allocator` which is extern.
pub const ZigAllocator = extern struct {
    vtable: *const std.mem.Allocator.VTable,
    ptr: *anyopaque,

    pub fn wrap(ally: std.mem.Allocator) ZigAllocator {
        return .{
            .vtable = ally.vtable,
            .ptr = ally.ptr,
        };
    }

    pub fn allocator(ally: ZigAllocator) std.mem.Allocator {
        return .{
            .vtable = ally.vtable,
            .ptr = ally.ptr,
        };
    }
};

comptime {
    _ = horizon;
    _ = mango;
    _ = ZigAllocator;
}

const std = @import("std");
