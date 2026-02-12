/// The `ThreadLocalStorage` of a `Thread` as used by `Horizon`.
///
/// `zitrus` reserves some needed state and storage
/// for some features.
pub const Block = extern struct {
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

        /// Make sure to flush the prefetch buffer!
        entry: ?*const fn (*const Exception.Info, *const Exception.Registers) callconv(.c) noreturn,
        /// Stack used when calling the exception entry.
        stack: Stack,
        /// Where to store the exception context.
        context: Context,
    };

    pub const State = extern struct {
        tp: [*]u8,
        _: [0x30]u8,

        comptime {
            std.debug.assert(@sizeOf(State) == 0x34);
        }
    };

    /// Currently unused by zitrus.
    storage: [0x40]u8,
    /// Function to call when an user-mode exception happens.
    exception: ExceptionHandler,
    /// Stores runtime state such as the `$tp` location.
    state: State,
    /// IPC parameters for requests and stores.
    ipc: ipc.Buffer,
};

/// Initializes the static TLS section and sets the main thread $tp.
pub fn initStatic() void {
    @setRuntimeSafety(false); // We don't want to panic as it depends on TLS
    @disableInstrumentation();
    @export(&__aeabi_read_tp, .{ .name = "__aeabi_read_tp" });

    const data_image = dataImage();

    const opt_tls_start: ?[*]u8 = @extern(?[*]u8, .{ .name = "__zitrus_main_tls_start" });
    const opt_tls_end: ?[*]u8 = @extern(?[*]u8, .{ .name = "__zitrus_main_tls_end" });

    if (opt_tls_start) |tls_start| {
        const tls_end = opt_tls_end.?;
        const static_tls = tls_start[0..(tls_end - tls_start)];

        @memcpy(static_tls[0..data_image.len], data_image);
        get().state.tp = @ptrFromInt(@intFromPtr(tls_start) - 8); // NOTE: Yes, the ABI says data starts at $tp + 8
    }
}

/// Returns the image of non-bss TLS data, may be empty.
pub fn dataImage() []const u8 {
    const opt_tdata_start = @extern(?[*]u8, .{ .name = "__zitrus_tls_data_image_start" });
    const opt_tdata_end = @extern(?[*]u8, .{ .name = "__zitrus_tls_data_image_end" });

    if (opt_tdata_start) |tdata_start| {
        const tdata_end = opt_tdata_end.?;
        return tdata_start[0..(tdata_end - tdata_start)];
    }

    return &.{};
}

/// Returns the minimum alignment of TLS data.
pub fn alignment() usize {
    if (@extern(?*anyopaque, .{ .name = "__zitrus_tls_align" })) |tls_align| return @intFromPtr(tls_align);
    return 1;
}

/// Returns the size of TLS data.
pub fn size() usize {
    const opt_tls_start: ?[*]u8 = @extern(?[*]u8, .{ .name = "__zitrus_main_tls_start" });
    const opt_tls_end: ?[*]u8 = @extern(?[*]u8, .{ .name = "__zitrus_main_tls_end" });

    if (opt_tls_start) |tls_start| return opt_tls_end.? - tls_start;
    return 0;
}

/// Gets the `Block` of the current thread.
///
/// `zitrus` reserves some needed state and storage
/// for some features.
pub inline fn get() *Block {
    return asm volatile ("mrc p15, 0, %[tls], cr13, cr0, 3"
        : [tls] "=r" (-> *Block),
    );
}

fn __aeabi_read_tp() callconv(.naked) void {
    const tp_offset = (@offsetOf(Block, "state") + @offsetOf(Block.State, "tp"));

    // NOTE: ABI mandates to only clobber `r0`.
    asm volatile (
        \\ mrc p15, 0, r0, cr13, cr0, 3
        \\ ldr r0, [r0, %[tp_offset]]
        \\ bx lr
        :
        : [tp_offset] "i" (tp_offset),
        : .{ .r0 = true });
}

const Index = extern struct { module: usize, offset: usize };

export fn __tls_get_addr(index: *const Index) *anyopaque {
    return @ptrFromInt(@intFromPtr(get().state.tp) + index.offset);
}

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const AddressArbiter = horizon.AddressArbiter;

const ipc = horizon.ipc;
const Exception = horizon.ErrorDisplayManager.Exception;
