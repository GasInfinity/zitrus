//! NOTE: The majority of this code is copy-pasted from the zig stdlib as we want to support the same entrypoints!

comptime {
    _ = root;

    if (builtin.target.os.tag == .@"3ds" and !@hasDecl(root, "_start") and @hasDecl(root, "main")) {
        @export(&_start, .{ .name = "_start" });

        // Ensure we export the .prm section
        _ = environment;
    }
}

// XXX: We're doing this as literally the program metadata is embedded in the start of the binary
fn _start() linksection(".text.base") callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    asm volatile ("b %[startup]"
        :
        : [startup] "X" (&startup),
    );
}

// XXX: Use kernel-provided stack size...
const stack_size: u32 = if (@hasDecl(root, "zitrus_options") and @FieldType(root, "zitrus_options") != zitrus.ZitrusOptions) root.zitrus_options.stack_size else 32768 * 8;
var allocated_stack: [stack_size]u8 align(8) linksection(".bss.allocated_stack") = undefined;

fn startup() callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    // TODO: Add .cantunwind: https://github.com/llvm/llvm-project/issues/115891
    asm volatile (
        \\ mov sp, %[allocated_stack]
        \\ add sp, sp, %[stack_size]
        \\ b %[callMainAndExit]
        :
        : [callMainAndExit] "X" (&callMainAndExit),
          [allocated_stack] "r" (&allocated_stack),
          [stack_size] "r" (stack_size),

          // Unused here but needed if we want zig to NOT optimize further reads!
          [program_meta] "r" (&environment.program_meta),
        : .{ .memory = true });
}

fn callMainAndExit() callconv(.c) noreturn {
    @setRuntimeSafety(false);
    @disableInstrumentation();

    const opt_init_array_start = @extern([*]*const fn () callconv(.c) void, .{
        .name = "__init_array_start",
        .linkage = .weak,
    });
    const opt_init_array_end = @extern([*]*const fn () callconv(.c) void, .{
        .name = "__init_array_end",
        .linkage = .weak,
    });

    if (opt_init_array_start) |init_array_start| {
        const init_array_end = opt_init_array_end.?;
        const slice = init_array_start[0..(init_array_end - init_array_start)];
        for (slice) |func| func();
    }

    horizon.debug.maybeEnableSegfaultHandler();
    // Maybe log to errdisp if return was not 0?
    _ = callMain(&.{}, &.{});
    horizon.exit();
}

inline fn callMain(args: std.process.Args.Vector, environ: std.process.Environ.Block) u8 {
    const fn_info = @typeInfo(@TypeOf(root.main)).@"fn";
    if (fn_info.params.len == 0) return wrapMain(root.main());
    if (fn_info.params[0].type.? == std.process.Init.Minimal) return wrapMain(root.main(.{
        .args = .{ .vector = args },
        .environ = .{ .block = environ },
    }));

    @compileError("Juicy main is currently not available, sorry!");
}

const bad_main_ret = "expected return type of main to be 'void', '!void', 'noreturn', 'u8', or '!u8'";

inline fn callMainWithArgs() u8 {
    const ReturnType = @typeInfo(@TypeOf(root.main)).@"fn".return_type.?;

    switch (ReturnType) {
        void => {
            root.main();
            return 0;
        },
        noreturn, u8 => {
            return root.main();
        },
        else => {
            if (@typeInfo(ReturnType) != .error_union) @compileError(bad_main_ret);

            const result = root.main() catch |err| horizon.panic.throw(@errorName(err), @errorReturnTrace());

            return switch (@TypeOf(result)) {
                void => 0,
                u8 => result,
                else => @compileError(bad_main_ret),
            };
        },
    }
}

inline fn wrapMain(result: anytype) u8 {
    const ReturnType = @TypeOf(result);
    switch (ReturnType) {
        void => return 0,
        noreturn => unreachable,
        u8 => return result,
        else => {},
    }
    if (@typeInfo(ReturnType) != .error_union) @compileError(bad_main_ret);

    const unwrapped_result = result catch |err| {
        std.log.err("{t}", .{err});
        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
        return 1;
    };

    return switch (@TypeOf(unwrapped_result)) {
        noreturn => unreachable,
        void => 0,
        u8 => unwrapped_result,
        else => @compileError(bad_main_ret),
    };
}

const root = @import("root");

const native_os = builtin.target.os.tag;

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;

const ErrorDisplayManager = horizon.ErrorDisplayManager;
