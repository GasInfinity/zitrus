//! Represents the `Horizon` support layer. It implements all known syscalls,
//! services, formats, etc... used by the OS.
//!
//! The API can be broken down like this:
//!
//! ## `Init` - High-level initialization abstraction
//!
//! `zitrus` is architectured as a set of lower-level components which then are
//! used to make higher-level abstractions.
//!
//! If you're only interested in making a normal applications
//! you have at your disposal:
//!
//! * `Init.Application.Software` - If you won't be using hardware acceleration.
//!
//! * `Init.Application.Mango` - If you will eventually use hardware acceleration via the `PICA200` with mango, creates a `mango.Device` on your behalf.
//!
//! ## Namespaces
//!
//! * `heap` - `heap.CommitAllocator` (for normal heap) and `heap.linear_page_allocator` respectively.
//!
//! * `result` - `result.Code` and everything related to `Horizon` result codes,
//! help wanted for getting all possible `result.Description`s.
//!
//! * `environment` - only really relevant for homebrew distributed as `3dsx`
//!
//! * `memory` - All virtual memory mappings of the standard process, here
//! you'll find `config.Shared` and `config.Kernel`.
//!
//! * `config` - `config.Shared` and `config.Kernel`
//!
//! * `ipc` - Type-safe and declarative `IPC` command handling, see `ipc.Buffer`.
//!
//! * `tls` - `tls.Block` and `threadlocal` variable support,
//! also where the `ipc.Buffer` is stored for `IPC` communication.
//!
//! * `fmt` - Do you need to parse a `fmt.ncch.romfs`? Or maybe a `fmt.smdh`?
//! There you'll find all `Horizon`-related formats implemented in `zitrus`.
//!
//! * `start` - The glue between your `main` and the real entrypoint,
//! its purpose is to do the bare minimum but still be useful.
//!
//! * `panic` - A standard panic handler that reports panics via `ErrorDisplayManager`.
//! Uses `break` if connecting to it didn't succeed.
//!
//! * `testing` - You should use variables defined here when using
//! the horizon test runner, akin to `std.testing`.
//!
//! * `services` - All `Horizon` services live here. See `ServiceManager`.
//!
//! ## Ports
//!
//! * `ErrorDisplayManager` - Type-safe abstraction of the `err:f` port. Used for logging,
//! reporting errors and exceptions.
//!
//! * `ServiceManager` - Type-safe abstraction of the `srv:` port. You get `services` with
//! this.
//!
//! ## Kernel Handles
//!
//! * `Object` - All kernel handles inherit from this.
//! * `Synchronization` - All waitable objects inherit from this, you can do a `waitSynchronization`
//! with it.
//! * `Interruptable` - A `Synchronization` which can be triggered by kernel interrupts.
//! * `ResourceLimit` - For `getResourceLimitLimitValues` and `getResourceLimitCurrentValues`
//! * `Mutex` - Manages synchronzation between threads and processes. Use `AddressArbiter`s and futexes
//! for process-local synchronization objects.
//! * `Semaphore` - `Mutex` ditto.
//! * `Event` - `Mutex` ditto. They can be signaled and cleared, their behavior changes depending on `ResetType`.
//! * `Timer` - `Mutex` ditto. Their behavior changes depending on `ResetType`.
//! * `MemoryBlock` - For inter-process shared memory creation and mapping.
//! * `ClientSession` - An `ipc` session to `ClientSession.sendRequest`s and get resposes from.
//! * `Thread` - self-explanatory, you can get the current thread via `Thread.current`.
//! * `Process` - self-explanatory, you can get the current process via `Process.current`.
//!

pub fn Result(T: type) type {
    return struct {
        pub const Cases = union(enum(u1)) {
            success: SelfResult,
            failure: result.Code,
        };

        code: result.Code,
        value: T,

        pub inline fn of(code: result.Code, value: T) SelfResult {
            return .{ .code = code, .value = value };
        }

        /// Returns the result as a tagged union to be used in a switch.
        pub inline fn cases(res: SelfResult) Cases {
            return if (res.code.isSuccess()) .{ .success = res } else .{ .failure = res.code };
        }

        const SelfResult = @This();
    };
}

