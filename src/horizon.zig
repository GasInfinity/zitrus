pub fn Result(T: type) type {
    // TODO: Last rewrite of result. This must be a struct!
    // However we can't switch on structs so we should just add a helper fn for ergonomics.
    return union(enum) {
        const Res = @This();

        pub const Success = struct { code: result.Code, value: T };

        success: Success,
        failure: result.Code,

        pub inline fn of(code: result.Code, value: T) Res {
            return if (code.isSuccess()) .{ .success = .{ .code = code, .value = value } } else .{ .failure = code };
        }
    };
}

pub const LimitableResource = enum(u32) {
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
    pub const TimeoutValue = extern struct { value: i32, timeout: i64 };

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

// TODO: Even though we have tests, do not ignore possible errors, use unreachable instead! (wait until switching on packed structs is available maybe)
pub const Object = enum(u32) {
    null = 0,
    _,

    pub fn dupe(obj: Object) !Object {
        return switch (duplicateHandle(obj)) {
            .success => |r| r.value,
            // FIXME: This CAN fail
            .failure => unreachable,
        };
    }
};

pub const ResouceLimit = packed struct(u32) {
    obj: Object,
};

pub const AddressArbiter = packed struct(u32) {
    obj: Object,

    pub fn create() UnexpectedError!AddressArbiter {
        return switch (createAddressArbiter()) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code),
        };
    }

    pub fn arbitrate(arbiter: AddressArbiter, address: *i32, arbitration: Arbitration) !void {
        const value: i32, const timeout_ns: i64 = switch (arbitration) {
            inline .signal, .wait_if_less_than, .decrement_and_wait_if_less_than => |value| .{ value, 0 },
            inline .wait_if_less_than_timeout, .decrement_and_wait_if_less_than_timeout => |timeout_value| .{ timeout_value.value, timeout_value.timeout },
        };

        const res = arbitrateAddress(arbiter, address, std.meta.activeTag(arbitration), value, timeout_ns);

        // TODO: switch on packed struct when implemented
        if (!res.isSuccess()) {
            if (res == result.Code.timeout) {
                return error.Timeout;
            }

            unreachable; // NOTE: Basically invalid address
        }
    }

    pub fn close(arbiter: AddressArbiter) void {
        _ = closeHandle(arbiter.obj);
    }
};

