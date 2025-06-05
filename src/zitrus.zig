pub const ZitrusOptions = struct {
    stack_size: u32,
};

pub const panic = @import("panic.zig");
pub const os = struct {
    pub const heap = struct {
        // XXX: The linear page allocator is the only one where we don't have to do any bookkeeping
        pub const page_allocator = horizon.linear_page_allocator;
    };
};

pub const arm = @import("arm.zig");
pub const memory = @import("memory.zig");
pub const start = @import("start.zig");
pub const horizon = @import("horizon.zig");

pub const gpu = @import("gpu.zig");

const builtin = @import("builtin");

comptime {
    _ = start;
}
