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

pub const ResetType = enum(u32) { oneshot, sticky, pulse };

pub const Arbitration = union(Type) {
    pub const Type = enum(u32) { signal, wait_if_less_than, decrement_and_wait_if_less_than, wait_if_less_than_timeout, decrement_and_wait_if_less_than_timeout };

    pub const TimeoutValue = extern struct { value: i32, timeout_ns: i64 };

    signal: i32,
    wait_if_less_than: i32,
    decrement_and_wait_if_less_than: i32,
    wait_if_less_than_timeout: TimeoutValue,
    decrement_and_wait_if_less_than_timeout: TimeoutValue,
};

pub const SystemInfo = union(Type) {
    pub const Type = enum(u32) {
        total_used_memory,
        total_used_kernel_memory,
        loaded_kernel_processes,
    };

    used_memory: MemoryRegion,
    used_kernel_memory: void,
    loaded_kernel_processes: void,
};

pub const ProcessInfoType = enum(u32) {
    used_heap_memory,
    used_handles = 0x4,
    highes_used_handles,

    num_threads = 0x7,
    max_threads,
};

pub const BreakReason = enum(u32) {
    panic,
    assert,
    user,
};

pub const InterruptId = enum(u32) {};

pub const StartupInfo = extern struct {
    priority: i32,
    stack_size: u32,
    argc: u32,
    argv: [*]i16,
    envp: [*]i16,
};

pub const Object = enum(u32) {
    null = 0,
    _,
};

pub const ResouceLimit = packed struct(u32) {
    obj: Object,
};

pub const AddressArbiter = packed struct(u32) {
    obj: Object,

    pub fn init() UnexpectedError!AddressArbiter {
        return switch (createAddressArbiter()) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn arbitrate(arbiter: AddressArbiter, address: *i32, arbitration: Arbitration) UnexpectedError!AddressArbiter {
        const value: u32, const timeout_ns: i64 = switch (arbitration) {
            inline .signal, .wait_if_less_than, .decrement_and_wait_if_less_than => |value| .{ value, 0 },
            inline .wait_if_less_than_timeout, .decrement_and_wait_if_less_than_timeout => |timeout_value| .{ timeout_value.value, timeout_value.timeout_ns },
        };

        return arbitrateAddress(arbiter, address, std.meta.activeTag(arbitration), value, timeout_ns);
    }

    pub fn deinit(arbiter: *AddressArbiter) void {
        _ = closeHandle(arbiter.obj);
        arbiter.* = undefined;
    }
};

pub const Synchronization = packed struct(u32) {
    pub const CreationError = error{OutOfSynchronizationObjects} || UnexpectedError;
    pub const WaitError = error{Timeout} || UnexpectedError;

    obj: Object,

    pub fn checkResult(comptime T: type, res: Result(T)) CreationError!T {
        return switch (res) {
            .success => |s| s.value,
            .failure => |code| if (code == ResultCode.out_of_sync_objects) error.OutOfSynchronizationObjects else unexpectedResult(code),
        };
    }

    pub fn wait(sync: Synchronization, timeout_ns: i64) WaitError!void {
        const sync_result = waitSynchronization(sync, timeout_ns);

        if (sync_result == ResultCode.timeout) {
            return error.Timeout;
        }

        if (!sync_result.isSuccess()) {
            return unexpectedResult(sync_result);
        }
    }

    pub fn waitMultiple(syncs: []const Synchronization, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return switch (waitSynchronizationMultiple(@ptrCast(syncs), wait_all, timeout_ns)) {
            .success => |s| if (s.code == ResultCode.timeout) error.Timeout else s.value,
            .failure => |code| unexpectedResult(code),
        };
    }
};

pub const Interruptable = packed struct(u32) {
    sync: Synchronization,
};

pub const Mutex = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    sync: Synchronization,

    pub fn create(initial_locked: bool) CreationError!Mutex {
        return Synchronization.checkResult(Mutex, createMutex(initial_locked));
    }

    pub fn release(mutex: Mutex) void {
        _ = releaseMutex(mutex);
    }

    pub fn wait(mutex: Mutex, timeout_ns: i64) WaitError!void {
        return mutex.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(mutexes: []const Mutex, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(mutexes), wait_all, timeout_ns);
    }

    pub fn deinit(mutex: *Mutex) void {
        _ = closeHandle(mutex.sync.obj);
        mutex.* = undefined;
    }
};

