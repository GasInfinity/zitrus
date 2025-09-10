//! Zitrus C API

pub const mango = @import("c/mango.zig");

comptime {
    _ = mango;
}
