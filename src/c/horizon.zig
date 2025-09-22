//! Zitrus Horizon C API

pub export fn ztrHorGetLinearPageAllocator() c.ZigAllocator {
    return .wrap(horizon.heap.linear_page_allocator);
}

pub export fn ztrHorControlMemory(out_addr: *[*]align(horizon.heap.page_size) u8, operation: horizon.MemoryOperation, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: horizon.MemoryPermission) ResultCode {
    const res = horizon.controlMemory(operation, addr0, addr1, size, permissions);

    out_addr.* = res.value;
    return res.code;
}

pub export fn ztrHorQueryMemory(query: *horizon.MemoryQuery, address: *anyopaque) ResultCode {
    const res = horizon.queryMemory(address);

    query.* = res.value;
    return res.code;
}

pub export fn ztrHorExit() noreturn {
    return horizon.exit();
}

pub export fn ztrHorExitThread() noreturn {
    return horizon.exitThread();
}

pub export fn ztrHorSleepThread(ns: i64) void {
    return horizon.sleepThread(ns);
}

pub export fn ztrHorCreateMutex(mut: *horizon.Mutex, initial_locked: bool) ResultCode {
    const res = horizon.createMutex(initial_locked);
    mut.* = res.value;
    return res.code;
}

pub export fn ztrHorReleaseMutex(mut: horizon.Mutex) ResultCode {
    return horizon.releaseMutex(mut);
}

pub export fn ztrHorCreateSemaphore(sema: *horizon.Semaphore, initial_count: usize, max_count: usize) ResultCode {
    const res = horizon.createSemaphore(initial_count, max_count);
    sema.* = res.value;
    return res.code;
}

pub export fn ztrHorReleaseSemaphore(last_count: *usize, semaphore: horizon.Semaphore, release_count: isize) ResultCode {
    const res = horizon.releaseSemaphore(semaphore, release_count);
    last_count.* = res.value;
    return res.code;
}

pub export fn ztrHorCreateEvent(event: *horizon.Event, reset_type: horizon.ResetType) ResultCode {
    const res = horizon.createEvent(reset_type);
    event.* = res.value;
    return res.code;
}

pub export fn ztrHorSignalEvent(event: horizon.Event) ResultCode {
    return horizon.signalEvent(event);
}

pub export fn ztrHorClearEvent(event: horizon.Event) ResultCode {
    return horizon.clearEvent(event);
}

comptime {
    _ = application;
    _ = tls;
}

pub const application = @import("horizon/application.zig");
// NOTE: ipc is very type-safe and relies on zig and `comptime` so it cannot be exposed.
pub const tls = @import("horizon/tls.zig");

const std = @import("std");
const zitrus = @import("zitrus");

const c = zitrus.c;
const horizon = zitrus.horizon;

const ResultCode = horizon.result.Code;