pub const Semaphore = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    int: Interruptable,

    pub fn create(initial_count: usize, max_count: usize) CreationError!Semaphore {
        return Synchronization.checkResult(Semaphore, createSemaphore(initial_count, max_count));
    }

    pub fn release(semaphore: Semaphore, count: usize) void {
        _ = releaseSemaphore(semaphore, count);
    }

    pub fn wait(semaphore: Semaphore, timeout_ns: i64) WaitError!void {
        return semaphore.int.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(semaphore: []const Semaphore, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(semaphore), wait_all, timeout_ns);
    }

    pub fn deinit(semaphore: *Semaphore) void {
        _ = closeHandle(semaphore.int.sync.obj);
        semaphore.* = undefined;
    }
};

pub const Event = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    int: Interruptable,

    pub fn create(reset_type: ResetType) CreationError!Event {
        return Synchronization.checkResult(Event, createEvent(reset_type));
    }

    pub fn clear(ev: Event) void {
        _ = clearEvent(ev);
    }

    pub fn signal(ev: Event) void {
        _ = signalEvent(ev);
    }

    pub fn wait(ev: Event, timeout_ns: i64) WaitError!void {
        return ev.int.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(evs: []const Event, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(evs), wait_all, timeout_ns);
    }

    pub fn deinit(ev: *Event) void {
        _ = closeHandle(ev.int.sync.obj);
        ev.* = undefined;
    }
};

pub const Timer = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    sync: Synchronization,

    pub fn create(reset_type: ResetType) CreationError!Event {
        return Synchronization.checkResult(Timer, createTimer(reset_type));
    }

    pub fn set(timer: Timer, initial_ns: i64, interval: i64) void {
        _ = setTimer(timer, initial_ns, interval);
    }

    pub fn clear(timer: Timer) void {
        _ = clearTimer(timer);
    }

    pub fn cancel(timer: Timer) void {
        _ = cancelTimer(timer);
    }

    pub fn wait(timer: Timer, timeout_ns: i64) WaitError!void {
        return timer.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(timers: []const Timer, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(timers), wait_all, timeout_ns);
    }

    pub fn deinit(timer: *Timer) void {
        _ = closeHandle(timer.sync.obj);
        timer.* = undefined;
    }
};

pub const MemoryBlock = packed struct(u32) {
    pub const Error = error{ InvalidPermissions, Unexpected };
    pub const CreationError = error{OutOfBlocks} || Error;

    obj: Object,

    pub fn create(address: *align(heap.page_size) anyopaque, size: usize, this: MemoryPermission, other: MemoryPermission) CreationError!MemoryBlock {
        return switch (createMemoryBlock(address, size, this, other)) {
            .success => |s| s.value,
            .failure => |code| if (code == ResultCode.out_of_memory_blocks) error.OutOfMemoryBlocks else unexpectedResult(code),
        };
    }

    pub const MapError = error{ InvalidPermissions, Unexpected };
    pub fn map(mem: MemoryBlock, address: [*]align(heap.page_size) u8, this: MemoryPermission, other: MemoryPermission) Error!void {
        if (this.execute) {
            return error.InvalidPermissions;
        }

        const map_result = mapMemoryBlock(mem, address, this, other);

        if (!map_result.isSuccess()) {
            return error.Unexpected;
        }
    }

    pub fn unmap(mem: MemoryBlock, address: [*]align(heap.page_size) u8) void {
        _ = unmapMemoryBlock(mem, address);
    }

    pub fn deinit(mem: *MemoryBlock) void {
        _ = closeHandle(mem.obj);
        mem.* = undefined;
    }
};

pub const ServerSession = packed struct(u32) {
    sync: Synchronization,

    pub fn deinit(session: *ServerSession) void {
        _ = closeHandle(session.sync.obj);
        session.* = undefined;
    }
};

