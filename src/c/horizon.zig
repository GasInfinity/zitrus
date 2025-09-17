//! Zitrus Horizon C API

pub export fn ztrHorGetLinearPageAllocator() c.ZigAllocator {
    return .wrap(horizon.heap.linear_page_allocator);
}

const application = @import("horizon/application.zig");

const std = @import("std");
const zitrus = @import("zitrus");

const c = zitrus.c;
const horizon = zitrus.horizon;