pub const SystemCall = enum(u8) {
    @"0x00",
    control_memory,
    query_memory,
    exit,
    get_process_affinity_mask,
    set_process_affinity_mask,
    get_process_ideal_processor,
    set_process_ideal_processor,
    create_thread,
    exit_thread,
    sleep_thread,
    get_thread_priority,
    set_thread_priority,
    get_thread_affinity_mask,
    set_thread_affinity_mask,
    get_thread_ideal_processor,
    set_thread_ideal_processor,
    get_cpu_count,
    run,
    create_mutex,
    release_mutex,
    create_semaphore,
    release_semaphore,
    create_event,
    signal_event,
    clear_event,
    create_timer,
    set_timer,
    cancel_timer,
    clear_timer,
    create_memory_block,
    map_memory_block,
    unmap_memory_block,
    create_address_arbiter,
    arbitrate_address,
    close_handle,
    wait_synchronization,
    wait_synchronization_multiple,
    /// Stubbed
    signal_and_wait,
    duplicate_handle,
    get_system_tick,
    get_handle_info,
    get_system_info,
    get_process_info,
    get_thread_info,
    connect_to_port,
    /// Stubbed
    send_sync_request1,
    /// Stubbed
    send_sync_request2,
    /// Stubbed
    send_sync_request3,
    /// Stubbed
    send_sync_request4,
    send_sync_request,
    open_process,
    open_thread,
    get_process_id,
    get_process_id_of_thread,
    get_thread_id,
    get_resource_limit,
    get_resource_limit_limit_values,
    get_resource_limit_current_values,
    get_thread_context,
    break_execution,
    output_debug_string,
    control_performance_counter,
    @"0x3F",
    @"0x40",
    @"0x41",
    @"0x42",
    @"0x43",
    @"0x44",
    @"0x45",
    @"0x46",
    create_port,
    create_session_to_port,
    create_session,
    accept_session,
    /// Stubbed
    reply_and_receive1,
    /// Stubbed
    reply_and_receive2,
    /// Stubbed
    reply_and_receive3,
    /// Stubbed
    reply_and_receive4,
    reply_and_receive,
    bind_interrupt,
    unbind_interrupt,
    invalidate_process_data_cache,
    store_process_data_cache,
    flush_process_data_cache,
    start_inter_process_dma,
    stop_dma,
    get_dma_state,
    restart_dma,
    set_gpu_prot,
    set_wifi_enabled,
    @"0x5B",
    @"0x5C",
    @"0x5D",
    @"0x5E",
    @"0x5F",
    debug_active_process,
    break_debug_process,
    terminate_debug_process,
    get_process_debug_event,
    continue_debug_event,
    get_process_list,
    get_thread_list,
    get_debug_thread_context,
    set_debug_thread_context,
    query_debug_process_memory,
    read_process_memory,
    write_process_memory,
    set_hardware_breakpoint,
    get_debug_thread_parameter,
    @"0x6E",
    @"0x6F",
    control_process_memory,
    map_process_memory,
    unmap_process_memory,
    create_codeset,
    @"0x74",
    create_process,
    terminate_process,
    set_process_resource_limits,
    create_resource_limit,
    set_resource_limit_limit_values,
    /// Stubbed since 2.0.0-2
    add_code_segment,
    /// Removed in 11.0.0-33
    backdoor,
    set_state,
    query_process_memory,
    @"0x7E",
    @"0x7F",
    @"0x80",
    @"0x81",
    @"0x82",
    @"0x83",
    @"0x84",
    @"0x85",
    @"0x86",
    @"0x87",
    @"0x88",
    @"0x89",
    @"0x8A",
    @"0x8B",
    @"0x8C",
    @"0x8D",
    @"0x8E",
    @"0x8F",
    @"0x90",
    @"0x91",
    @"0x92",
    @"0x93",
    @"0x94",
    @"0x95",
    @"0x96",
    @"0x97",
    @"0x98",
    @"0x99",
    @"0x9A",
    @"0x9B",
    @"0x9C",
    @"0x9D",
    @"0x9E",
    @"0x9F",
    @"0xA0",
    @"0xA1",
    @"0xA2",
    @"0xA3",
    @"0xA4",
    @"0xA5",
    @"0xA6",
    @"0xA7",
    @"0xA8",
    @"0xA9",
    @"0xAA",
    @"0xAB",
    @"0xAC",
    @"0xAD",
    @"0xAE",
    @"0xAF",
    @"0xB0",
    @"0xB1",
    @"0xB2",
    @"0xB3",
    @"0xB4",
    @"0xB5",
    @"0xB6",
    @"0xB7",
    @"0xB8",
    @"0xB9",
    @"0xBA",
    @"0xBB",
    @"0xBC",
    @"0xBD",
    @"0xBE",
    @"0xBF",
    @"0xC0",
    @"0xC1",
    @"0xC2",
    @"0xC3",
    @"0xC4",
    @"0xC5",
    @"0xC6",
    @"0xC7",
    @"0xC8",
    @"0xC9",
    @"0xCA",
    @"0xCB",
    @"0xCC",
    @"0xCD",
    @"0xCE",
    @"0xCF",
    @"0xD0",
    @"0xD1",
    @"0xD2",
    @"0xD3",
    @"0xD4",
    @"0xD5",
    @"0xD6",
    @"0xD7",
    @"0xD8",
    @"0xD9",
    @"0xDA",
    @"0xDB",
    @"0xDC",
    @"0xDD",
    @"0xDE",
    @"0xDF",
    @"0xE0",
    @"0xE1",
    @"0xE2",
    @"0xE3",
    @"0xE4",
    @"0xE5",
    @"0xE6",
    @"0xE7",
    @"0xE8",
    @"0xE9",
    @"0xEA",
    @"0xEB",
    @"0xEC",
    @"0xED",
    @"0xEE",
    @"0xEF",
    @"0xF0",
    @"0xF1",
    @"0xF2",
    @"0xF3",
    @"0xF4",
    @"0xF5",
    @"0xF6",
    @"0xF7",
    @"0xF8",
    @"0xF9",
    @"0xFA",
    @"0xFB",
    @"0xFC",
    @"0xFD",
    @"0xFE",
    breakpoint,
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

pub const MemoryRegion = enum(u3) {
    all,
    app,
    system,
    base,
};

pub const MemoryOperation = packed struct(u32) {
    pub const Kind = enum(u8) {
        free = 1,
        reserve,
        commit,
        map,
        unmap,
        protect,
    };

    pub const Region = enum(u3) {
        all,
        app,
        system,
        base,
    };

    kind: Kind,
    area: Region,
    _unused0: u5 = 0,
    linear: bool,
    _unused1: u15 = 0,
};

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

pub const BreakReason = enum(u32) {
    panic,
    assert,
    user,
};

pub const InterruptId = enum(u32) {};

pub const Timeout = enum(i64) {
    none = -1,
    _,

    pub fn fromNanoseconds(ns: u63) Timeout {
        return @enumFromInt(ns);
    }
};

pub const StartupInfo = extern struct {
    priority: i32,
    stack_size: u32,
    argc: u32,
    argv: [*]i16,
    envp: [*]i16,
};

pub const Object = packed struct(u32) {
    pub const none: Object = .{ ._ = 0 };
    pub const Error = error{
        /// Resource limit for the object reached, out of handles or out of kernel memory.
        SystemResources,
    } || UnexpectedError;

    _: u32,

    pub fn dupe(obj: Object) Error!Object {
        const C = result.Code;
        return switch (duplicateHandle(obj).cases()) {
            .success => |r| r.value,
            .failure => |code| if (code == C.kernel_out_of_handles) error.SystemResources else if (code == C.kernel_invalid_handle) resultBug(code) else unexpectedResult(code),
        };
    }

    pub fn close(obj: Object) void {
        const code = closeHandle(obj);
        if (!code.isSuccess()) resultBug(code) catch {};
    }
};

pub const ResourceLimit = packed struct(u32) {
    pub const Kind = enum(u32) {
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

    pub const CreateError = Object.Error;

    obj: Object,

    pub fn create() CreateError!ResourceLimit {
        const C = result.Code;
        return switch (createResourceLimit().cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn setLimitValues(resource_limit: ResourceLimit, resources: []const Kind, amount: []const i64) !void {
        std.debug.assert(resources.len == amount.len);

        const code = setResourceLimitLimitValues(resource_limit, resources, amount, resources.len);

        if (!code.isSuccess()) return unexpectedResult(code); // TODO: Investigate
    }

    pub fn close(limit: ResourceLimit) void {
        limit.obj.close();
    }
};

pub const CodeSet = packed struct(u32) {
    pub const Info = extern struct {}; // TODO:
    pub const CreateError = Object.Error;

    obj: Object,

    pub fn create(info: CodeSet.Info, text: [*]align(heap.page_size) const u8, rodata: [*]align(heap.page_size) const u8, data: [*]align(heap.page_size) const u8) CreateError!ResourceLimit {
        const C = result.Code;
        return switch (createCodeSet(info, text, rodata, data).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn close(set: CodeSet) void {
        set.obj.close();
    }
};

/// Spurious wakeups are not possible.
/// Each arbiter holds a single waitlist.
pub const AddressArbiter = packed struct(u32) {
    pub const none: AddressArbiter = .{ .obj = .none };
    pub const Mutex = extern struct {
        pub const init: Mut = .{};
        pub const State = enum(i32) {
            unlocked = 0,
            locked = -1,
            contended = -2,
        };

        state: std.atomic.Value(State) = .init(.unlocked),

        pub fn tryLock(mut: *Mut) bool {
            return mut.state.cmpxchgStrong(.unlocked, .locked, .acquire, .monotonic) == null;
        }

        pub fn lock(mut: *Mut, arbiter: AddressArbiter) void {
            if (mut.tryLock()) return;

            if (mut.state.load(.monotonic) == .contended) {
                arbiter.wait(State, &mut.state.raw, .unlocked);
            }

            while (mut.state.swap(.contended, .acquire) != .unlocked) {
                arbiter.wait(State, &mut.state.raw, .unlocked);
            }
        }

        pub fn lockTimeout(mut: *Mut, arbiter: AddressArbiter, timeout: Timeout) error{Timeout}!void {
            if (mut.tryLock()) return;

            if (mut.state.load(.monotonic) == .contended) {
                arbiter.waitTimeout(State, &mut.state.raw, .unlocked, timeout) catch |err| switch (err) {
                    error.Timeout => return if (mut.state.swap(.contended, .acquire) != .unlocked) error.Timeout else {},
                };
            }

            while (mut.state.swap(.contended, .acquire) != .unlocked) {
                try arbiter.waitTimeout(State, &mut.state.raw, .unlocked, timeout);
            }
        }

        pub fn unlock(mut: *Mut, arbiter: AddressArbiter) void {
            const last = mut.state.swap(.unlocked, .release);
            std.debug.assert(last != .unlocked);

            if (last == .contended) arbiter.signal(State, &mut.state.raw, 1);
        }

        const Mut = @This();
    };

    /// Similar to an auto-reset Event. Each `Thread` must have a separate `Parker` if needed.
    pub const Parker = extern struct {
        pub const init: Parker = .{};
        pub const State = enum(i32) { resting = 0, alerted };

        state: std.atomic.Value(State) = .init(.resting),

        pub fn park(parker: *Parker, arbiter: AddressArbiter) error{Timeout}!void {
            if (parker.state.swap(.resting, .acquire) == .alerted) return;
            arbiter.wait(State, &parker.state.raw, .alerted);
            std.debug.assert(parker.state.swap(.resting, .monotonic) == .alerted);
        }

        pub fn parkTimeout(parker: *Parker, arbiter: AddressArbiter, timeout: Timeout) error{Timeout}!void {
            if (parker.state.swap(.resting, .acquire) == .alerted) return;
            try arbiter.waitTimeout(State, &parker.state.raw, .alerted, timeout);
            std.debug.assert(parker.state.swap(.resting, .monotonic) == .alerted);
        }

        pub fn unpark(parker: *Parker, arbiter: AddressArbiter) void {
            if (parker.state.swap(.alerted, .release) == .alerted) return;
            arbiter.signal(State, &parker.state.raw, 1);
        }
    };

    pub const CreateError = Object.Error;
    pub const ArbitrateError = error{
        /// Only if an arbitration ending with `_timeout` was used.
        Timeout,
    };

    pub const Arbitration = union(Type) {
        pub const Type = enum(u32) { signal, wait_if_less_than, decrement_and_wait_if_less_than, wait_if_less_than_timeout, decrement_and_wait_if_less_than_timeout };
        pub const TimeoutValue = extern struct { value: i32, timeout: Timeout };

        signal: i32,
        wait_if_less_than: i32,
        decrement_and_wait_if_less_than: i32,
        wait_if_less_than_timeout: TimeoutValue,
        decrement_and_wait_if_less_than_timeout: TimeoutValue,
    };

    obj: Object,

    pub fn create() CreateError!AddressArbiter {
        const C = result.Code;
        return switch (createAddressArbiter().cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.os_out_of_address_arbiters or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn arbitrate(arbiter: AddressArbiter, address: *i32, arbitration: Arbitration) ArbitrateError!void {
        const C = result.Code;
        const value: i32, const timeout: Timeout = switch (arbitration) {
            inline .signal, .wait_if_less_than, .decrement_and_wait_if_less_than => |value| .{ value, .none },
            inline .wait_if_less_than_timeout, .decrement_and_wait_if_less_than_timeout => |timeout_value| .{ timeout_value.value, timeout_value.timeout },
        };

        // NOTE: The if-else is a workaround for azahar as it doesn't have the same behavior as the Horizon kernel!
        const code = if (timeout == .none)
            switch (arbitration) {
                .wait_if_less_than_timeout => arbitrateAddress(arbiter, address, .wait_if_less_than, value, timeout),
                .decrement_and_wait_if_less_than_timeout => arbitrateAddress(arbiter, address, .decrement_and_wait_if_less_than, value, timeout),
                else => arbitrateAddress(arbiter, address, std.meta.activeTag(arbitration), value, timeout),
            }
        else
            arbitrateAddress(arbiter, address, std.meta.activeTag(arbitration), value, timeout);

        return if (code == C.os_timeout) error.Timeout else if (code == C.kernel_unaligned_address) unreachable // NOTE: If you hit this you 100% have IB as the pointer is assumed to be aligned
        else if (code == C.os_invalid_string) unreachable // NOTE: invalid address
        else if (!code.isSuccess()) unreachable // NOTE: really unreachable
        else {};
    }

    /// Waits on the address if `address.* < value` until signaled. The comparison is *signed*.
    pub fn wait(arbiter: AddressArbiter, comptime T: type, address: *T, value: T) void {
        comptime std.debug.assert(@bitSizeOf(T) == @bitSizeOf(u32) and @sizeOf(T) == @sizeOf(u32));

        return arbiter.arbitrate(@ptrCast(address), .{
            .wait_if_less_than = switch (@typeInfo(T)) {
                .int => @bitCast(value),
                .@"enum" => @bitCast(@intFromEnum(value)),
                else => comptime unreachable,
            },
        }) catch unreachable;
    }

    /// Waits on the address if `address.* < value` until signaled or `timeout`. The comparison is *signed*.
    pub fn waitTimeout(arbiter: AddressArbiter, comptime T: type, address: *T, value: T, timeout: Timeout) error{Timeout}!void {
        comptime std.debug.assert(@bitSizeOf(T) == @bitSizeOf(u32) and @sizeOf(T) == @sizeOf(u32));

        return try arbiter.arbitrate(@ptrCast(address), .{ .wait_if_less_than_timeout = .{
            .value = switch (@typeInfo(T)) {
                .int => @bitCast(value),
                .@"enum" => @bitCast(@intFromEnum(value)),
                else => comptime unreachable,
            },
            .timeout = timeout,
        } });
    }

    /// Signals up to `waiters` threads waiting on the address or all if null.
    pub fn signal(arbiter: AddressArbiter, comptime T: type, address: *T, waiters: ?u31) void {
        comptime std.debug.assert(@bitSizeOf(T) == @bitSizeOf(u32) and @sizeOf(T) == @sizeOf(u32));
        arbiter.arbitrate(@ptrCast(address), .{ .signal = waiters orelse -1 }) catch unreachable;
    }

    pub fn close(arbiter: AddressArbiter) void {
        arbiter.obj.close();
    }
};

pub const MemoryBlock = packed struct(u32) {
    pub const CreateError = error{
        /// Tried to allocate a `linear` memory block as an application or invalid permissions specified.
        PermissionDenied,
    } || Object.Error;
    pub const MapError = error{} || UnexpectedError;

    obj: Object,

    pub fn create(address: [*]align(heap.page_size) u8, size: u32, this: MemoryPermission, other: MemoryPermission) CreateError!MemoryBlock {
        const C = result.Code;
        return switch (createMemoryBlock(address, size, this, other).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.fnd_out_of_memory or code == C.os_out_of_memory_blocks or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory_for_memory_blocks) error.SystemResources //
            else if (code == C.kernel_permission_denied or code == C.os_invalid_combination) error.PermissionDenied //
            else if (code == C.kernel_unaligned_size or code == C.os_unaligned_size or code == C.os_invalid_address) resultBug(code) //
            else unexpectedResult(code),
        };
    }

    pub fn map(mem: MemoryBlock, address: [*]align(heap.page_size) u8, this: MemoryPermission, other: MemoryPermission) MapError!void {
        const C = result.Code;
        const code = mapMemoryBlock(mem, address, this, other);

        return if (code == C.os_unaligned_address or code == C.os_invalid_handle) unreachable // NOTE: If you hit this you 100% have IB as the pointer is assumed to be aligned
        else if (code == C.os_invalid_combination or code == C.os_invalid_address or code == C.os_invalid_address_state) resultBug(code) // NOTE: Invalid combination == Invalid permissions
        else if (!code.isSuccess()) unexpectedResult(code) else {};
    }

    pub fn unmap(mem: MemoryBlock, address: [*]align(heap.page_size) u8) void {
        _ = unmapMemoryBlock(mem, address);
    }

    pub fn close(mem: MemoryBlock) void {
        mem.obj.close();
    }
};

pub const Synchronization = packed struct(u32) {
    pub const none: Synchronization = .{ .obj = .none };
    pub const WaitError = error{Timeout} || UnexpectedError;
    pub const WaitManyError = WaitError || Object.Error;

    obj: Object,

    pub fn wait(sync: Synchronization, timeout: Timeout) WaitError!void {
        const C = result.Code;
        const code = waitSynchronization(sync, timeout);

        return if (code == C.os_timeout) error.Timeout else if (code == C.kernel_invalid_handle) unreachable // programmer error
        else if (code == C.kernel_out_of_range) unreachable // invalid timeout
        else if (!code.isSuccess()) unexpectedResult(code) else {};
    }

    pub fn waitMany(syncs: []const Synchronization, wait_all: bool, timeout: Timeout) WaitManyError!usize {
        const C = result.Code;
        return switch (waitSynchronizationMultiple(@ptrCast(syncs), wait_all, timeout).cases()) {
            .success => |s| if (s.code == C.os_timeout) error.Timeout else s.value,
            .failure => |code| if (code == C.kernel_invalid_handle) unreachable else if (code == C.kernel_invalid_pointer) unreachable // syncs.ptr is null
            else if (code == C.kernel_out_of_range) unreachable // invalid timeout
            else if (code == C.kernel_out_of_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn dupe(sync: Synchronization) Object.Error!Synchronization {
        return @bitCast(try sync.obj.dupe());
    }

    pub fn close(sync: Synchronization) void {
        sync.obj.close();
    }
};

pub const Interruptable = packed struct(u32) {
    sync: Synchronization,

    pub fn close(int: Interruptable) void {
        int.sync.close();
    }
};

pub const Mutex = packed struct(u32) {
    pub const CreateError = error{} || Object.Error;
    pub const WaitError = Synchronization.WaitError;
    pub const WaitManyError = Synchronization.WaitManyError;

    sync: Synchronization,

    pub fn create(initial_locked: bool) CreateError!Mutex {
        const C = result.Code;
        return switch (createMutex(initial_locked).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.os_out_of_mutexes or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn release(mutex: Mutex) void {
        const C = result.Code;
        const code = releaseMutex(mutex);

        return if (code == C.kernel_invalid_handle) unreachable else if (code == C.kernel_invalid_result_value) unreachable // not locked
        else if (code == C.kernel_mutex_not_owned) unreachable else if (!code.isSuccess()) unreachable // NOTE: Truly unreachable
        else {};
    }

    pub fn wait(mutex: Mutex, timeout: Timeout) WaitError!void {
        return mutex.sync.wait(timeout);
    }

    pub fn waitMany(mutexes: []const Mutex, wait_all: bool, timeout: Timeout) WaitError!usize {
        return Synchronization.waitMany(@ptrCast(mutexes), wait_all, timeout);
    }

    pub fn close(mutex: Mutex) void {
        mutex.sync.close();
    }
};

pub const Semaphore = packed struct(u32) {
    pub const CreateError = error{} || Object.Error;
    pub const WaitError = Synchronization.WaitError;
    pub const WaitManyError = Synchronization.WaitManyError;

    int: Interruptable,

    pub fn create(initial_count: u31, max_count: u31) CreateError!Semaphore {
        const C = result.Code;
        return switch (createSemaphore(initial_count, max_count).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.os_out_of_semaphores or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else if (code == C.kernel_invalid_combination) resultBug(code) // initial_count > max_count
            else unexpectedResult(code),
        };
    }

    pub fn release(semaphore: Semaphore, count: u31) usize {
        const C = result.Code;
        return switch (releaseSemaphore(semaphore, count).cases()) {
            .success => |r| r.value,
            .failure => |code| if (code == C.kernel_invalid_handle) unreachable else if (code == C.kernel_out_of_range) unreachable // releasing more than max_count
            else unreachable, // NOTE: Truly unreachable
        };
    }

    pub fn wait(semaphore: Semaphore, timeout: Timeout) WaitError!void {
        return semaphore.int.sync.wait(timeout);
    }

    pub fn waitMany(semaphore: []const Semaphore, wait_all: bool, timeout: Timeout) WaitManyError!usize {
        return Synchronization.waitMany(@ptrCast(semaphore), wait_all, timeout);
    }

    pub fn close(semaphore: Semaphore) void {
        semaphore.int.close();
    }
};

pub const Event = packed struct(u32) {
    pub const CreateError = error{} || Object.Error;
    pub const WaitError = Synchronization.WaitError;
    pub const WaitManyError = Synchronization.WaitManyError;

    int: Interruptable,

    pub fn create(reset_type: ResetType) CreateError!Event {
        const C = result.Code;
        return switch (createEvent(reset_type).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.os_out_of_events or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn clear(ev: Event) void {
        const C = result.Code;
        const code = clearEvent(ev);

        return if (code == C.kernel_invalid_handle) unreachable //
        else if (!code.isSuccess()) unreachable // NOTE: Truly unreachable / kernel bug
        else {};
    }

    pub fn signal(ev: Event) void {
        const C = result.Code;
        const code = signalEvent(ev);

        return if (code == C.kernel_invalid_handle) unreachable //
        else if (!code.isSuccess()) unreachable // NOTE: Truly unreachable / kernel bug
        else {};
    }

    pub fn dupe(ev: Event) Object.Error!Event {
        return @bitCast(try ev.int.sync.dupe());
    }

    pub fn wait(ev: Event, timeout: Timeout) WaitError!void {
        return ev.int.sync.wait(timeout);
    }

    pub fn waitMany(evs: []const Event, wait_all: bool, timeout: Timeout) WaitManyError!usize {
        return Synchronization.waitMany(@ptrCast(evs), wait_all, timeout);
    }

    pub fn close(ev: Event) void {
        ev.int.close();
    }
};

pub const Timer = packed struct(u32) {
    pub const CreateError = error{} || Object.Error;
    pub const WaitError = Synchronization.WaitError;
    pub const WaitManyError = Synchronization.WaitManyError;

    sync: Synchronization,

    pub fn create(reset_type: ResetType) CreateError!Timer {
        const C = result.Code;
        return switch (createTimer(reset_type).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.os_out_of_timers or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
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

    pub fn dupe(ev: Timer) Object.Error!Timer {
        return @bitCast(try ev.sync.dupe());
    }

    pub fn wait(timer: Timer, timeout: Timeout) WaitError!void {
        return timer.sync.wait(timeout);
    }

    pub fn waitMany(timers: []const Timer, wait_all: bool, timeout: Timeout) WaitError!usize {
        return Synchronization.waitMany(@ptrCast(timers), wait_all, timeout);
    }

    pub fn close(timer: Timer) void {
        timer.sync.close();
    }
};

pub const ServerSession = packed struct(u32) {
    sync: Synchronization,

    pub fn close(session: ServerSession) void {
        session.sync.close();
    }
};

pub const ClientSession = packed struct(u32) {
    pub const none: ClientSession = .{ .sync = .none };
    pub const ConnectionError = error{NotFound} || UnexpectedError;
    pub const RequestError = error{ConnectionClosedByPeer} || UnexpectedError;

    sync: Synchronization,

    pub fn connect(port: [:0]const u8) ConnectionError!ClientSession {
        const C = result.Code;
        std.debug.assert(port.len < 12);
        return switch (connectToPort(port).cases()) {
            .success => |s| s.value,
            .failure => |code| if (code == C.kernel_not_found) 
                error.NotFound 
            else if (code == C.os_invalid_string or code == C.os_string_too_big)
                resultBug(code) // invalid port.ptr and we already assert port.len < 12
            else
                unexpectedResult(code),
        };
    }

    pub fn sendRequest(session: ClientSession) RequestError!void {
        const C = result.Code;
        const code = sendSyncRequest(session);

        return if (code == C.kernel_invalid_handle)
            resultBug(code)
        else if (code == C.os_session_closed_by_remote) 
            error.ConnectionClosedByPeer
        else if (!code.isSuccess()) 
            unexpectedResult(code) 
        else 
            {};
    }

    pub fn close(session: ClientSession) void {
        session.sync.close();
    }
};

pub const Debug = packed struct(u32) {
    sync: Synchronization,

    pub fn close(dbg: Debug) void {
        dbg.sync.close();
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
        port.sync.close();
    }
};

pub const ClientPort = packed struct(u32) {
    pub const CreateSessionError = Object.Error || error{
        /// The port cannot accept more sessions. It may be able to in the future.
        PortBusy,
    };
    pub const WaitError = Synchronization.WaitError;
    pub const WaitManyError = Synchronization.WaitManyError;

    sync: Synchronization,

    pub fn createSession(port: ClientPort) CreateSessionError!ClientSession {
        const C = result.Code;
        return switch (createSessionToPort(port)) {
            .success => |s| s.value,
            .failure => |code| if (code == C.kernel_invalid_handle) unreachable else if (code == C.os_port_busy) error.PortBusy else if (code == C.out_of_sessions or code == C.kernel_out_of_handles or code == C.os_out_of_kernel_memory) error.SystemResources else unexpectedResult(code),
        };
    }

    pub fn wait(port: Port, timeout: Timeout) WaitError!void {
        return port.sync.wait(timeout);
    }

    pub fn waitMany(ports: []const ClientPort, wait_all: bool, timeout: Timeout) WaitManyError!usize {
        return Synchronization.waitMany(@ptrCast(ports), wait_all, timeout);
    }

    pub fn close(port: ClientPort) void {
        port.sync.close();
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

/// Raw and lean kernel thread, use `std.Thread` instead unless you *really* need this
/// as it doesn't depend on any runtime thus TLS is NOT handled.
pub const Thread = packed struct(u32) {
    pub const Impl = @import("horizon/Thread/Impl.zig");

    pub const Id = enum(u32) { _ };
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
    pub const WaitManyError = Synchronization.WaitManyError;

    sync: Synchronization,

    pub fn create(entry: *const fn (ctx: ?*anyopaque) callconv(.c) noreturn, ctx: ?*anyopaque, stack_top: [*]u8, priority: Priority, processor_id: Processor) UnexpectedError!Thread {
        return switch (createThread(entry, ctx, stack_top, priority, processor_id).cases()) {
            .success => |s| s.value,
            .failure => |code| unexpectedResult(code), // TODO: Error codes for this!
        };
    }
    pub fn id(thread: Thread) Id {
        return switch (getThreadId(thread).cases()) {
            .success => |s| s.value,
            .failure => unreachable, // NOTE: basically invalid handle!
        };
    }

    pub fn pid(thread: Thread) Process.Id {
        return switch (getThreadProcessId(thread).cases()) {
            .success => |s| s.value,
            .failure => unreachable, // NOTE: basically invalid handle!
        };
    }

    pub fn wait(thread: Thread, timeout: Timeout) WaitError!void {
        return thread.sync.wait(timeout);
    }

    pub fn waitMany(threads: []const Thread, wait_all: bool, timeout: Timeout) WaitManyError!usize {
        return Synchronization.waitMany(@ptrCast(threads), wait_all, timeout);
    }

    pub fn close(thread: Thread) void {
        thread.sync.close();
    }
};

pub const Process = packed struct(u32) {
    pub const none: Process = .{ .sync = .none };
    pub const Id = enum(u32) { _ };
    pub const InfoType = enum(u32) {
        used_heap_memory,
        used_handles = 0x4,
        highest_used_handles,

        num_threads = 0x7,
        max_threads,

        /// Gets the `horizon.Process.Capability.KernelFlags` of the process with all zeroed out except `MemoryType`
        memory_region = 19,
    };

    // TODO: Make union(u32) when implemented in zig
    pub const Capability = packed union {
        pub const none: Capability = @bitCast(@as(u32, 0xFFFFFFFF));

        // I suppose this allows you to use `svcBindInterrupt`?
        pub const InterruptInfo = packed struct(u32) {
            pub const magic_value = 0b1110;

            info: u28,
            header: u4 = magic_value,
        };

        // There's no info about this but I think that index is the 24-bit window of the syscall
        // table and mask are the syscalls which the app uses?
        pub const SystemCallMask = packed struct(u32) {
            pub const magic_value = 0b11110;

            mask: u24,
            index: u3,
            header: u5 = magic_value,
        };

        pub const KernelVersion = packed struct(u32) {
            pub const magic_value = 0b1111110;

            minor: u8,
            major: u8,
            _unused0: u9 = 0,
            header: u7 = magic_value,
        };

        pub const HandleTableSize = packed struct(u32) {
            pub const magic_value = 0b11111110;

            size: u19,
            _unused0: u5 = 0,
            header: u8 = magic_value,
        };

        pub const KernelFlags = packed struct(u32) {
            pub const magic_value = 0b111111110;
            pub const MemoryType = enum(u4) { application = 1, system, base, _ };

            allow_debug: bool,
            force_debug: bool,
            allow_non_alphanumeric: bool,
            shared_page_writing: bool,
            allow_privileged_priorities: bool,
            allow_main_args: bool,
            shared_device_memory: bool,
            runnable_on_sleep: bool,
            memory_type: MemoryType,
            special_memory: bool,
            allow_cpu2: bool,
            _unused0: u9 = 0,
            header: u9 = magic_value,
        };

        pub const MapAddressRangeStart = packed struct(u32) {
            pub const magic_value = 0b11111111100;

            page: u20,
            read_only: bool,
            header: u11 = magic_value,
        };

        pub const MapAddressRangeEnd = packed struct(u32) {
            page: u20,
            cacheable: bool,
            header: u11 = MapAddressRangeStart.magic_value,
        };

        pub const MapIoPage = packed struct(u32) {
            pub const magic_value = 0b11111111111;

            page: u20,
            read_only: bool,
            header: u11 = 0b11111111111,
        };

        interrupt_info: InterruptInfo,
        system_call_mask: SystemCallMask,
        kernel_version: KernelVersion,
        kernel_flags: KernelFlags,
        handle_table_size: HandleTableSize,
        map_range_start: MapAddressRangeStart,
        map_range_end: MapAddressRangeEnd,
        map_io_page: MapIoPage,

        pub fn kernelVersion(major: u8, minor: u8) Capability {
            return .{ .kernel_version = .{ .major = major, .minor = minor } };
        }

        pub fn kernelFlags(flags: KernelFlags) Capability {
            return .{ .kernel_flags = flags };
        }

        pub fn handleTableSize(size: u19) Capability {
            return .{ .handle_table_size = .{ .size = size } };
        }

        pub fn syscallMask(index: u3, mask: u24) Capability {
            return .{ .system_call_mask = .{ .index = index, .mask = mask } };
        }
    };

    /// Alias to the current process.
    ///
    /// `controlMemory`, `mapMemory` and `unmapMemory` need a real handle and won't work with this alias.
    pub const current: Process = @bitCast(@as(u32, 0xFFFF8001));

    sync: Synchronization,

    pub fn dupe(proc: Process) Object.Error!Process {
        return @bitCast(try proc.sync.dupe());
    }

    pub fn id(prc: Process) Process.Id {
        return switch (getProcessId(prc)) {
            .success => |s| s.value,
            .failure => unreachable, // NOTE: basically invalid handle!
        };
    }

    pub fn controlMemory(prc: Process, operation: MemoryOperation.Kind, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: MemoryPermission) !void {
        const code = controlProcessMemory(prc, operation, addr0, addr1, size, permissions);

        if (!code.isSuccess()) return unexpectedResult(code);
    }

    pub fn mapMemory(prc: Process, slice: []align(heap.page_size) u8) !void {
        const code = mapProcessMemory(prc, slice);

        if (!code.isSuccess()) return unexpectedResult(code);
    }

    pub fn unmapMemory(prc: Process, slice: []align(heap.page_size) u8) !void {
        const code = unmapProcessMemory(prc, slice);

        if (!code.isSuccess()) unreachable; // NOTE: programmer error
    }

    pub fn close(prc: Process) void {
        prc.sync.close();
    }
};

/// A `std.Io.Writer` which does `outputDebugString` on drain.
pub fn outputDebugWriter(buffer: []u8) std.Io.Writer {
    return .{
        .vtable = &.{
            .drain = outputDebugDrain,
        },
        .buffer = buffer,
    };
}

fn outputDebugDrain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    const buffered = w.buffered();
    if (buffered.len > 0) outputDebugString(buffered);
    w.end = 0;

    var n: usize = 0;
    for (data[0 .. data.len - 1]) |slice| {
        if (slice.len == 0) continue;

        outputDebugString(slice);
        n += slice.len;
    }

    for (0..splat) |_| outputDebugString(data[data.len - 1]);

    return n + splat * data[data.len - 1].len;
}

pub fn controlMemory(operation: MemoryOperation, addr0: ?*align(heap.page_size) anyopaque, addr1: ?*align(heap.page_size) anyopaque, size: usize, permissions: MemoryPermission) Result([*]align(heap.page_size) u8) {
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

/// Exits the current process.
pub fn exit() noreturn {
    asm volatile ("svc 0x03");
    unreachable;
}

pub fn getProcessAffinityMask(prc: Process, processor_count: i32) Result(u8) {
    var affinity_mask: u8 = undefined;

    const code = asm volatile ("svc 0x04"
        : [code] "={r0}" (-> result.Code),
        : [affinity_mask] "{r0}" (&affinity_mask),
          [process] "{r1}" (prc),
          [processor_count] "{r2}" (processor_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, affinity_mask);
}

pub fn setProcessAffinityMask(prc: Process, affinity_mask: *const u8, processor_count: i32) result.Code {
    return asm volatile ("svc 0x05"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [affinity_mask] "{r1}" (affinity_mask),
          [processor_count] "{r2}" (processor_count),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getProcessIdealProcessor(prc: Process) Result(i32) {
    var ideal_processor: i32 = undefined;

    const code = asm volatile ("svc 0x06"
        : [code] "={r0}" (-> result.Code),
          [ideal_processor] "={r1}" (ideal_processor),
        : [process] "{r1}" (prc),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, ideal_processor);
}

pub fn setProcessIdealProcessor(prc: Process, ideal_processor: i32) result.Code {
    return asm volatile ("svc 0x07"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
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

/// Exits the current thread.
pub fn exitThread() noreturn {
    asm volatile ("svc 0x09");
    unreachable;
}

/// Sleeps the current thread `ns` nanoseconds.
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

pub fn getCpuCount() i32 {
    return asm volatile ("svc 0x11"
        : [processor_number] "={r0}" (-> i32),
        :
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn run(prc: Process, startup_info: *const StartupInfo) result.Code {
    return asm volatile ("svc 0x12"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
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

pub fn createSemaphore(initial_count: u31, max_count: u31) Result(Semaphore) {
    var semaphore: Semaphore = undefined;

    const code = asm volatile ("svc 0x15"
        : [code] "={r0}" (-> result.Code),
          [semaphore] "={r1}" (semaphore),
        : [initial_count] "{r1}" (initial_count),
          [max_count] "{r2}" (max_count),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, semaphore);
}

pub fn releaseSemaphore(semaphore: Semaphore, release_count: u31) Result(usize) {
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

pub fn arbitrateAddress(arbiter: AddressArbiter, address: *i32, arbitration_type: AddressArbiter.Arbitration.Type, value: i32, timeout: Timeout) result.Code {
    const timeout_u: u64 = @bitCast(@intFromEnum(timeout));

    return asm volatile ("svc 0x22"
        : [code] "={r0}" (-> result.Code),
        : [arbiter] "{r0}" (arbiter),
          [address] "{r1}" (address),
          [type] "{r2}" (arbitration_type),
          [value] "{r3}" (value),
          [timeout_low] "{r4}" (@as(u32, @truncate(timeout_u))),
          [timeout_high] "{r5}" (@as(u32, @truncate(timeout_u >> 32))),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn closeHandle(handle: Object) result.Code {
    return asm volatile ("svc 0x23"
        : [code] "={r0}" (-> result.Code),
        : [handle] "{r0}" (handle),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn waitSynchronization(sync: Synchronization, timeout: Timeout) result.Code {
    const timeout_u: u64 = @bitCast(@intFromEnum(timeout));

    return asm volatile ("svc 0x24"
        : [code] "={r0}" (-> result.Code),
        : [sync] "{r0}" (sync),
          [timeout_low] "{r2}" (@as(u32, @truncate(timeout_u))),
          [timeout_high] "{r3}" (@as(u32, @truncate(timeout_u >> 32))),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn waitSynchronizationMultiple(handles: []const Synchronization, wait_all: bool, timeout: Timeout) Result(usize) {
    const timeout_u: u64 = @bitCast(@intFromEnum(timeout));
    var id: usize = 0;

    const code = asm volatile ("svc 0x25"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [handles] "{r1}" (handles.ptr),
          [handles_len] "{r2}" (handles.len),
          [wait_all] "{r3}" (wait_all),
          [timeout_low] "{r0}" (@as(u32, @truncate(timeout_u))),
          [timeout_high] "{r4}" (@as(u32, @truncate(timeout_u >> 32))),
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

pub fn getSystemTick() u64 {
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

pub fn getProcessInfo(prc: Process, info: Process.InfoType) Result(i64) {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    const code = asm volatile ("svc 0x2B"
        : [code] "={r0}" (-> result.Code),
          [lo] "={r1}" (lo),
          [hi] "={r2}" (hi),
        : [process] "{r1}" (prc),
          [type] "{r2}" (info),
        : .{ .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, @bitCast((@as(u64, hi) << 32) | lo));
}

// svc getThreadInfo() stubbed 0x2C

pub fn connectToPort(port: [:0]const u8) Result(ClientSession) {
    std.debug.assert(port.len < 12);
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

pub fn openProcess(id: Process.Id) Result(Process) {
    var prc: Process = undefined;

    const code = asm volatile ("svc 0x33"
        : [code] "={r0}" (-> result.Code),
          [process] "={r1}" (prc),
        : [id] "{r1}" (@intFromEnum(id)),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, prc);
}

pub fn openThread(prc: Process, id: Thread.Id) Result(Thread) {
    var thread: Thread = undefined;

    const code = asm volatile ("svc 0x34"
        : [code] "={r0}" (-> result.Code),
          [thread] "={r1}" (thread),
        : [process] "{r1}" (prc),
          [id] "{r2}" (@intFromEnum(id)),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, thread);
}

/// Only fails with `0xD9001BF7` if `prc` is an invalid handle.
///
/// Allows the `.current` pseudo-handle
pub fn getProcessId(prc: Process) Result(Process.Id) {
    var id: Process.Id = undefined;

    const code = asm volatile ("svc 0x35"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [process] "{r1}" (prc),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getThreadProcessId(thread: Thread) Result(Process.Id) {
    var id: Process.Id = undefined;

    const code = asm volatile ("svc 0x36"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getThreadId(thread: Thread) Result(Thread.Id) {
    var id: Thread.Id = undefined;

    const code = asm volatile ("svc 0x37"
        : [code] "={r0}" (-> result.Code),
          [id] "={r1}" (id),
        : [thread] "{r1}" (thread),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, id);
}

pub fn getResourceLimit(prc: Process) Result(ResourceLimit) {
    var resource_limit: ResourceLimit = undefined;

    const code = asm volatile ("svc 0x38"
        : [code] "={r0}" (-> result.Code),
          [resource_limit] "={r1}" (resource_limit),
        : [process] "{r1}" (prc),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, resource_limit);
}

pub fn getResourceLimitLimitValues(values: []i64, resource_limit: ResourceLimit, names: []ResourceLimit.Kind) result.Code {
    std.debug.assert(values.len == names.len);

    return asm volatile ("svc 0x39"
        : [code] "={r0}" (-> result.Code),
        : [values_ptr] "{r0}" (values.ptr),
          [resource_limit] "{r1}" (resource_limit),
          [names_ptr] "{r2}" (names.ptr),
          [names_len] "{r3}" (names.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn getResourceLimitCurrentValues(values: []i64, resource_limit: ResourceLimit, names: []ResourceLimit.Kind) result.Code {
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

pub fn invalidateProcessDataCache(prc: Process, data: []u8) result.Code {
    return asm volatile ("svc 0x52"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn storeProcessDataCache(prc: Process, data: []const u8) result.Code {
    return asm volatile ("svc 0x53"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn flushProcessDataCache(prc: Process, data: []const u8) result.Code {
    return asm volatile ("svc 0x54"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [data_ptr] "{r1}" (data.ptr),
          [data_len] "{r2}" (data.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

// TODO: dma svc's 0x55-0x58

// svc setGpuProt() TODO: 0x59
// svc setWifiEnabled() TODO: 0x5A

// TODO: debug svc's 0x60-0x6D

pub fn controlProcessMemory(prc: Process, operation: MemoryOperation.Kind, addr0: ?*anyopaque, addr1: ?*anyopaque, size: usize, permissions: MemoryPermission) result.Code {
    return asm volatile ("svc 0x70"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [addr0] "{r1}" (addr0),
          [addr1] "{r2}" (addr1),
          [size] "{r3}" (size),
          [operation] "{r4}" (operation),
          [permissions] "{r5}" (permissions),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn mapProcessMemory(prc: Process, slice: []align(heap.page_size) u8) result.Code {
    return asm volatile ("svc 0x71"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [addr] "{r1}" (slice.ptr),
          [size] "{r2}" (slice.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn unmapProcessMemory(prc: Process, slice: []align(heap.page_size) u8) result.Code {
    return asm volatile ("svc 0x72"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [addr] "{r1}" (slice.ptr),
          [size] "{r2}" (slice.len),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createCodeSet(info: CodeSet.Info, text: [*]align(heap.page_size) const u8, rodata: [*]align(heap.page_size) const u8, data: [*]align(heap.page_size) const u8) Result(CodeSet) {
    var code_set: CodeSet = undefined;

    const code = asm volatile ("svc 0x73"
        : [code] "={r0}" (-> result.Code),
          [code_set] "={r1}" (code_set),
        : [data] "{r0}" (data),
          [info] "{r1}" (&info),
          [text] "{r2}" (text),
          [rodata] "{r3}" (rodata),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, code_set);
}

// svc stubbed 0x74

pub fn createProcess(code_set: CodeSet, capabilities: []const Process.Capability) Result(Process) {
    var prc: Process = undefined;

    const code = asm volatile ("svc 0x75"
        : [code] "={r0}" (-> result.Code),
          [session] "={r1}" (prc),
        : [code_set] "{r1}" (code_set),
          [capabilities_ptr] "{r2}" (capabilities.ptr),
          [capabilities_len] "{r3}" (capabilities.len),
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, prc);
}

pub fn terminateProcess(prc: Process) result.Code {
    return asm volatile ("svc 0x76"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn setProcessResourceLimit(prc: Process, resource_limit: ResourceLimit) result.Code {
    return asm volatile ("svc 0x77"
        : [code] "={r0}" (-> result.Code),
        : [process] "{r0}" (prc),
          [resource_limit] "{r1}" (resource_limit),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub fn createResourceLimit() Result(ResourceLimit) {
    var resource_limit: ResourceLimit = undefined;

    const code = asm volatile ("svc 0x78"
        : [code] "={r0}" (-> result.Code),
          [resource_limit] "={r1}" (resource_limit),
        :
        : .{ .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });

    return .of(code, resource_limit);
}

pub fn setResourceLimitLimitValues(resource_limit: ResourceLimit, resources: [*]const ResourceLimit.Kind, amount: [*]const i64, count: u32) result.Code {
    return asm volatile ("svc 0x79"
        : [code] "={r0}" (-> result.Code),
        : [resource_limit] "{r0}" (resource_limit),
          [resources] "{r1}" (resources),
          [amount] "{r2}" (amount),
          [count] "{r3}" (count),
        : .{ .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

// svc addCodeSegment() 0x7A
// svc backdoor() 0x7B
// svc kernelSetState() 0x7C
// svc queryProcessMemory() 0x7D

pub fn breakpoint() void {
    asm volatile ("svc 0xFF" ::: .{ .r0 = true, .r1 = true, .r2 = true, .r3 = true, .r12 = true, .cpsr = true, .memory = true });
}

pub const UnexpectedError = std.Io.UnexpectedError;
pub fn unexpectedResult(code: result.Code) UnexpectedError {
    debug.print("unexpected result: {f} (0x{X:0>8})\n", .{ code, @as(u32, @bitCast(code)) });
    return error.Unexpected;
}

pub fn resultBug(code: result.Code) UnexpectedError {
    if (is_debug) std.debug.panic("programmer bug caused result {f} (0x{X:0>8})\n", .{ code, @as(u32, @bitCast(code)) });
    return error.Unexpected;
}

pub const default_std_os_options: std.Options.OperatingSystem = .{
    .start = start,
    .debug = debug,
    .heap = heap,
    .Thread = Thread.Impl,
    .process = process,
    .Io = Io,
    .testing = testing,
};

comptime {
    _ = start;

    _ = Io;
    _ = heap;
    _ = process;
    _ = result;
    _ = environment;
    _ = memory;
    _ = config;
    _ = ipc;
    _ = fmt;
    _ = time;
    _ = services;

    _ = Init;
    _ = AddressArbiter;
    _ = AddressArbiter.Mutex;
    _ = AddressArbiter.Parker;
    _ = ServiceManager;
    _ = ErrorDisplayManager;
}

pub const Io = @import("horizon/Io.zig");

pub const Init = @import("horizon/Init.zig");

pub const heap = @import("horizon/heap.zig");
pub const process = @import("horizon/process.zig");
pub const result = @import("horizon/result.zig");
pub const environment = @import("horizon/environment.zig");
pub const memory = @import("horizon/memory.zig");
pub const config = @import("horizon/config.zig");
pub const ipc = @import("horizon/ipc.zig");
pub const tls = @import("horizon/tls.zig");
pub const fmt = @import("horizon/fmt.zig");
pub const time = @import("horizon/time.zig");

pub const start = @import("horizon/start.zig");
pub const debug = @import("horizon/debug.zig");
pub const testing = @import("horizon/testing.zig");

pub const ServiceManager = @import("horizon/ServiceManager.zig");
pub const ErrorDisplayManager = @import("horizon/ErrorDisplayManager.zig");

pub const services = @import("horizon/services.zig");

const is_debug = @import("builtin").mode == .Debug;
const std = @import("std");
