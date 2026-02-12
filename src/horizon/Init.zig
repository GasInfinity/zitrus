gpa: std.mem.Allocator,
arbiter: horizon.AddressArbiter,

pub const Application = @import("Init/Application.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
