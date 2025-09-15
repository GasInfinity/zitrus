pub const ThreadLocalStorage = extern struct {
    pub const ExceptionHandler = extern struct {
        pub const Stack = enum(u32) {
            /// Inherit the faulting stack
            inherit = 1,
            _,

            /// Use an arbitrary stack top.
            pub fn top(stack: [*]u8) Stack {
                return @enumFromInt(@intFromPtr(stack));
            }
        };

        pub const Context = enum(u32) {
            /// Store the context in the stack.
            store_stack = 0,
            /// Store the context in the faulting stack.
            store_inherited = 1,
            _,

            /// Use an arbitrary memory location to store the context.
            pub fn at(memory: [*]u8) Context {
                return @enumFromInt(@intFromPtr(memory));
            }
        };

        // TODO: The proper
        entry: ?*const fn () callconv(.c) noreturn,
        /// Stack used when calling the exception entry.
        stack: Stack,
        /// Where to store the exception context.
        context: Context,
    };

    pub const State = extern struct {
        /// `$tp` used for software/emulated TLS if not using `tpidrurw`.
        tp: [*]u8,
        _: [0x30]u8,

        comptime {
            std.debug.assert(@sizeOf(State) == 0x34);
        }
    };

    /// When TLS variables fit into `(0x40 - 8)` bytes,
    /// this location will be used for the storage.
    storage: [0x40]u8,
    // TODO: panic on exception
    /// Function to call when an user-mode exception happens.
    exception: ExceptionHandler,
    /// Stores runtime state such as the `$tp` location.
    state: State,
    /// IPC parameters for requests and stores.
    ipc: ipc.Buffer,
};

pub inline fn get() *ThreadLocalStorage {
    return asm volatile ("mrc p15, 0, %[tls], cr13, cr0, 3"
        : [tls] "=r" (-> *ThreadLocalStorage),
    );
}

// TODO: only export this when not using tpidrurw.
export fn __aeabi_read_tp() callconv(.naked) void {
    const tp_offset = (@offsetOf(ThreadLocalStorage, "state") + @offsetOf(ThreadLocalStorage.State, "tp"));

    asm volatile (
        \\ mrc p15, 0, r0, cr13, cr0, 3
        \\ ldr r0, [r0, %[tp_offset]]
        \\ bx lr
        :
        : [tp_offset] "i" (tp_offset),
        : .{ .r0 = true });
}

const ipc = @import("ipc.zig");

const builtin = @import("builtin");
const std = @import("std");