pub const ClientSession = packed struct(u32) {
    pub const ConnectionError = UnexpectedError || error{NotFound};
    pub const RequestError = UnexpectedError || error{ConnectionClosed};

    sync: Synchronization,

    pub fn connect(port: [:0]const u8) ConnectionError!ClientSession {
        return switch (connectToPort(port)) {
            .success => |s| s.value,
            .failure => |code| if (code == ResultCode.port_not_found) error.NotFound else unexpectedResult(code),
        };
    }

    pub fn sendRequest(session: ClientSession) RequestError!void {
        const req_result = sendSyncRequest(session);

        if (!req_result.isSuccess()) {
            if (req_result == ResultCode.session_closed) {
                return error.ConnectionClosed;
            }

            return unexpectedResult(req_result);
        }
    }

    pub fn deinit(session: *ClientSession) void {
        _ = closeHandle(session.sync.obj);
        session.* = undefined;
    }
};

pub const Session = struct {
    server: ServerSession,
    client: ClientSession,

    pub fn create() UnexpectedError!Session {
        return switch (createSession()) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn deinit(session: *Session) void {
        session.server.deinit();
        session.client.deinit();
        session.* = undefined;
    }
};

pub const ServerPort = packed struct(u32) {
    sync: Synchronization,

    pub fn accept(port: ServerPort) UnexpectedError!ServerSession {
        return switch (acceptSession(port)) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn deinit(port: *ServerPort) void {
        _ = closeHandle(port.sync.obj);
        port.* = undefined;
    }
};

pub const ClientPort = packed struct(u32) {
    sync: Synchronization,

    pub fn createNewSession(port: ClientPort) UnexpectedError!ClientSession {
        return switch (createSessionToPort(port)) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn deinit(port: *ClientPort) void {
        _ = closeHandle(port.sync.obj);
        port.* = undefined;
    }
};

pub const Port = struct {
    server: ServerPort,
    client: ClientPort,

    pub fn create(name: [:0]const u8, max_sessions: i16) UnexpectedError!Port {
        return switch (createPort(name, max_sessions)) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn deinit(port: *Port) void {
        port.server.deinit();
        port.client.deinit();
        port.* = undefined;
    }
};

pub const Thread = packed struct(u32) {
    pub const current: Thread = @bitCast(@as(u32, 0xFFFF8000));

    pub const WaitError = Synchronization.WaitError;

    sync: Synchronization,

    pub fn create(entry: *fn (ctx: *anyopaque) void, ctx: *anyopaque, stack_top: [*]u8, priority: u6, processor_id: i32) UnexpectedError!Thread {
        return switch (createThread(entry, ctx, stack_top, priority, processor_id)) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn wait(thread: Thread, timeout_ns: i64) WaitError!void {
        return thread.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(threads: []const Thread, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(threads), wait_all, timeout_ns);
    }
};

pub const Process = packed struct(u32) {
    pub const current: Process = @bitCast(@as(u32, 0xFFFF8001));

    sync: Synchronization,
};

pub fn controlMemory(operation: MemoryOperation, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: MemoryPermission) Result([*]u8) {
    var mapped_addr: [*]u8 = undefined;

    const code = asm volatile ("svc 0x01"
        : [code] "={r0}" (-> ResultCode),
          [mapped_addr] "={r1}" (mapped_addr),
        : [operation] "{r0}" (operation),
          [addr0] "{r1}" (addr0),
          [addr1] "{r2}" (addr1),
          [size] "{r3}" (size),
          [permissions] "{r4}" (permissions),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, mapped_addr);
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
        : "r12", "cc", "memory"
    );

    return .of(code, .{ .memory_info = .{ .base_vaddr = base_vaddr, .size = size, .permission = permission, .state = state }, .page_info = .{ .flags = page_flags } });
}

pub fn exit() noreturn {
    asm volatile ("svc 0x03");
    unreachable;
}

pub fn getProcessAffinityMask(process: Process, processor_count: i32) Result(u8) {
    var affinity_mask: u8 = undefined;

    const code = asm volatile ("svc 0x04"
        : [code] "={r0}" (-> ResultCode),
        : [affinity_mask] "{r0}" (&affinity_mask),
          [process] "{r1}" (process),
          [processor_count] "{r2}" (processor_count),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, affinity_mask);
}

pub fn setProcessAffinityMask(process: Process, affinity_mask: *const u8, processor_count: i32) ResultCode {
    return asm volatile ("svc 0x05"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [affinity_mask] "{r1}" (affinity_mask),
          [processor_count] "{r2}" (processor_count),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getProcessIdealProcessor(process: Process) Result(i32) {
    var ideal_processor: i32 = undefined;

    const code = asm volatile ("svc 0x06"
        : [code] "={r0}" (-> ResultCode),
          [ideal_processor] "={r1}" (ideal_processor),
        : [process] "{r1}" (process),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, ideal_processor);
}

pub fn setProcessIdealProcessor(process: Process, ideal_processor: i32) ResultCode {
    return asm volatile ("svc 0x07"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [ideal_processor] "{r1}" (ideal_processor),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

// TODO: processor_id type?
pub fn createThread(entry: *fn (ctx: *anyopaque) void, ctx: *anyopaque, stack_top: [*]u8, priority: u6, processor_id: i32) Result(Thread) {
    var handle: Thread = undefined;

    const code = asm volatile ("svc 0x08"
        : [code] "={r0}" (-> ResultCode),
          [handle] "={r1}" (handle),
        : [priority] "{r0}" (priority),
          [entry] "{r1}" (entry),
          [ctx] "{r2}" (ctx),
          [stack_top] "{r3}" (stack_top),
          [processor_id] "{r4}" (processor_id),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, handle);
}

pub fn exitThread() noreturn {
    asm volatile ("svc 0x09");
    unreachable;
}

pub fn sleepThread(ns: i64) void {
    const ns_u: u64 = @bitCast(ns);

    asm volatile ("svc 0x0A"
        :
        : [ns_low] "{r0}" (@as(u32, @truncate(ns_u))),
          [ns_high] "{r1}" (@as(u32, @truncate(ns_u >> 32))),
        : "r0", "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getThreadPriority(thread: Thread) Result(u6) {
    var priority: u6 = undefined;

    const code = asm volatile ("svc 0x0B"
        : [code] "={r0}" (-> ResultCode),
          [priority] "={r1}" (priority),
        : [thread] "{r1}" (thread),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, priority);
}

pub fn setThreadPriority(thread: Thread, priority: u6) ResultCode {
    return asm volatile ("svc 0x0C"
        : [code] "={r0}" (-> ResultCode),
        : [thread] "{r0}" (thread),
          [priority] "{r1}" (priority),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getThreadAffinityMask(thread: Thread, processor_count: i32) Result(u8) {
    var affinity_mask: u8 = undefined;

    const code = asm volatile ("svc 0x0D"
        : [code] "={r0}" (-> ResultCode),
        : [affinity_mask] "{r0}" (&affinity_mask),
          [thread] "{r1}" (thread),
          [processor_count] "{r2}" (processor_count),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, affinity_mask);
}

pub fn setThreadAffinityMask(thread: Thread, affinity_mask: u8, processor_count: i32) ResultCode {
    return asm volatile ("svc 0x0E"
        : [code] "={r0}" (-> ResultCode),
        : [thread] "{r0}" (thread),
          [affinity_mask] "{r1}" (&affinity_mask),
          [processor_count] "{r2}" (processor_count),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getThreadIdealProcessor(thread: Thread) Result(i32) {
    var ideal_processor: i32 = undefined;

    const code = asm volatile ("svc 0x0F"
        : [code] "={r0}" (-> ResultCode),
          [ideal_processor] "={r1}" (ideal_processor),
        : [thread] "{r1}" (thread),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, ideal_processor);
}

pub fn setThreadIdealProcessor(thread: Process, ideal_processor: i32) ResultCode {
    return asm volatile ("svc 0x10"
        : [code] "={r0}" (-> ResultCode),
        : [thread] "{r0}" (thread),
          [ideal_processor] "{r1}" (ideal_processor),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getCurrentProcessorNumber() i32 {
    return asm volatile ("svc 0x11"
        : [processor_number] "={r0}" (-> i32),
        :
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn run(process: Process, startup_info: *const StartupInfo) ResultCode {
    return asm volatile ("svc 0x12"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [startup_info] "{r1}" (startup_info),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn createMutex(initial_locked: bool) Result(Mutex) {
    var mutex: Mutex = undefined;

    const code = asm volatile ("svc 0x13"
        : [code] "={r0}" (-> ResultCode),
          [mutex] "={r1}" (mutex),
        : [initial_locked] "{r0}" (initial_locked),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, mutex);
}

pub fn releaseMutex(handle: Mutex) ResultCode {
    return asm volatile ("svc 0x14"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (handle),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn createSemaphore(initial_count: usize, max_count: usize) Result(Semaphore) {
    var semaphore: Semaphore = undefined;

    const code = asm volatile ("svc 0x15"
        : [code] "={r0}" (-> ResultCode),
          [semaphore] "={r1}" (semaphore),
        : [initial_count] "{r0}" (initial_count),
          [max_count] "{r1}" (max_count),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, semaphore);
}

pub fn releaseSemaphore(semaphore: Semaphore, release_count: usize) Result(usize) {
    var count: usize = undefined;

    const code = asm volatile ("svc 0x16"
        : [code] "={r0}" (-> ResultCode),
          [count] "={r1}" (count),
        : [semaphore] "{r0}" (semaphore),
          [release_count] "{r1}" (release_count),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, count);
}

pub fn createEvent(reset_type: ResetType) Result(Event) {
    var event: u32 = undefined;

    const code = asm volatile ("svc 0x17"
        : [code] "={r0}" (-> ResultCode),
          [event] "={r1}" (event),
        : [reset_type] "{r0}" (reset_type),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, @bitCast(event));
}

pub fn signalEvent(event: Event) ResultCode {
    return asm volatile ("svc 0x18"
        : [code] "={r0}" (-> ResultCode),
        : [event] "{r0}" (event),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn clearEvent(event: Event) ResultCode {
    return asm volatile ("svc 0x19"
        : [code] "={r0}" (-> ResultCode),
        : [event] "{r0}" (event),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn createTimer(reset_type: ResetType) Result(Timer) {
    var timer: Timer = undefined;

    const code = asm volatile ("svc 0x1A"
        : [code] "={r0}" (-> ResultCode),
          [timer] "={r1}" (timer),
        : [reset_type] "{r0}" (reset_type),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, timer);
}

pub fn setTimer(timer: Timer, initial_ns: i64, interval: i64) ResultCode {
    const initial_ns_u: u64 = @bitCast(initial_ns);
    const interval_u: u64 = @bitCast(interval);

    return asm volatile ("svc 0x1B"
        : [code] "={r0}" (-> ResultCode),
        : [timer] "{r0}" (timer),
          [initial_ns_low] "{r2}" (@as(u32, @truncate(initial_ns_u))),
          [initial_ns_high] "{r3}" (@as(u32, @truncate(initial_ns_u >> 32))),
          [interval_low] "{r1}" (@as(u32, @truncate(interval_u))),
          [interval_high] "{r4}" (@as(u32, @truncate(interval_u >> 32))),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn cancelTimer(timer: Timer) ResultCode {
    return asm volatile ("svc 0x1C"
        : [code] "={r0}" (-> ResultCode),
        : [timer] "{r0}" (timer),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn clearTimer(timer: Timer) ResultCode {
    return asm volatile ("svc 0x1D"
        : [code] "={r0}" (-> ResultCode),
        : [timer] "{r0}" (timer),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn createMemoryBlock(address: [*]align(heap.page_size) u8, size: usize, this: MemoryPermission, other: MemoryPermission) Result(MemoryBlock) {
    var memory_block: MemoryBlock = undefined;

    const code = asm volatile ("svc 0x1E"
        : [code] "={r0}" (-> ResultCode),
          [memory_block] "={r1}" (memory_block),
        : [address] "{r0}" (address),
          [size] "{r1}" (size),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .{ .code = code, .value = memory_block };
}

pub fn mapMemoryBlock(memory_block: MemoryBlock, address: [*]align(heap.page_size) u8, this: MemoryPermission, other: MemoryPermission) ResultCode {
    return asm volatile ("svc 0x1F"
        : [code] "={r0}" (-> ResultCode),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn unmapMemoryBlock(memory_block: MemoryBlock, address: [*]align(heap.page_size) u8) ResultCode {
    return asm volatile ("svc 0x20"
        : [code] "={r0}" (-> ResultCode),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn createAddressArbiter() Result(AddressArbiter) {
    var arbiter: AddressArbiter = undefined;

    const code = asm volatile ("svc 0x21"
        : [code] "={r0}" (-> ResultCode),
          [arbiter] "={r1}" (arbiter),
        :
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, arbiter);
}

pub fn arbitrateAddress(arbiter: AddressArbiter, address: *i32, arbitration_type: Arbitration.Type, value: i32, timeout_ns: i64) ResultCode {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);

    return asm volatile ("svc 0x22"
        : [code] "={r0}" (-> ResultCode),
        : [arbiter] "{r0}" (arbiter),
          [address] "{r1}" (address),
          [type] "{r2}" (arbitration_type),
          [value] "{r3}" (value),
          [timeout_ns_low] "{r4}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_ns_high] "{r5}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn closeHandle(handle: Object) ResultCode {
    return asm volatile ("svc 0x23"
        : [code] "={r0}" (-> ResultCode),
        : [handle] "{r0}" (handle),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn waitSynchronization(sync: Synchronization, timeout_ns: i64) ResultCode {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);

    return asm volatile ("svc 0x24"
        : [code] "={r0}" (-> ResultCode),
        : [sync] "{r0}" (sync),
          [timeout_low] "{r2}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_high] "{r3}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn waitSynchronizationMultiple(handles: []const Synchronization, wait_all: bool, timeout_ns: i64) Result(usize) {
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
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, id);
}

// svc signalAndWait() stubbed 0x26

pub fn duplicateHandle(original: Object) Result(Object) {
    var duplicated: Object = undefined;

    const code = asm volatile ("svc 0x27"
        : [code] "={r0}" (-> ResultCode),
          [duplicated] "={r1}" (duplicated),
        : [original] "{r0}" (original),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, duplicated);
}

pub fn getSystemTick() i64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("svc 0x28"
        : [lo] "={r0}" (lo),
          [hi] "={r1}" (hi),
        :
        : "r2", "r3", "r12", "cc", "memory"
    );

    return @bitCast((@as(u64, hi) << 32) | lo);
}

// svc getHandleInfo() not needed currently / not really useful 0x29

pub fn getSystemInfo(info: SystemInfo.Type, param: u32) Result(i64) {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    const code = asm volatile ("svc 0x2A"
        : [code] "={r0}" (-> ResultCode),
          [lo] "={r1}" (lo),
          [hi] "={r2}" (hi),
        : [type] "{r1}" (info),
          [param] "{r2}" (param),
        : "r3", "r12", "cc", "memory"
    );

    return .of(code, @bitCast((@as(u64, hi) << 32) | lo));
}

pub fn getProcessInfo(process: Process, info: ProcessInfoType) Result(i64) {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    const code = asm volatile ("svc 0x2B"
        : [code] "={r0}" (-> ResultCode),
          [lo] "={r1}" (lo),
          [hi] "={r2}" (hi),
        : [process] "{r1}" (process),
          [type] "{r2}" (info),
        : "r3", "r12", "cc", "memory"
    );

    return .of(code, @bitCast((@as(u64, hi) << 32) | lo));
}

// svc getThreadInfo() stubbed 0x2C

pub fn connectToPort(port: [:0]const u8) Result(ClientSession) {
    var session: ClientSession = undefined;

    const code = asm volatile ("svc 0x2D"
        : [code] "={r0}" (-> ResultCode),
          [session] "={r1}" (session),
        : [unknown] "{r0}" (0),
          [port] "{r1}" (port.ptr),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, session);
}

// svc sendSyncRequest1() stubbed 0x2E
// svc sendSyncRequest2() stubbed 0x2F
// svc sendSyncRequest3() stubbed 0x30
// svc sendSyncRequest4() stubbed 0x31

pub fn sendSyncRequest(session: ClientSession) ResultCode {
    return asm volatile ("svc 0x32"
        : [code] "={r0}" (-> ResultCode),
        : [session] "{r0}" (session),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn openProcess(process_id: u32) Result(Process) {
    var process: Process = undefined;

    const code = asm volatile ("svc 0x33"
        : [code] "={r0}" (-> ResultCode),
          [process] "={r1}" (process),
        : [process_id] "{r1}" (process_id),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, process);
}

pub fn openThread(process: Process, thread_id: u32) Result(Thread) {
    var thread: Thread = undefined;

    const code = asm volatile ("svc 0x34"
        : [code] "={r0}" (-> ResultCode),
          [thread] "={r1}" (thread),
        : [process] "{r1}" (process),
          [thread_id] "{r2}" (thread_id),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, thread);
}

pub fn getProcessId(process: Process) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x35"
        : [code] "={r0}" (-> ResultCode),
          [id] "={r1}" (id),
        : [process] "{r1}" (process),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, id);
}

pub fn getThreadProcessId(thread: Thread) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x36"
        : [code] "={r0}" (-> ResultCode),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, id);
}

pub fn getThreadId(thread: Thread) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x37"
        : [code] "={r0}" (-> ResultCode),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, id);
}

pub fn getResourceLimit(process: Process) Result(ResouceLimit) {
    var resource_limit: ResouceLimit = undefined;

    const code = asm volatile ("svc 0x38"
        : [code] "={r0}" (-> ResultCode),
          [resource_limit] "={r1}" (resource_limit),
        : [process] "{r1}" (process),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, resource_limit);
}

pub fn getResourceLimitLimitValues(values: []i64, resource_limit: ResouceLimit, names: []LimitableResource) ResultCode {
    std.debug.assert(values.len == names.len);

    return asm volatile ("svc 0x39"
        : [code] "={r0}" (-> ResultCode),
        : [values_ptr] "{r0}" (values.ptr),
          [resource_limit] "{r1}" (resource_limit),
          [names_ptr] "{r2}" (names.ptr),
          [names_len] "{r3}" (names.len),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn getResourceLimitCurrentValues(values: []i64, resource_limit: ResouceLimit, names: []LimitableResource) ResultCode {
    std.debug.assert(values.len == names.len);

    return asm volatile ("svc 0x3A"
        : [code] "={r0}" (-> ResultCode),
        : [values_ptr] "{r0}" (values.ptr),
          [resource_limit] "{r1}" (resource_limit),
          [names_ptr] "{r2}" (names.ptr),
          [names_len] "{r3}" (names.len),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

// svc getThreadContext() stubbed 0x3B

pub fn breakExecution(reason: BreakReason) void {
    asm volatile ("svc 0x3C"
        :
        : [reason] "{r0}" (reason),
        : "r0", "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn breakDebug(reason: BreakReason, cro_info: []const u8) void {
    asm volatile ("svc 0x3C"
        :
        : [reason] "{r0}" (reason),
          [cro_info] "{r1}" (cro_info.ptr),
          [cro_info_size] "{r2}" (cro_info.len),
        : "r0", "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn outputDebugString(str: []const u8) void {
    asm volatile ("svc 0x3D"
        :
        : [str_ptr] "{r0}" (str.ptr),
          [str_len] "{r1}" (str.len),
        : "r0", "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

// svc controlPerformanceCounter() TODO: 0x3E

pub fn createPort(name: [:0]const u8, max_sessions: i16) Result(Port) {
    var server_port: ServerPort = undefined;
    var client_port: ClientPort = undefined;

    const code = asm volatile ("svc 0x47"
        : [code] "={r0}" (-> ResultCode),
          [server_port] "={r1}" (server_port),
          [client_port] "={r2}" (client_port),
        : [name] "{r2}" (name),
          [max_sessions] "{r3}" (max_sessions),
        : "r3", "r12", "cc", "memory"
    );

    return .of(code, .{ .server = server_port, .client = client_port });
}

pub fn createSessionToPort(port: ClientPort) Result(ClientSession) {
    var session: ClientSession = undefined;

    const code = asm volatile ("svc 0x48"
        : [code] "={r0}" (-> ResultCode),
          [session] "={r1}" (session),
        : [port] "{r1}" (port),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, session);
}

pub fn createSession() Result(Session) {
    var server_session: ServerSession = undefined;
    var client_session: ClientSession = undefined;

    const code = asm volatile ("svc 0x49"
        : [code] "={r0}" (-> ResultCode),
          [server_session] "={r1}" (server_session),
          [client_session] "={r2}" (client_session),
        :
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, .{ .server = server_session, .client = client_session });
}

pub fn acceptSession(port: ServerPort) Result(ServerSession) {
    var session: ServerSession = undefined;

    const code = asm volatile ("svc 0x4A"
        : [code] "={r0}" (-> ResultCode),
          [session] "={r1}" (session),
        : [port] "{r1}" (port),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, session);
}

// svc replyAndReceive1() stubbed 0x4B
// svc replyAndReceive2() stubbed 0x4C
// svc replyAndReceive3() stubbed 0x4D
// svc replyAndReceive4() stubbed 0x4E

pub fn replyAndReceive(port_sessions: []Object, reply_target: ServerSession) Result(i32) {
    var index: i32 = undefined;

    const code = asm volatile ("svc 0x4F"
        : [code] "={r0}" (-> ResultCode),
          [index] "={r1}" (index),
        : [port_sessions] "{r1}" (port_sessions.ptr),
          [port_sessions_len] "{r2}" (port_sessions.len),
          [reply_target] "{r3}" (reply_target),
        : "r2", "r3", "r12", "cc", "memory"
    );

    return .of(code, index);
}

pub fn bindInterrupt(id: InterruptId, int: Interruptable, priority: i32, isHighActive: bool) ResultCode {
    return asm volatile ("svc 0x50"
        : [code] "={r0}" (-> ResultCode),
        : [id] "{r0}" (id),
          [int] "{r1}" (int),
          [priority] "{r2}" (priority),
          [isHighActive] "{r3}" (isHighActive),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn unbindInterrupt(id: InterruptId, int: Interruptable) ResultCode {
    return asm volatile ("svc 0x51"
        : [code] "={r0}" (-> ResultCode),
        : [id] "{r0}" (id),
          [int] "{r1}" (int),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn invalidateProcessDataCache(process: Process, data: []u8) ResultCode {
    return asm volatile ("svc 0x52"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn storeProcessDataCache(process: Process, data: []const u8) ResultCode {
    return asm volatile ("svc 0x53"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

pub fn flushProcessDataCache(process: Process, data: []const u8) ResultCode {
    return asm volatile ("svc 0x54"
        : [code] "={r0}" (-> ResultCode),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : "r1", "r2", "r3", "r12", "cc", "memory"
    );
}

// TODO: dma svc's 0x55-0x58

// svc setGpuProt() TODO: 0x59
// svc setWifiEnabled() TODO: 0x5A

// TODO: debug svc's 0x60-0x6D
// TODO: proccess handling svc's 0x70-0x7D

pub fn breakpoint() noreturn {
    asm volatile ("svc 0xFF" ::: "r0", "r1", "r2", "r3", "r12", "cc", "memory");
}

pub const UnexpectedError = error{Unexpected};
pub fn unexpectedResult(code: ResultCode) UnexpectedError {
    // OutputDebugString?
    _ = code;
    return error.Unexpected;
}

comptime {
    // TODO: Testing instead of relying on this!

    // std.testing.refAllDeclsRecursive(@This());
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
