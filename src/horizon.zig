pub const ResultCode = result.ResultCode;
pub const Result = result.Result;

pub const LimitableResource = enum(u32) { priority, commit, thread, event, mutex, semaphore, timer, shared_memory, address_arbiter, cpu_time };

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

    pub fn init(address: *align(4096) anyopaque, size: usize, this: MemoryPermission, other: MemoryPermission) CreationError!MemoryBlock {
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
    pub fn map(mem: MemoryBlock, address: *align(4096) anyopaque, this: MemoryPermission, other: MemoryPermission) Error!void {
        if (this.execute) {
            return error.InvalidPermissions;
        }

        const map_result = mapMemoryBlock(mem.handle, address, this, other);

        if (!map_result.isSuccess()) {
            return error.Unexpected;
        }
    }

    pub fn unmap(mem: MemoryBlock, address: *align(4096) anyopaque) void {
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

pub const page_size_min: usize = 4096;

pub const SharedMemoryAddressAllocator = page_allocators.SharedMemoryAddressAllocator;
pub const sharedMemoryAddressAllocator = page_allocators.sharedMemoryAddressAllocator;
pub const linear_page_allocator = page_allocators.linear_page_allocator;

pub const controlMemory = syscalls.controlMemory;
pub const queryMemory = syscalls.queryMemory;
pub const exit = syscalls.exit;
pub const sleepThread = syscalls.sleepThread;
pub const createMutex = syscalls.createMutex;
pub const releaseMutex = syscalls.releaseMutex;
pub const createSemaphore = syscalls.createSemaphore;
pub const releaseSemaphore = syscalls.releaseSemaphore;
pub const createEvent = syscalls.createEvent;
pub const signalEvent = syscalls.signalEvent;
pub const clearEvent = syscalls.clearEvent;
pub const closeHandle = syscalls.closeHandle;
pub const createMemoryBlock = syscalls.createMemoryBlock;
pub const mapMemoryBlock = syscalls.mapMemoryBlock;
pub const unmapMemoryBlock = syscalls.unmapMemoryBlock;
pub const waitSynchronization = syscalls.waitSynchronization;
pub const waitSynchronizationMultiple = syscalls.waitSynchronizationMultiple;
pub const duplicateHandle = syscalls.duplicateHandle;
pub const getSystemTick = syscalls.getSystemTick;
pub const connectToPort = syscalls.connectToPort;
pub const sendSyncRequest = syscalls.sendSyncRequest;
pub const getProcessId = syscalls.getProcessId;
pub const getResourceLimit = syscalls.getResourceLimit;
pub const getResourceLimitLimitValues = syscalls.getResourceLimitLimitValues;
pub const getResourceLimitCurrentValues = syscalls.getResourceLimitCurrentValues;
pub const breakpoint = syscalls.breakpoint;

pub const result = @import("horizon/result.zig");
pub const memory = @import("horizon/memory.zig");
pub const syscalls = @import("horizon/syscalls.zig");
pub const kernel = @import("horizon/kernel.zig");
pub const ipc = @import("horizon/ipc.zig");
pub const tls = @import("horizon/tls.zig");
pub const page_allocators = @import("horizon/page_allocators.zig");

pub const ServiceManager = @import("horizon/ServiceManager.zig");
pub const ErrorDisplayManager = @import("horizon/ErrorDisplayManager.zig");

pub const services = @import("horizon/services.zig");

const std = @import("std");
