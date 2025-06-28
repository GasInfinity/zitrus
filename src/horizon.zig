pub const ResultCode = result.ResultCode;
pub const Result = result.Result;

pub const LimitableResource = enum(u32) {
    priority,
    commit,
    thread,
    event,
    mutex,
    semaphore,
    timer,
    shared_memory,
    address_arbiter,
    cpu_time,
};

pub const MemoryPermission = packed struct(u32) {
    pub const r: MemoryPermission = .{ .read = true };
    pub const w: MemoryPermission = .{ .write = true };
    pub const x: MemoryPermission = .{ .execute = true };
    pub const rw: MemoryPermission = .{ .read = true, .write = true };
    pub const rx: MemoryPermission = .{ .read = true, .execute = true };
    pub const rwx: MemoryPermission = .{ .read = true, .write = true, .execute = true };
    pub const dont_care: MemoryPermission = @bitCast(@as(u32, 0x10000000));

    read: bool = false,
    write: bool = false,
    execute: bool = false,
    _: u29 = 0,
};

pub const MemoryOpcode = enum(u8) {
    free = 1,
    reserve,
    commit,
    map,
    unmap,
    protect,
};

pub const MemoryRegion = enum(u3) {
    all,
    app,
    system,
    base,
};

pub const MemoryOperation = packed struct(u32) { fundamental_operation: MemoryOpcode, area: MemoryRegion, _unused0: u5 = 0, linear: bool, _unused1: u15 = 0 };

pub const MemoryState = enum(u32) {
    free,
    reserved,
    io,
    static,
    code,
    private,
    shared,
    continuous,
    aliased,
    alias,
    alias_code,
    locked,
};

pub const MemoryInfo = struct {
    base_vaddr: *anyopaque,
    size: usize,
    permission: MemoryPermission,
    state: MemoryState,
};

pub const PageFlags = enum(u32) {
    locked,
    changed,
};

pub const PageInfo = struct {
    flags: PageFlags,
};

pub const MemoryQuery = struct {
    memory_info: MemoryInfo,
    page_info: PageInfo,
};

pub const Handle = opaque {
    pub const current_thread: *Handle = @ptrFromInt(0xFFFF8000);
    pub const current_process: *Handle = @ptrFromInt(0xFFFF8001);
};

pub const ResetType = enum(u32) { oneshot, sticky, pulse };

