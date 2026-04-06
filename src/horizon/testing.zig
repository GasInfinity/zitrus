/// Provides a session to the Service Manager port within tests.
/// Initialized at startup. Read-only after that
pub var srv: horizon.ServiceManager = if (!builtin.is_test)
    @compileError("not testing")
else
    undefined;

/// Provides a session to the Applet service within tests.
/// Initialized at startup. Read-only after that
pub var apt: horizon.services.Applet = if (!builtin.is_test)
    @compileError("not testing")
else
    undefined;

/// Provides a session to the GraphicsServerGpu service within tests.
/// Initialized at startup. Read-only after that
pub var gsp: horizon.services.GraphicsServerGpu = if (!builtin.is_test)
    @compileError("not testing")
else
    undefined;

pub var arbiter: horizon.AddressArbiter = if (!builtin.is_test)
    @compileError("not testing")
else
    undefined;

// FIXME: DebugAllocator doesn't work in non single-threaded mode as it depends on std.Io.Threaded, great.
pub var allocator_instance: std.heap.DebugAllocator(.{
    .thread_safe = false,
    .stack_trace_frames = if (std.debug.sys_can_stack_trace) 10 else 0,
    .resize_stack_traces = true,
    .canary = @truncate(0x2731e675c3a701ba),
    .page_size = 64 * 1024,
}) = .init;
pub const allocator = if (builtin.is_test) allocator_instance.allocator() else @compileError("not testing");

pub var io_instance: horizon.Io = undefined;
pub const io = if (builtin.is_test) io_instance.io() else @compileError("not testing");

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
