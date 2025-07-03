pub const ZitrusOptions = struct {
    stack_size: u32,
};

pub const PhysicalAddress = enum(usize) {
    _,
};

pub fn AlignedPhysicalAddress(comptime alignment: std.mem.Alignment) type {
    if(alignment == .@"1") {
        return PhysicalAddress;
    }

    return enum(usize) {
        _,
    };
}

pub const panic = @import("panic.zig");
pub const arm = @import("arm.zig");
pub const memory = @import("memory.zig");
pub const start = @import("start.zig");
pub const horizon = @import("horizon.zig");

pub const gpu = @import("gpu.zig");

const builtin = @import("builtin");
const std = @import("std");

comptime {
    _ = start;
}