pub const Mutex = extern struct {
    pub const CreationError = error{ OutOfMutexes, Unexpected };

    handle: *Handle,

    pub fn init(initial_locked: bool) CreationError!Mutex {
        const mutex_result = createMutex(initial_locked);

        if (!mutex_result.code.isSuccess()) {
            if (mutex_result.code == ResultCode.out_of_sync_objects) {
                return error.OutOfMutexes;
            }

            return error.Unexpected;
        }

        return .{ .handle = mutex_result.value.? };
    }

    pub fn release(mutex: Mutex) void {
        _ = releaseMutex(mutex.handle);
    }

    pub const WaitError = error{ Timeout, Unexpected };
    pub fn wait(mutex: Mutex, timeout_ns: i64) WaitError!void {
        const sync_result = waitSynchronization(mutex.handle, timeout_ns);

        if (!sync_result.isSuccess()) {
            if (sync_result == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }
    }

    pub fn waitMultiple(mutexes: []const Mutex, wait_all: bool, timeout_ns: i64) WaitError!usize {
        const sync_result = waitSynchronizationMultiple(std.mem.bytesAsSlice(*Handle, std.mem.sliceAsBytes(mutexes)), wait_all, timeout_ns);

        if (!sync_result.code.isSuccess()) {
            if (sync_result.code == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }

        return sync_result.value.?;
    }

    pub fn deinit(mutex: *Mutex) void {
        _ = closeHandle(mutex.handle);
        mutex.* = undefined;
    }
};

pub const Semaphore = extern struct {
    pub const CreationError = error{ OutOfSemaphores, Unexpected };

    handle: *Handle,

    pub fn init(initial_count: usize, max_count: usize) CreationError!Semaphore {
        const semaphore_result = createSemaphore(initial_count, max_count);

        if (!semaphore_result.code.isSuccess()) {
            if (semaphore_result.code == ResultCode.out_of_sync_objects) {
                return error.OutOfSemaphores;
            }

            return error.Unexpected;
        }

        return .{ .handle = semaphore_result.value.? };
    }

    pub fn release(semaphore: Semaphore, count: usize) void {
        _ = releaseSemaphore(semaphore.handle, count);
    }

    pub const WaitError = error{ Timeout, Unexpected };
    pub fn wait(semaphore: Semaphore, timeout_ns: i64) WaitError!void {
        const sync_result = waitSynchronization(semaphore.handle, timeout_ns);

        if (!sync_result.isSuccess()) {
            if (sync_result == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }
    }

    pub fn waitMultiple(semaphore: []const Semaphore, wait_all: bool, timeout_ns: i64) WaitError!usize {
        const sync_result = waitSynchronizationMultiple(std.mem.bytesAsSlice(*Handle, std.mem.sliceAsBytes(semaphore)), wait_all, timeout_ns);

        if (!sync_result.code.isSuccess()) {
            if (sync_result.code == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }

        return sync_result.value.?;
    }

    pub fn deinit(semaphore: *Semaphore) void {
        _ = closeHandle(semaphore.handle);
        semaphore.* = undefined;
    }
};

pub const Event = extern struct {
    pub const CreationError = error{ OutOfEvents, Unexpected };

    handle: *Handle,

    pub fn init(reset_type: ResetType) CreationError!Event {
        const ev_result = createEvent(reset_type);

        if (!ev_result.code.isSuccess()) {
            if (ev_result.code == ResultCode.out_of_sync_objects) {
                return error.OutOfEvents;
            }

            return error.Unexpected;
        }

        return .{ .handle = ev_result.value.? };
    }

    pub fn clear(ev: Event) void {
        _ = clearEvent(ev.handle);
    }

    pub fn signal(ev: Event) void {
        _ = signalEvent(ev.handle);
    }

    pub const WaitError = error{ Timeout, Unexpected };
    pub fn wait(ev: Event, timeout_ns: i64) WaitError!void {
        const sync_result = waitSynchronization(ev.handle, timeout_ns);

        if (!sync_result.isSuccess()) {
            if (sync_result == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }
    }

    pub fn waitMultiple(evs: []const Event, wait_all: bool, timeout_ns: i64) WaitError!usize {
        const sync_result = waitSynchronizationMultiple(std.mem.bytesAsSlice(*Handle, std.mem.sliceAsBytes(evs)), wait_all, timeout_ns);

        if (!sync_result.code.isSuccess()) {
            if (sync_result.code == ResultCode.timeout) {
                return error.Timeout;
            }

            return error.Unexpected;
        }

        return sync_result.value.?;
    }

    pub fn deinit(ev: *Event) void {
        _ = closeHandle(ev.handle);
        ev.* = undefined;
    }
};

pub const MemoryBlock = extern struct {
    pub const Error = error{ InvalidPermissions, Unexpected };
    pub const CreationError = Error || error{OutOfBlocks};

    handle: *Handle,

    pub fn init(address: *align(heap.page_size) anyopaque, size: usize, this: MemoryPermission, other: MemoryPermission) CreationError!MemoryBlock {
        if (this.execute) {
            return Error.InvalidPermissions;
        }

        const mem_result = createMemoryBlock(address, size, this, other);

        if (!mem_result.code.isSuccess()) {
            if (mem_result.code == ResultCode.out_of_memory_blocks) {
                return error.OutOfBlocks;
            }

            return error.Unexpected;
        }

        return .{ .handle = mem_result.value.? };
    }

    pub const MapError = error{ InvalidPermissions, Unexpected };
    pub fn map(mem: MemoryBlock, address: [*]align(heap.page_size) u8, this: MemoryPermission, other: MemoryPermission) Error!void {
        if (this.execute) {
            return error.InvalidPermissions;
        }

        const map_result = mapMemoryBlock(mem.handle, address, this, other);

        if (!map_result.isSuccess()) {
            return error.Unexpected;
        }
    }

    pub fn unmap(mem: MemoryBlock, address: [*]align(heap.page_size) u8) void {
        _ = unmapMemoryBlock(mem.handle, address);
    }

    pub fn deinit(mem: *MemoryBlock) void {
        _ = closeHandle(mem.handle);
        mem.* = undefined;
    }
};

pub const Session = extern struct {
    pub const Error = error{Unexpected};
    pub const ConnectionError = Error || error{NotFound};
    pub const RequestError = Error || error{ConnectionClosed};

    handle: *Handle,

    pub fn connect(port: [:0]const u8) ConnectionError!Session {
        const res = connectToPort(port);

        if (!res.code.isSuccess()) {
            if (res.code == ResultCode.port_not_found) {
                return ConnectionError.NotFound;
            }

            return error.Unexpected;
        }

        return .{ .handle = res.value.? };
    }

    pub fn sendRequest(session: Session) RequestError!void {
        const req_result = sendSyncRequest(session.handle);

        if (!req_result.isSuccess()) {
            if (req_result == ResultCode.session_closed) {
                return error.ConnectionClosed;
            }

            return error.Unexpected;
        }
    }

    pub fn deinit(session: *Session) void {
        _ = closeHandle(session.handle);
        session.* = undefined;
    }
};

pub fn controlMemory(operation: MemoryOperation, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: MemoryPermission) Result(*anyopaque) {
    var mapped_addr: *anyopaque = undefined;

    const code = asm volatile ("svc 0x01"
        : [code] "={r0}" (-> ResultCode),
          [mapped_addr] "={r1}" (mapped_addr),
        : [operation] "{r0}" (operation),
          [addr0] "{r1}" (addr0),
          [addr1] "{r2}" (addr1),
          [size] "{r3}" (size),
          [permissions] "{r4}" (permissions),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = mapped_addr };
}

pub fn queryMemory(address: *anyopaque) Result(MemoryQuery) {
    var base_vaddr: *anyopaque = undefined;
    var size: usize = undefined;
    var permission: MemoryPermission = undefined;
    var state: MemoryState = undefined;
    var page_flags: PageFlags = undefined;

    const code = asm volatile ("svc 0x02"
        : [code] "={r0}" (-> ResultCode),
          [base_vaddr] "={r1}" (base_vaddr),
          [size] "={r2}" (size),
          [permission] "={r3}" (permission),
          [state] "={r4}" (state),
          [page_flags] "={r5}" (page_flags),
        : [handle] "{r2}" (address),
        : "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = .{ .memory_info = .{ .base_vaddr = base_vaddr, .size = size, .permission = permission, .state = state }, .page_info = .{ .flags = page_flags } } };
}

pub fn exit() noreturn {
    asm volatile ("svc 0x03");
    unreachable;
}

pub fn sleepThread(ns: i64) void {
    const ns_u: u64 = @bitCast(ns);

    asm volatile ("svc 0x0A"
        :
        : [ns_low] "{r0}" (@as(u32, @truncate(ns_u))),
          [ns_high] "{r1}" (@as(u32, @truncate(ns_u >> 32))),
        : "r0", "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn createMutex(initial_locked: bool) Result(*Handle) {
    var handle: ?*Handle = undefined;

    const code = asm volatile ("svc 0x13"
        : [code] "={r0}" (-> ResultCode),
          [handle] "={r1}" (handle),
        : [initial_locked] "{r0}" (initial_locked),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = handle };
}

pub fn releaseMutex(handle: *Handle) ResultCode {
    return asm volatile ("svc 0x14"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (handle),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn createSemaphore(initial_count: usize, max_count: usize) Result(*Handle) {
    var handle: ?*Handle = undefined;

    const code = asm volatile ("svc 0x15"
        : [code] "={r0}" (-> ResultCode),
          [handle] "={r1}" (handle),
        : [initial_count] "{r0}" (initial_count),
          [max_count] "{r1}" (max_count),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = handle };
}

pub fn releaseSemaphore(handle: *Handle, release_count: usize) Result(*Handle) {
    var count: usize = undefined;

    const code = asm volatile ("svc 0x16"
        : [code] "={r0}" (-> ResultCode),
          [count] "={r1}" (count),
        : [handle] "{r0}" (handle),
          [release_count] "{r1}" (release_count),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = count };
}

pub fn createEvent(reset_type: ResetType) Result(*Handle) {
    var event: ?*Handle = undefined;

    const code = asm volatile ("svc 0x17"
        : [code] "={r0}" (-> ResultCode),
          [event] "={r1}" (event),
        : [reset_type] "{r0}" (reset_type),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = event };
}

pub fn signalEvent(event: *Handle) ResultCode {
    return asm volatile ("svc 0x18"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (event),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn clearEvent(event: *Handle) ResultCode {
    return asm volatile ("svc 0x19"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (event),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn createMemoryBlock(address: *align(4096) anyopaque, size: usize, this: MemoryPermission, other: MemoryPermission) Result(*Handle) {
    var memory_block: ?*Handle = undefined;

    const code = asm volatile ("svc 0x1E"
        : [code] "={r0}" (-> ResultCode),
          [memory_block] "={r1}" (memory_block),
        : [address] "{r0}" (address),
          [size] "{r1}" (size),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = memory_block };
}

pub fn mapMemoryBlock(memory_block: *Handle, address: [*]align(4096) u8, this: MemoryPermission, other: MemoryPermission) ResultCode {
    return asm volatile ("svc 0x1F"
        : [code] "={r0}" (-> ResultCode),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn unmapMemoryBlock(memory_block: *Handle, address: [*]align(4096) u8) ResultCode {
    return asm volatile ("svc 0x20"
        : [code] "={r0}" (-> ResultCode),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn closeHandle(handle: *Handle) ResultCode {
    return asm volatile ("svc 0x23"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (handle),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn waitSynchronization(handle: *Handle, timeout_ns: i64) ResultCode {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);

    return asm volatile ("svc 0x24"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (handle),
          [timeout_low] "{r2}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_high] "{r3}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn waitSynchronizationMultiple(handles: []const *Handle, wait_all: bool, timeout_ns: i64) Result(usize) {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);
    var id: usize = 0;

    const code = asm volatile ("svc 0x25"
        : [code] "={r0}" (-> ResultCode),
          [id] "={r1}" (id),
        : [handles] "{r1}" (handles.ptr),
          [handles_len] "{r2}" (handles.len),
          [wait_all] "{r3}" (wait_all),
          [timeout_low] "{r0}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_high] "{r4}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = id };
}

pub fn duplicateHandle(original: *Handle) Result(*Handle) {
    var duplicated: ?*Handle = undefined;

    const code = asm volatile ("svc 0x27"
        : [code] "={r0}" (-> ResultCode),
          [duplicated] "={r1}" (duplicated),
        : [original] "{r0}" (original),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = duplicated };
}

pub fn getSystemTick() i64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("svc 0x28"
        : [lo] "={r0}" (lo),
          [hi] "={r1}" (hi),
        :
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return @bitCast((@as(u64, hi) << 32) | lo);
}

pub fn connectToPort(port: [:0]const u8) Result(*Handle) {
    var session: ?*Handle = undefined;

    const code = asm volatile ("svc 0x2D"
        : [code] "={r0}" (-> ResultCode),
          [session] "={r1}" (session),
        : [unknown] "{r0}" (0),
          [port] "{r1}" (port.ptr),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = session };
}

pub fn sendSyncRequest(session: *Handle) ResultCode {
    return asm volatile ("svc 0x32"
        : [code] "={r0}" (-> ResultCode),
        : [session] "{r0}" (session),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn getProcessId(process: *Handle) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x35"
        : [code] "={r0}" (-> ResultCode),
          [id] "={r1}" (id),
        : [process] "{r1}" (process),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = id };
}

pub fn getResourceLimit(process: *Handle) Result(*Handle) {
    var resource_limit: ?*Handle = undefined;

    const code = asm volatile ("svc 0x38"
        : [code] "={r0}" (-> ResultCode),
          [resource_limit] "={r1}" (resource_limit),
        : [process] "{r1}" (process),
        : "r2", "r3", "r12", "lr", "cc", "memory"
    );

    return .{ .code = code, .value = resource_limit };
}

pub fn getResourceLimitLimitValues(values: []i64, resource_limit: *Handle, names: []LimitableResource) ResultCode {
    std.debug.assert(values.len == names.len);
    return asm volatile ("svc 0x39"
        : [code] "={r0}" (-> ResultCode),
        : [values_ptr] "{r0}" (@intFromPtr(values.ptr)),
          [resource_limit] "{r1}" (@intFromPtr(resource_limit)),
          [names_ptr] "{r2}" (@intFromPtr(names.ptr)),
          [names_len] "{r3}" (names.len),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn getResourceLimitCurrentValues(values: []i64, resource_limit: *Handle, names: []LimitableResource) ResultCode {
    std.debug.assert(values.len == names.len);
    return asm volatile ("svc 0x3A"
        : [code] "={r0}" (-> ResultCode),
        : [values_ptr] "{r0}" (@intFromPtr(values.ptr)),
          [resource_limit] "{r1}" (@intFromPtr(resource_limit)),
          [names_ptr] "{r2}" (@intFromPtr(names.ptr)),
          [names_len] "{r3}" (names.len),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn breakpoint() noreturn {
    asm volatile ("svc 0xFF" ::: "r0", "r1", "r2", "r3", "r12", "lr", "cc", "memory");
}

pub const heap = @import("horizon/heap.zig");
pub const environment = @import("horizon/environment.zig");
pub const result = @import("horizon/result.zig");
pub const memory = @import("horizon/memory.zig");
pub const config = @import("horizon/config.zig");
pub const ipc = @import("horizon/ipc.zig");
pub const tls = @import("horizon/tls.zig");

pub const ServiceManager = @import("horizon/ServiceManager.zig");
pub const ErrorDisplayManager = @import("horizon/ErrorDisplayManager.zig");

pub const services = @import("horizon/services.zig");

const std = @import("std");
