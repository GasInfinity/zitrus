//! Minimal replacement for std.debug and overrides.

/// Print to the debug console. Intended for use in "printf
/// debugging". Use `std.log` functions for proper logging.
///
/// Uses a 64-byte buffer for formatted printing which is flushed before this
/// function returns.
///
/// Never fails, uses `horizon.outputDebugWriter`
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [64]u8 = undefined;
    var debug_writer = horizon.outputDebugWriter(&buf);
    debug_writer.print(fmt, args) catch unreachable;
    debug_writer.flush() catch unreachable;
}

// TODO: We have to get Dwarf info in some way or another...

pub const SelfInfo = @import("debug/SelfInfo.zig");

pub fn getDebugInfoAllocator() std.mem.Allocator {
    return .failing;
}

pub fn printLineFromFile(_: std.Io, _: *std.Io.Writer, _: std.debug.SourceLocation) !void {
    return error.Unsupported;
}

/// Non-zero whenever the program triggered a panic.
/// The counter is incremented/decremented atomically.
var panicking = std.atomic.Value(u8).init(0);

/// Counts how many times the panic handler is invoked by this thread.
/// This is used to catch and handle panics triggered by the panic handler.
var panic_stage: usize = 0;

/// Stores the panic stacktrace
var panic_buffer: [1024]u8 = undefined;

pub fn defaultPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);

    // If somehow we didn't exit with errdisp (e.g on some emulators)
    // we don't want to return!
    defer while (true) horizon.breakExecution(.panic);
    
    var fixed: std.Io.Writer = .fixed(&panic_buffer);
    const fixed_terminal: std.Io.Terminal = .{
        .writer = &fixed,
        .mode = .no_color,
    };

    const unwind_first_trace_addr = first_trace_addr orelse @returnAddress();

    switch (panic_stage) {
        0 => {
            panic_stage = 1;
            _ = panicking.fetchAdd(1, .seq_cst);

            trace: {
                if (builtin.single_threaded) {
                    fixed.print("panic: ", .{}) catch break :trace;
                } else {
                    const current_thread_id = horizon.getThreadId(.current).value;
                    fixed.print("thread {d} panic: ", .{@intFromEnum(current_thread_id)}) catch break :trace;
                }

                fixed.print("{s}\n", .{msg}) catch break :trace;

                if (@errorReturnTrace()) |t| if (t.index > 0) {
                    fixed.writeAll("error return context:\n") catch break :trace;
                    std.debug.writeStackTrace(t, fixed_terminal) catch break :trace;
                    fixed.writeAll("\nstack trace:\n") catch break :trace;
                };

                std.debug.writeCurrentStackTrace(.{
                    .first_address = unwind_first_trace_addr,
                    .allow_unsafe_unwind = true, // we're crashing anyway, give it our all!
                }, fixed_terminal) catch break :trace;
            }

            print("{s}\n", .{fixed.buffered()}); // XXX: azahar doesn't implement setUserString

            var errdisp = horizon.ErrorDisplayManager.open() catch {
                print("panic: could not open err:f connection\n", .{});
                while (true) horizon.breakExecution(.panic);
            };
            defer errdisp.close();

            errdisp.sendSetUserString(fixed.buffered()) catch print("panic: 'err:f' could not set user string", .{});
            errdisp.sendThrow(.{
                .type = .failure,
                .revision_high = 0x00,
                .revision_low = 0x00,
                .result_code = .failure,
                .pc_address = unwind_first_trace_addr,
                .process_id = @intFromEnum(horizon.getProcessId(.current).value), // NOTE: cannot fail as current is always valid.
                .title_id = 0x0,
                .applet_title_id = 0x0,
                .data = .{ .failure = .{
                    .message = if (msg.len > 0x5F) (msg[0..0x5F].* ++ .{0}) else buf: {
                        var buffer: [0x60]u8 = undefined;
                        @memcpy(buffer[0..msg.len], msg);
                        @memset(buffer[msg.len..], 0x00);
                        break :buf buffer;
                    },
                } },
            }) catch print("panic: 'err:f' could not throw with message '{s}'", .{msg});
        },
        1 => {
            panic_stage = 2;

            // A panic happened while trying to get the stacktrace, connect to err:f or throw.
            //
            // We're going to let `breakExecution` do the job
            print("panic: recursive panic\n", .{});
        },
        else => {}, // Truly unreachable but we never know!
    }
}

const enable_segfault_handler = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
} or std.options.enable_segfault_handler;

