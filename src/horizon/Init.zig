arbiter: horizon.AddressArbiter,
gpa: std.mem.Allocator,
io: std.Io,

pub const Application = @import("Init/Application.zig");

const Init = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
