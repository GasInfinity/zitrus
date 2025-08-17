pub const vtable = std.heap.SbrkAllocator(horizon.sbrk).vtable;

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = mem.Alignment;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