pub fn maybeEnableSegfaultHandler() void {
    if (enable_segfault_handler) {
        horizon.tls.get().exception = .{
            .stack = .inherit,
            .context = .store_inherited,
            .entry = &handleSegfaultHorizon,
        };

        zitrus.hardware.cpu.cache.dataSynchronizationBarrier();
        zitrus.hardware.cpu.cache.flushPrefetchBuffer();
    }
}

fn handleSegfaultHorizon(info: *const Exception.Info, registers: *const Exception.Registers) callconv(.c) noreturn {
    const name: []const u8, const addr: ?usize = switch (info.type) {
        .prefetch_abort => .{
            switch (info.fault.status()) {
                _ => "Prefetch Abort",
                inline else => |status| std.fmt.comptimePrint("({t}) Prefetch Abort", .{status}),
            },
            info.address,
        },
        .data_abort => .{
            switch (info.fault.operation) {
                inline else => |op| switch (info.fault.status()) {
                    _ => std.fmt.comptimePrint("({t}) Data Abort", .{op}),
                    inline else => |status| std.fmt.comptimePrint("({t}, {t}) Data Abort", .{op, status}),
                },
            },
            info.address,
        },
        .undefined => .{"Illegal Instruction", info.address },
        .vfp => .{"Arithmetic Exception", info.address },
    };

    const opt_ctx: std.debug.cpu_context.Native = .{ .r = registers.gpr };

    // Allow overriding the target-agnostic segfault handler by exposing `root.debug.handleSegfault`.
    if (@hasDecl(root, "debug") and @hasDecl(root.debug, "handleSegfault")) {
        return root.debug.handleSegfault(addr, name, &opt_ctx);
    }

    return defaultHandleSegfault(addr, name, &opt_ctx);
}

/// Like defaultPanic, the default segfault handler just calls ErrorDisplay
pub fn defaultHandleSegfault(addr: ?usize, name: []const u8, opt_ctx: ?std.debug.CpuContextPtr) noreturn {
    @branchHint(.cold);

    // If somehow we didn't exit with errdisp (e.g on some emulators)
    // we don't want to return!
    defer while (true) horizon.breakExecution(.panic);

    var fixed: std.Io.Writer = .fixed(&panic_buffer);
    const fixed_terminal: std.Io.Terminal = .{
        .writer = &fixed,
        .mode = .no_color,
    };

    switch (panic_stage) {
        0 => {
            panic_stage = 1;
            _ = panicking.fetchAdd(1, .seq_cst);

            trace: {
                if (addr) |a| {
                    fixed.print("{s} at address 0x{x}\n", .{ name, a }) catch break :trace;
                } else {
                    fixed.print("{s} (no address available)\n", .{name}) catch break :trace;
                }
                if (opt_ctx) |context| {
                    std.debug.writeCurrentStackTrace(.{
                        .context = context,
                        .allow_unsafe_unwind = true, // we're crashing anyway, give it our all!
                    }, fixed_terminal) catch break :trace;
                }
            }

            var errdisp = horizon.ErrorDisplayManager.open() catch {
                print("panic: could not open err:f connection\n", .{});
                while (true) horizon.breakExecution(.panic);
            };
            defer errdisp.close();
            errdisp.sendSetUserString(fixed.buffered()) catch print("panic: 'err:f' could not set user string", .{});
            errdisp.sendThrow(.{
                .type = .failure,
                .revision_high = 0x00,
                .revision_low = 0x00,
                .result_code = .failure,
                .pc_address = if (opt_ctx) |ctx| ctx.r[15] else 0xDEADBEEF,
                .process_id = @intFromEnum(horizon.getProcessId(.current).value), // NOTE: cannot fail as current is always valid.
                .title_id = 0x0,
                .applet_title_id = 0x0,
                .data = .{ .failure = .{
                    .message = if (name.len > 0x5F) (name[0..0x5F].* ++ .{0}) else buf: {
                        var buffer: [0x60]u8 = undefined;
                        @memcpy(buffer[0..name.len], name);
                        @memset(buffer[name.len..], 0x00);
                        break :buf buffer;
                    },
                } },
            }) catch print("panic: 'err:f' could not throw with message '{s}'", .{name});
        },
        1 => {
            panic_stage = 2;

            // A panic happened while trying to get the stacktrace, connect to err:f or throw.
            //
            // We're going to let `breakExecution` do the job
            print("panic: recursive panic\n", .{});
        },
        else => {}, // Truly unreachable but we never know!
    }
}

const root = @import("root");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
const Exception = horizon.ErrorDisplayManager.Exception;
