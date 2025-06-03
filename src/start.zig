comptime {
    _ = root;

    if (builtin.target.os.tag == .other and !@hasDecl(root, "_start") and @hasDecl(root, "main")) {
        @export(&_start, .{ .name = "_start" });

        // Ensure we export the .prm section
        _ = environment;
    }
}

// XXX: We're doing this as literally the program metadata is embedded in the start of the binary
fn _start() linksection(".init") callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    asm volatile ("b %[startup]"
        :
        : [startup] "X" (&startup),
    );
}

const stack_size: u32 = if (@hasDecl(root, "zitrus_options") and @FieldType(root, "zitrus_options") != zitrus.ZitrusOptions) root.zitrus_options.stack_size else 32768;
var allocated_stack: [stack_size]u8 align(8) linksection(".bss.allocated_stack") = undefined;

fn startup() linksection(".startup") callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    // TODO: Add .cantunwind: https://github.com/llvm/llvm-project/issues/115891
    asm volatile (
        \\ str lr, [%[exit_fn]]
        \\ mov sp, %[allocated_stack]
        \\ add sp, sp, %[stack_size]
        \\ b %[callMainAndExit]
        :
        : [callMainAndExit] "X" (&callMainAndExit),
          [exit_fn] "r" (&environment.exit_fn),
          [allocated_stack] "r" (&allocated_stack),
          [stack_size] "r" (stack_size),

          // Unused here but needed if we want zig to NOT optimize further reads!
          [program_meta] "r" (&environment.program_meta),
        : "memory"
    );
}

fn callMainAndExit() callconv(.c) noreturn {
    @setRuntimeSafety(false);
    @disableInstrumentation();

    const possible_argument_list = environment.program_meta.argument_list;

    const argc: usize, const argv: [*][*:0]u8 = if (possible_argument_list) |argument_list|
        .{ argument_list[0], @ptrCast(&argument_list[1]) }
    else
        .{ 0, &[_][*:0]u8{} };

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

    // TODO: Log to errdisp if return was not 0?
    _ = callMainWithArgs(argc, argv);

    if (environment.exit_fn) |exit_fn| {
        exit_fn();
    }

    horizon.exit();
}

const bad_main_ret = "expected return type of main to be 'void', '!void', 'noreturn', 'u8', or '!u8'";

inline fn callMainWithArgs(argc: usize, argv: [*][*:0]u8) u8 {
    const ReturnType = @typeInfo(@TypeOf(root.main)).@"fn".return_type.?;
    std.os.argv = argv[0..argc];

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

            const result = root.main() catch |err| zitrus.panic.throw(@errorName(err), @errorReturnTrace());

            return switch (@TypeOf(result)) {
                void => 0,
                u8 => result,
                else => @compileError(bad_main_ret),
            };
        },
    }
}

const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = zitrus.environment;

const ErrorDisplayManager = horizon.ErrorDisplayManager;