pub const Synchronization = packed struct(u32) {
    pub const CreationError = error{OutOfSynchronizationObjects} || UnexpectedError;
    pub const WaitError = error{Timeout} || UnexpectedError;

    obj: Object,

    pub fn checkResult(comptime T: type, res: Result(T)) CreationError!T {
        return switch (res) {
            .success => |s| s.value,
            .failure => |code| if (code == result.Code.out_of_sync_objects) error.OutOfSynchronizationObjects else unexpectedResult(code),
        };
    }

    pub fn wait(sync: Synchronization, timeout_ns: i64) WaitError!void {
        const sync_result = waitSynchronization(sync, timeout_ns);

        if (sync_result == result.Code.timeout) {
            return error.Timeout;
        }

        if (!sync_result.isSuccess()) {
            return unexpectedResult(sync_result);
        }
    }

    pub fn waitMultiple(syncs: []const Synchronization, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return switch (waitSynchronizationMultiple(@ptrCast(syncs), wait_all, timeout_ns)) {
            .success => |s| if (s.code == result.Code.timeout) error.Timeout else s.value,
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

    pub fn close(mutex: Mutex) void {
        _ = closeHandle(mutex.sync.obj);
    }
};

pub const Semaphore = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    int: Interruptable,

    pub fn create(initial_count: usize, max_count: usize) CreationError!Semaphore {
        return Synchronization.checkResult(Semaphore, createSemaphore(initial_count, max_count));
    }

    // TODO: Same as with above, properly handle errors with unreachable
    pub fn release(semaphore: Semaphore, count: isize) usize {
        return releaseSemaphore(semaphore, count).success.value;
    }

    pub fn wait(semaphore: Semaphore, timeout_ns: i64) WaitError!void {
        return semaphore.int.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(semaphore: []const Semaphore, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(semaphore), wait_all, timeout_ns);
    }

    pub fn close(semaphore: Semaphore) void {
        _ = closeHandle(semaphore.int.sync.obj);
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

    pub fn dupe(ev: Event) !Event {
        return @bitCast(@intFromEnum(try ev.int.sync.obj.dupe()));
    }

    pub fn wait(ev: Event, timeout_ns: i64) WaitError!void {
        return ev.int.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(evs: []const Event, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(evs), wait_all, timeout_ns);
    }

    pub fn close(ev: Event) void {
        _ = closeHandle(ev.int.sync.obj);
    }
};

pub const Timer = packed struct(u32) {
    pub const CreationError = Synchronization.CreationError;
    pub const WaitError = Synchronization.WaitError;

    sync: Synchronization,

    pub fn create(reset_type: ResetType) CreationError!Timer {
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

    pub fn dupe(ev: Timer) !Timer {
        return @bitCast(@intFromEnum(try ev.sync.obj.dupe()));
    }

    pub fn wait(timer: Timer, timeout_ns: i64) WaitError!void {
        return timer.sync.wait(timeout_ns);
    }

    pub fn waitMultiple(timers: []const Timer, wait_all: bool, timeout_ns: i64) WaitError!usize {
        return Synchronization.waitMultiple(@ptrCast(timers), wait_all, timeout_ns);
    }

    pub fn close(timer: Timer) void {
        _ = closeHandle(timer.sync.obj);
    }
};

pub const MemoryBlock = packed struct(u32) {
    pub const Error = error{ InvalidPermissions, Unexpected };
    pub const CreationError = error{OutOfMemoryBlocks} || Error;

    obj: Object,

    pub fn create(address: [*]align(heap.page_size) u8, size: u32, this: MemoryPermission, other: MemoryPermission) CreationError!MemoryBlock {
        return switch (createMemoryBlock(address, size, this, other)) {
            .success => |s| s.value,
            .failure => |code| if (code == result.Code.out_of_memory_blocks) error.OutOfMemoryBlocks else unexpectedResult(code),
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

    pub fn close(mem: MemoryBlock) void {
        _ = closeHandle(mem.obj);
    }
};

pub const ServerSession = packed struct(u32) {
    sync: Synchronization,

    pub fn close(session: ServerSession) void {
        _ = closeHandle(session.sync.obj);
    }
};

pub const ClientSession = packed struct(u32) {
    pub const ConnectionError = UnexpectedError || error{NotFound};
    pub const RequestError = UnexpectedError || error{ConnectionClosed};

    sync: Synchronization,

    pub fn connect(port: [:0]const u8) ConnectionError!ClientSession {
        return switch (connectToPort(port)) {
            .success => |s| s.value,
            .failure => |code| if (code == result.Code.port_not_found) error.NotFound else unexpectedResult(code),
        };
    }

    pub fn sendRequest(session: ClientSession) RequestError!void {
        const req_result = sendSyncRequest(session);

        if (!req_result.isSuccess()) {
            if (req_result == result.Code.session_closed) {
                return error.ConnectionClosed;
            }

            return unexpectedResult(req_result);
        }
    }

    pub fn close(session: ClientSession) void {
        _ = closeHandle(session.sync.obj);
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

    pub fn close(session: Session) void {
        session.server.close();
        session.client.close();
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

    pub fn close(port: ServerPort) void {
        _ = closeHandle(port.sync.obj);
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

    pub fn close(port: ClientPort) void {
        _ = closeHandle(port.sync.obj);
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

    pub fn close(port: *Port) void {
        port.server.close();
        port.client.close();
    }
};

pub const Thread = packed struct(u32) {
    pub const Priority = enum(u6) {
        pub const highest: Priority = .priority(0x00);
        pub const highest_user: Priority = .priority(0x18);
        pub const lowest: Priority = .priority(0x3F);

        _,

        pub fn priority(value: u6) Priority {
            return @enumFromInt(value);
        }
    };

    pub const Processor = enum(i3) {
        pub const app: Processor = .@"0";
        pub const sys: Processor = .@"1";

        default = -2,
        any = -1,

        @"0" = 0,
        @"1",
        @"2",
        @"3",
    };

    pub const current: Thread = @bitCast(@as(u32, 0xFFFF8000));

    pub const WaitError = Synchronization.WaitError;

    sync: Synchronization,

    pub fn create(entry: *const fn (ctx: ?*anyopaque) callconv(.c) noreturn, ctx: ?*anyopaque, stack_top: [*]u8, priority: Priority, processor_id: Processor) UnexpectedError!Thread {
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

    pub fn close(thread: Thread) void {
        _ = closeHandle(thread.sync.obj);
    }
};

pub const Process = packed struct(u32) {
    pub const current: Process = @bitCast(@as(u32, 0xFFFF8001));

    sync: Synchronization,
};

pub fn outputDebugWriter(buffer: []u8) std.Io.Writer {
    return .{
        .vtable = &.{
            .drain = outputDebugDrain,
        },
        .buffer = buffer,
    };
}

fn outputDebugDrain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    outputDebugString(w.buffered()); 
    w.end = 0;

    var n: usize = 0;
    for (data[0..data.len - 1]) |slice| {
        outputDebugString(slice);
        n += slice.len;
    }

    for (0..splat) |_| {
        outputDebugString(data[data.len - 1]);
    }

    return n + splat * data[data.len - 1].len;
}

pub fn controlMemory(operation: MemoryOperation, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: MemoryPermission) Result([*]align(heap.page_size) u8) {
    var mapped_addr: [*]align(heap.page_size) u8 = undefined;

    const code = asm volatile ("svc 0x01"
        : [code] "={r0}" (-> result.Code),
          [mapped_addr] "={r1}" (mapped_addr),
        : [operation] "{r0}" (operation),
          [addr0] "{r1}" (addr0),
          [addr1] "{r2}" (addr1),
          [size] "{r3}" (size),
          [permissions] "{r4}" (permissions),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, mapped_addr);
}

pub fn queryMemory(address: *anyopaque) Result(MemoryQuery) {
    var base_vaddr: *anyopaque = undefined;
    var size: usize = undefined;
    var permission: MemoryPermission = undefined;
    var state: MemoryState = undefined;
    var page_flags: PageFlags = undefined;

    const code = asm volatile ("svc 0x02"
        : [code] "={r0}" (-> result.Code),
          [base_vaddr] "={r1}" (base_vaddr),
          [size] "={r2}" (size),
          [permission] "={r3}" (permission),
          [state] "={r4}" (state),
          [page_flags] "={r5}" (page_flags),
        : [handle] "{r2}" (address),
        : .{ .r12 = true, .cpsr = true, .memory = true });

    return .of(code, .{ .memory_info = .{ .base_vaddr = base_vaddr, .size = size, .permission = permission, .state = state }, .page_info = .{ .flags = page_flags } });
}

pub fn exit() noreturn {
    asm volatile ("svc 0x03");
    unreachable;
}

pub fn getProcessAffinityMask(process: Process, processor_count: i32) Result(u8) {
    var affinity_mask: u8 = undefined;

    const code = asm volatile ("svc 0x04"
        : [code] "={r0}" (-> result.Code),
        : [affinity_mask] "{r0}" (&affinity_mask),
          [process] "{r1}" (process),
          [processor_count] "{r2}" (processor_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, affinity_mask);
}

pub fn setProcessAffinityMask(process: Process, affinity_mask: *const u8, processor_count: i32) result.Code {
    return asm volatile ("svc 0x05"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [affinity_mask] "{r1}" (affinity_mask),
          [processor_count] "{r2}" (processor_count),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getProcessIdealProcessor(process: Process) Result(i32) {
    var ideal_processor: i32 = undefined;

    const code = asm volatile ("svc 0x06"
        : [code] "={r0}" (-> result.Code),
          [ideal_processor] "={r1}" (ideal_processor),
        : [process] "{r1}" (process),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, ideal_processor);
}

pub fn setProcessIdealProcessor(process: Process, ideal_processor: i32) result.Code {
    return asm volatile ("svc 0x07"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [ideal_processor] "{r1}" (ideal_processor),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createThread(entry: *const fn (ctx: ?*anyopaque) callconv(.c) noreturn, ctx: ?*anyopaque, stack_top: [*]u8, priority: Thread.Priority, processor_id: Thread.Processor) Result(Thread) {
    var handle: Thread = undefined;

    const code = asm volatile ("svc 0x08"
        : [code] "={r0}" (-> result.Code),
          [handle] "={r1}" (handle),
        : [priority] "{r0}" (@as(u32, @intFromEnum(priority))),
          [entry] "{r1}" (entry),
          [ctx] "{r2}" (ctx),
          [stack_top] "{r3}" (stack_top),
          [processor_id] "{r4}" (@as(i32, @intFromEnum(processor_id))),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

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
        : .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getThreadPriority(thread: Thread) Result(u6) {
    var priority: u6 = undefined;

    const code = asm volatile ("svc 0x0B"
        : [code] "={r0}" (-> result.Code),
          [priority] "={r1}" (priority),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, priority);
}

pub fn setThreadPriority(thread: Thread, priority: u6) result.Code {
    return asm volatile ("svc 0x0C"
        : [code] "={r0}" (-> result.Code),
        : [thread] "{r0}" (thread),
          [priority] "{r1}" (priority),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getThreadAffinityMask(thread: Thread, processor_count: i32) Result(u8) {
    var affinity_mask: u8 = undefined;

    const code = asm volatile ("svc 0x0D"
        : [code] "={r0}" (-> result.Code),
        : [affinity_mask] "{r0}" (&affinity_mask),
          [thread] "{r1}" (thread),
          [processor_count] "{r2}" (processor_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, affinity_mask);
}

pub fn setThreadAffinityMask(thread: Thread, affinity_mask: u8, processor_count: i32) result.Code {
    return asm volatile ("svc 0x0E"
        : [code] "={r0}" (-> result.Code),
        : [thread] "{r0}" (thread),
          [affinity_mask] "{r1}" (&affinity_mask),
          [processor_count] "{r2}" (processor_count),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getThreadIdealProcessor(thread: Thread) Result(i32) {
    var ideal_processor: i32 = undefined;

    const code = asm volatile ("svc 0x0F"
        : [code] "={r0}" (-> result.Code),
          [ideal_processor] "={r1}" (ideal_processor),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, ideal_processor);
}

pub fn setThreadIdealProcessor(thread: Process, ideal_processor: i32) result.Code {
    return asm volatile ("svc 0x10"
        : [code] "={r0}" (-> result.Code),
        : [thread] "{r0}" (thread),
          [ideal_processor] "{r1}" (ideal_processor),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getCurrentProcessorNumber() i32 {
    return asm volatile ("svc 0x11"
        : [processor_number] "={r0}" (-> i32),
        :
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn run(process: Process, startup_info: *const StartupInfo) result.Code {
    return asm volatile ("svc 0x12"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [startup_info] "{r1}" (startup_info),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createMutex(initial_locked: bool) Result(Mutex) {
    var mutex: Mutex = undefined;

    const code = asm volatile ("svc 0x13"
        : [code] "={r0}" (-> result.Code),
          [mutex] "={r1}" (mutex),
        : [initial_locked] "{r1}" (@as(u32, @intFromBool(initial_locked))),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, mutex);
}

pub fn releaseMutex(handle: Mutex) result.Code {
    return asm volatile ("svc 0x14"
        : [code] "={r0}" (-> result.Code),
        : [handle] "{r0}" (handle),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createSemaphore(initial_count: usize, max_count: usize) Result(Semaphore) {
    var semaphore: Semaphore = undefined;

    const code = asm volatile ("svc 0x15"
        : [code] "={r0}" (-> result.Code),
          [semaphore] "={r1}" (semaphore),
        : [initial_count] "{r1}" (initial_count),
          [max_count] "{r2}" (max_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, semaphore);
}

pub fn releaseSemaphore(semaphore: Semaphore, release_count: isize) Result(usize) {
    var count: usize = undefined;

    const code = asm volatile ("svc 0x16"
        : [code] "={r0}" (-> result.Code),
          [count] "={r1}" (count),
        : [semaphore] "{r1}" (semaphore),
          [release_count] "{r2}" (release_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, count);
}

pub fn createEvent(reset_type: ResetType) Result(Event) {
    var event: u32 = undefined;

    const code = asm volatile ("svc 0x17"
        : [code] "={r0}" (-> result.Code),
          [event] "={r1}" (event),
        : [reset_type] "{r1}" (reset_type),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, @bitCast(event));
}

pub fn signalEvent(event: Event) result.Code {
    return asm volatile ("svc 0x18"
        : [code] "={r0}" (-> result.Code),
        : [event] "{r0}" (event),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn clearEvent(event: Event) result.Code {
    return asm volatile ("svc 0x19"
        : [code] "={r0}" (-> result.Code),
        : [event] "{r0}" (event),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createTimer(reset_type: ResetType) Result(Timer) {
    var timer: Timer = undefined;

    const code = asm volatile ("svc 0x1A"
        : [code] "={r0}" (-> result.Code),
          [timer] "={r1}" (timer),
        : [reset_type] "{r1}" (reset_type),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, timer);
}

pub fn setTimer(timer: Timer, initial_ns: i64, interval: i64) result.Code {
    const initial_ns_u: u64 = @bitCast(initial_ns);
    const interval_u: u64 = @bitCast(interval);

    return asm volatile ("svc 0x1B"
        : [code] "={r0}" (-> result.Code),
        : [timer] "{r0}" (timer),
          [initial_ns_low] "{r2}" (@as(u32, @truncate(initial_ns_u))),
          [initial_ns_high] "{r3}" (@as(u32, @truncate(initial_ns_u >> 32))),
          [interval_low] "{r1}" (@as(u32, @truncate(interval_u))),
          [interval_high] "{r4}" (@as(u32, @truncate(interval_u >> 32))),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn cancelTimer(timer: Timer) result.Code {
    return asm volatile ("svc 0x1C"
        : [code] "={r0}" (-> result.Code),
        : [timer] "{r0}" (timer),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn clearTimer(timer: Timer) result.Code {
    return asm volatile ("svc 0x1D"
        : [code] "={r0}" (-> result.Code),
        : [timer] "{r0}" (timer),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createMemoryBlock(address: [*]align(heap.page_size) u8, size: u32, this: MemoryPermission, other: MemoryPermission) Result(MemoryBlock) {
    var memory_block: MemoryBlock = undefined;

    const code = asm volatile ("svc 0x1E"
        : [code] "={r0}" (-> result.Code),
          [memory_block] "={r1}" (memory_block),
        : [other_permissions] "{r0}" (other),
          [address] "{r1}" (address),
          [size] "{r2}" (size),
          [permissions] "{r3}" (this),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, memory_block);
}

pub fn mapMemoryBlock(memory_block: MemoryBlock, address: [*]align(heap.page_size) u8, this: MemoryPermission, other: MemoryPermission) result.Code {
    return asm volatile ("svc 0x1F"
        : [code] "={r0}" (-> result.Code),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
          [permissions] "{r2}" (this),
          [other_permissions] "{r3}" (other),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn unmapMemoryBlock(memory_block: MemoryBlock, address: [*]align(heap.page_size) u8) result.Code {
    return asm volatile ("svc 0x20"
        : [code] "={r0}" (-> result.Code),
        : [memory_block] "{r0}" (memory_block),
          [address] "{r1}" (address),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createAddressArbiter() Result(AddressArbiter) {
    var arbiter: AddressArbiter = undefined;

    const code = asm volatile ("svc 0x21"
        : [code] "={r0}" (-> result.Code),
          [arbiter] "={r1}" (arbiter),
        :
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, arbiter);
}

pub fn arbitrateAddress(arbiter: AddressArbiter, address: *i32, arbitration_type: Arbitration.Type, value: i32, timeout_ns: i64) result.Code {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);

    return asm volatile ("svc 0x22"
        : [code] "={r0}" (-> result.Code),
        : [arbiter] "{r0}" (arbiter),
          [address] "{r1}" (address),
          [type] "{r2}" (arbitration_type),
          [value] "{r3}" (value),
          [timeout_ns_low] "{r4}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_ns_high] "{r5}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn closeHandle(handle: Object) result.Code {
    return asm volatile ("svc 0x23"
        : [code] "={r0}" (-> result.Code),
        : [handle] "{r0}" (handle),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn waitSynchronization(sync: Synchronization, timeout_ns: i64) result.Code {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);

    return asm volatile ("svc 0x24"
        : [code] "={r0}" (-> result.Code),
        : [sync] "{r0}" (sync),
          [timeout_low] "{r2}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_high] "{r3}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn waitSynchronizationMultiple(handles: []const Synchronization, wait_all: bool, timeout_ns: i64) Result(usize) {
    const timeout_ns_u: u64 = @bitCast(timeout_ns);
    var id: usize = 0;

    const code = asm volatile ("svc 0x25"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [handles] "{r1}" (handles.ptr),
          [handles_len] "{r2}" (handles.len),
          [wait_all] "{r3}" (wait_all),
          [timeout_low] "{r0}" (@as(u32, @truncate(timeout_ns_u))),
          [timeout_high] "{r4}" (@as(u32, @truncate(timeout_ns_u >> 32))),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

// svc signalAndWait() stubbed 0x26

pub fn duplicateHandle(original: Object) Result(Object) {
    var duplicated: Object = undefined;

    const code = asm volatile ("svc 0x27"
        : [code] "={r0}" (-> result.Code),
          [duplicated] "={r1}" (duplicated),
        : [original] "{r1}" (original),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, duplicated);
}

pub fn getSystemTick() i64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("svc 0x28"
        : [lo] "={r0}" (lo),
          [hi] "={r1}" (hi),
        :
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return @bitCast((@as(u64, hi) << 32) | lo);
}

// svc getHandleInfo() not needed currently / not really useful 0x29

pub fn getSystemInfo(info: SystemInfo.Type, param: u32) Result(i64) {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    const code = asm volatile ("svc 0x2A"
        : [code] "={r0}" (-> result.Code),
          [lo] "={r1}" (lo),
          [hi] "={r2}" (hi),
        : [type] "{r1}" (info),
          [param] "{r2}" (param),
        : .{ .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, @bitCast((@as(u64, hi) << 32) | lo));
}

pub fn getProcessInfo(process: Process, info: ProcessInfoType) Result(i64) {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    const code = asm volatile ("svc 0x2B"
        : [code] "={r0}" (-> result.Code),
          [lo] "={r1}" (lo),
          [hi] "={r2}" (hi),
        : [process] "{r1}" (process),
          [type] "{r2}" (info),
        : .{ .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, @bitCast((@as(u64, hi) << 32) | lo));
}

// svc getThreadInfo() stubbed 0x2C

pub fn connectToPort(port: [:0]const u8) Result(ClientSession) {
    var session: ClientSession = undefined;

    const code = asm volatile ("svc 0x2D"
        : [code] "={r0}" (-> result.Code),
          [session] "={r1}" (session),
        : [port] "{r1}" (port.ptr),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, session);
}

// svc sendSyncRequest1() stubbed 0x2E
// svc sendSyncRequest2() stubbed 0x2F
// svc sendSyncRequest3() stubbed 0x30
// svc sendSyncRequest4() stubbed 0x31

pub fn sendSyncRequest(session: ClientSession) result.Code {
    return asm volatile ("svc 0x32"
        : [code] "={r0}" (-> result.Code),
        : [session] "{r0}" (session),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn openProcess(process_id: u32) Result(Process) {
    var process: Process = undefined;

    const code = asm volatile ("svc 0x33"
        : [code] "={r0}" (-> result.Code),
          [process] "={r1}" (process),
        : [process_id] "{r1}" (process_id),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, process);
}

pub fn openThread(process: Process, thread_id: u32) Result(Thread) {
    var thread: Thread = undefined;

    const code = asm volatile ("svc 0x34"
        : [code] "={r0}" (-> result.Code),
          [thread] "={r1}" (thread),
        : [process] "{r1}" (process),
          [thread_id] "{r2}" (thread_id),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, thread);
}

pub fn getProcessId(process: Process) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x35"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [process] "{r1}" (process),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getThreadProcessId(thread: Thread) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x36"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getThreadId(thread: Thread) Result(u32) {
    var id: u32 = undefined;

    const code = asm volatile ("svc 0x37"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getResourceLimit(process: Process) Result(ResouceLimit) {
    var resource_limit: ResouceLimit = undefined;

    const code = asm volatile ("svc 0x38"
        : [code] "={r0}" (-> result.Code),
          [resource_limit] "={r1}" (resource_limit),
        : [process] "{r1}" (process),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, resource_limit);
}

pub fn getResourceLimitLimitValues(values: []i64, resource_limit: ResouceLimit, names: []LimitableResource) result.Code {
    std.debug.assert(values.len == names.len);

    return asm volatile ("svc 0x39"
        : [code] "={r0}" (-> result.Code),
        : [values_ptr] "{r0}" (values.ptr),
          [resource_limit] "{r1}" (resource_limit),
          [names_ptr] "{r2}" (names.ptr),
          [names_len] "{r3}" (names.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getResourceLimitCurrentValues(values: []i64, resource_limit: ResouceLimit, names: []LimitableResource) result.Code {
    std.debug.assert(values.len == names.len);

    return asm volatile ("svc 0x3A"
        : [code] "={r0}" (-> result.Code),
        : [values_ptr] "{r0}" (values.ptr),
          [resource_limit] "{r1}" (resource_limit),
          [names_ptr] "{r2}" (names.ptr),
          [names_len] "{r3}" (names.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

// svc getThreadContext() stubbed 0x3B

pub fn breakExecution(reason: BreakReason) void {
    asm volatile ("svc 0x3C"
        :
        : [reason] "{r0}" (reason),
        : .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn breakDebug(reason: BreakReason, cro_info: []const u8) void {
    asm volatile ("svc 0x3C"
        :
        : [reason] "{r0}" (reason),
          [cro_info] "{r1}" (cro_info.ptr),
          [cro_info_size] "{r2}" (cro_info.len),
        : .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn outputDebugString(str: []const u8) void {
    asm volatile ("svc 0x3D"
        :
        : [str_ptr] "{r0}" (str.ptr),
          [str_len] "{r1}" (str.len),
        : .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

// svc controlPerformanceCounter() TODO: 0x3E

pub fn createPort(name: [:0]const u8, max_sessions: i16) Result(Port) {
    var server_port: ServerPort = undefined;
    var client_port: ClientPort = undefined;

    const code = asm volatile ("svc 0x47"
        : [code] "={r0}" (-> result.Code),
          [server_port] "={r1}" (server_port),
          [client_port] "={r2}" (client_port),
        : [name] "{r2}" (name),
          [max_sessions] "{r3}" (max_sessions),
        : .{ .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, .{ .server = server_port, .client = client_port });
}

pub fn createSessionToPort(port: ClientPort) Result(ClientSession) {
    var session: ClientSession = undefined;

    const code = asm volatile ("svc 0x48"
        : [code] "={r0}" (-> result.Code),
          [session] "={r1}" (session),
        : [port] "{r1}" (port),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, session);
}

pub fn createSession() Result(Session) {
    var server_session: ServerSession = undefined;
    var client_session: ClientSession = undefined;

    const code = asm volatile ("svc 0x49"
        : [code] "={r0}" (-> result.Code),
          [server_session] "={r1}" (server_session),
          [client_session] "={r2}" (client_session),
        :
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, .{ .server = server_session, .client = client_session });
}

pub fn acceptSession(port: ServerPort) Result(ServerSession) {
    var session: ServerSession = undefined;

    const code = asm volatile ("svc 0x4A"
        : [code] "={r0}" (-> result.Code),
          [session] "={r1}" (session),
        : [port] "{r1}" (port),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, session);
}

// svc replyAndReceive1() stubbed 0x4B
// svc replyAndReceive2() stubbed 0x4C
// svc replyAndReceive3() stubbed 0x4D
// svc replyAndReceive4() stubbed 0x4E

pub fn replyAndReceive(port_sessions: []Object, reply_target: ServerSession) Result(i32) {
    var index: i32 = undefined;

    const code = asm volatile ("svc 0x4F"
        : [code] "={r0}" (-> result.Code),
          [index] "={r1}" (index),
        : [port_sessions] "{r1}" (port_sessions.ptr),
          [port_sessions_len] "{r2}" (port_sessions.len),
          [reply_target] "{r3}" (reply_target),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, index);
}

pub fn bindInterrupt(id: InterruptId, int: Interruptable, priority: i32, isHighActive: bool) result.Code {
    return asm volatile ("svc 0x50"
        : [code] "={r0}" (-> result.Code),
        : [id] "{r0}" (id),
          [int] "{r1}" (int),
          [priority] "{r2}" (priority),
          [isHighActive] "{r3}" (isHighActive),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn unbindInterrupt(id: InterruptId, int: Interruptable) result.Code {
    return asm volatile ("svc 0x51"
        : [code] "={r0}" (-> result.Code),
        : [id] "{r0}" (id),
          [int] "{r1}" (int),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn invalidateProcessDataCache(process: Process, data: []u8) result.Code {
    return asm volatile ("svc 0x52"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn storeProcessDataCache(process: Process, data: []const u8) result.Code {
    return asm volatile ("svc 0x53"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn flushProcessDataCache(process: Process, data: []const u8) result.Code {
    return asm volatile ("svc 0x54"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (process),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

// TODO: dma svc's 0x55-0x58

// svc setGpuProt() TODO: 0x59
// svc setWifiEnabled() TODO: 0x5A

// TODO: debug svc's 0x60-0x6D
// TODO: proccess handling svc's 0x70-0x7D

pub fn breakpoint() noreturn {
    asm volatile ("svc 0xFF" ::: .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

var sbrk_heap_top: usize = memory.heap_begin;

pub fn sbrk(n: usize) usize {
    const aligned_n = std.mem.alignForward(usize, n, heap.page_size);
    const current_heap_top = sbrk_heap_top;

    sbrk_heap_top += aligned_n;
    return switch (controlMemory(.{
        .area = .all,
        .fundamental_operation = .commit,
        .linear = false,
    }, @ptrFromInt(current_heap_top), null, aligned_n, .rw)) {
        .failure => 0,
        .success => current_heap_top,
    };
}

pub const UnexpectedError = error{Unexpected};
pub fn unexpectedResult(code: result.Code) UnexpectedError {
    // OutputDebugString?
    var buf: [256]u8 = undefined;
    outputDebugString(std.fmt.bufPrint(&buf, "unexpected result: {} ({})", .{ @as(u32, @bitCast(code)), code }) catch unreachable);
    return error.Unexpected;
}

comptime {
    _ = ipc;
    _ = fmt;
}

pub const heap = @import("horizon/heap.zig");
pub const result = @import("horizon/result.zig");
pub const environment = @import("horizon/environment.zig");
pub const memory = @import("horizon/memory.zig");
pub const config = @import("horizon/config.zig");
pub const ipc = @import("horizon/ipc.zig");
pub const tls = @import("horizon/tls.zig");
pub const fmt = @import("horizon/fmt.zig");

pub const testing = @import("horizon/testing.zig");

pub const ServiceManager = @import("horizon/ServiceManager.zig");
pub const ErrorDisplayManager = @import("horizon/ErrorDisplayManager.zig");

pub const services = @import("horizon/services.zig");

const std = @import("std");
