pub const vtable = .{};

// TODO: Should we use a sbrk-esque approach? bitmap, buddy, ...?

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = mem.Alignment;

const zitrus = @import("zitrus");
