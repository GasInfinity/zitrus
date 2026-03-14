//! Zitrus Horizon C API

fn hosControlMemory(out_addr: *[*]align(horizon.heap.page_size) u8, operation: horizon.MemoryOperation, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: horizon.MemoryPermission) callconv(.c) result.Code {
    const res = horizon.controlMemory(operation, addr0, addr1, size, permissions);

    out_addr.* = res.value;
    return res.code;
}

fn hosQueryMemory(query: *horizon.MemoryQuery, address: *anyopaque) callconv(.c) result.Code {
    const res = horizon.queryMemory(address);

    query.* = res.value;
    return res.code;
}

fn hosExit() callconv(.c) noreturn {
    return horizon.exit();
}

fn hosExitThread() callconv(.c) noreturn {
    return horizon.exitThread();
}

fn hosSleepThread(ns: i64) callconv(.c) void {
    return horizon.sleepThread(ns);
}

fn hosCreateMutex(mut: *horizon.Mutex, initial_locked: bool) callconv(.c) result.Code {
    const res = horizon.createMutex(initial_locked);
    mut.* = res.value;
    return res.code;
}

fn hosReleaseMutex(mut: horizon.Mutex) callconv(.c) result.Code {
    return horizon.releaseMutex(mut);
}

fn hosCreateSemaphore(sema: *horizon.Semaphore, initial_count: usize, max_count: usize) callconv(.c) result.Code {
    const res = horizon.createSemaphore(initial_count, max_count);
    sema.* = res.value;
    return res.code;
}

fn hosReleaseSemaphore(last_count: *usize, semaphore: horizon.Semaphore, release_count: isize) callconv(.c) result.Code {
    const res = horizon.releaseSemaphore(semaphore, release_count);
    last_count.* = res.value;
    return res.code;
}

fn hosCreateEvent(event: *horizon.Event, reset_type: horizon.ResetType) callconv(.c) result.Code {
    const res = horizon.createEvent(reset_type);
    event.* = res.value;
    return res.code;
}

fn hosSignalEvent(event: horizon.Event) callconv(.c) result.Code {
    return horizon.signalEvent(event);
}

fn hosClearEvent(event: horizon.Event) callconv(.c) result.Code {
    return horizon.clearEvent(event);
}

/// Gets the `tls.Block` of the current thread.
///
/// `zitrus` reserves some needed state and storage
/// for `threadlocal` variables.
fn hosThreadBlock() callconv(.c) *horizon.tls.Block {
    return horizon.tls.get();
}

comptime {
    @export(&hosThreadBlock, .{ .name = "hosThreadBlock" });
}

const std = @import("std");
const zitrus = @import("zitrus");

const c = zitrus.c;
const horizon = zitrus.horizon;
const result = horizon.result;
