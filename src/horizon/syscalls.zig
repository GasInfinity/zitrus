// It seems SVC's follow AAPCS
// a.k.a:
// r0-r3 -> args/clobbered
// r12 -> clobbered
// lr -> maybe clobbered?
// cc -> ditto.
// memory -> bro, 100%
// https://www.3dbrew.org/wiki/SVC#System_calls

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

pub fn mapMemoryBlock(memory_block: *Handle, address: *align(4096) anyopaque, this: MemoryPermission, other: MemoryPermission) ResultCode {
    return asm volatile ("svc 0x1F"
        : [code] "={r0}" (-> ResultCode),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : "r1", "r2", "r3", "r12", "lr", "cc", "memory"
    );
}

pub fn unmapMemoryBlock(memory_block: *Handle, address: *align(4096) anyopaque) ResultCode {
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

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ResultCode = horizon.ResultCode;
const Result = horizon.Result;

const Handle = horizon.Handle;

const LimitableResource = horizon.LimitableResource;
const ResetType = horizon.ResetType;

const MemoryPermission = horizon.MemoryPermission;
const MemoryOperation = horizon.MemoryOperation;
const MemoryState = horizon.MemoryState;
const PageFlags = horizon.PageFlags;
const MemoryQuery = horizon.MemoryQuery;
