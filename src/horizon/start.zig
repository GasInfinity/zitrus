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
const stack_size: u32 = if (@hasDecl(root, "zitrus_options") and @FieldType(root, "zitrus_options") != zitrus.ZitrusOptions) root.zitrus_options.stack_size else 128 * 1024;
var allocated_stack: [stack_size]u8 align(8) linksection(".bss.allocated_stack") = undefined;

fn startup() callconv(.naked) noreturn {
    @disableInstrumentation();
    @setRuntimeSafety(false);
    // TODO: Add .cantunwind: https://github.com/llvm/llvm-project/issues/115891
    asm volatile (
        \\ mov sp, %[allocated_stack]
        \\ add sp, sp, %[stack_size]
        \\ b %[callMainAndExit]
        :
        : [callMainAndExit] "X" (&callMainAndExit),
          [allocated_stack] "r" (&allocated_stack),
          [stack_size] "i" (stack_size),

          // Needed as it will be optimized if not.
          [program_meta] "p" (&environment.program_meta),
        : .{ .memory = true });
}

fn callMainAndExit() callconv(.c) noreturn {
    @setRuntimeSafety(false);
    @disableInstrumentation();

    if (!builtin.single_threaded) horizon.tls.initStatic();

    horizon.debug.maybeEnableSegfaultHandler();

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

    // Maybe log to errdisp if return was not 0?
    _ = callMain(&.{}, .empty);
    horizon.exit();
}

inline fn callMain(args: std.process.Args.Vector, environ: std.process.Environ.Block) u8 {
    const fn_info = @typeInfo(@TypeOf(root.main)).@"fn";
    if (fn_info.params.len == 0) return wrapMain(root.main());

    const First = fn_info.params[0].type.?;

    if (First == std.process.Init.Minimal) return wrapMain(root.main(.{
        .args = .{ .vector = args },
        .environ = .{ .block = environ },
    }));

    if (comptime std.mem.findScalar(type, juice, First) == null) {
        @compileError("Unsupported main parameter '" ++ @typeInfo(First) ++ "'");
    }

    return wrapMain(juiceMain(args, environ));
}

const juice: []const type = base_juice ++ application_juice;

const base_juice: []const type = &.{
    horizon.Init,
};

const application_juice: []const type = &.{
    horizon.Init.Application,
    horizon.Init.Application.Software,
    horizon.Init.Application.Mango,
};

fn UnwrapError(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .error_union => |e| e.payload,
        else => T,
    };
}

inline fn juiceMain(_: std.process.Args.Vector, _: std.process.Environ.Block) !UnwrapError(@typeInfo(@TypeOf(root.main)).@"fn".return_type.?) {
    const First = @typeInfo(@TypeOf(root.main)).@"fn".params[0].type.?; // NOTE: We already know we have 1 parameter.
    const Init = horizon.Init;
    const services = horizon.services;

    const arbiter: horizon.AddressArbiter = try .create();
    defer arbiter.close();

    // XXX: Use debug_allocator if possible in debug mode, currently we cannot use it as it depends on `std.Io.Threaded`
    var allocator_instance: horizon.heap.CommitAllocator = .init(arbiter, horizon.memory.heap_begin);
    defer allocator_instance.deinit();

    const gpa = allocator_instance.allocator();

    horizon.Io.global.* = .init(gpa, arbiter);
    defer horizon.Io.global.deinit();

    const base: Init = .{
        .arbiter = arbiter,
        .gpa = gpa,
        .io = horizon.Io.debug_io,
    };

    if (First == Init) return root.main(base);

    if (comptime std.mem.findScalar(type, application_juice, First)) |_| {
        const srv = try horizon.ServiceManager.open();
        defer srv.close();

        try srv.sendRegisterClient();

        const apt: services.Applet = try .open(.app, srv);
        defer apt.close();

        const gsp: services.GraphicsServerGpu = try .open(srv);
        defer gsp.close();

        const hid: services.Hid = try .open(.user, srv);
        defer hid.close();

        var notif_man: horizon.ServiceManager.Notification.Manager = try .init(srv);
        defer notif_man.deinit();

        var app: services.Applet.Application = try .init(apt, .app, srv);
        defer app.deinit(apt, .app, srv);

        var input: services.Hid.Input = try .init(hid);
        defer input.deinit();

        const app_init: horizon.Init.Application = .{
            .base = base,
            .srv = srv,
            .apt = apt,
            .gsp = gsp,
            .hid = hid,

            .notification_manager = &notif_man,
            .app = &app,
            .input = &input,
        };

        return switch (First) {
            Init.Application => root.main(app_init),
            Init.Application.Software => blk: {
                const config: services.GraphicsServerGpu.Graphics.Software.Config = if (@hasDecl(root, "init_options"))
                    @field(root, "init_options")
                else
                    .{};

                var soft: services.GraphicsServerGpu.Graphics.Software = try .init(config, gsp, horizon.heap.linear_page_allocator);
                defer soft.deinit(gsp, horizon.heap.linear_page_allocator, app.flags.must_close);

                break :blk root.main(.{
                    .app = app_init,
                    .soft = &soft,
                });
            },
            Init.Application.Mango => blk: {
                const device = try mango.createHorizonBackedDevice(.{
                    .gsp = gsp,
                    .arbiter = arbiter,
                }, gpa);
                defer device.destroy();

                break :blk root.main(.{
                    .app = app_init,
                    .device = device,
                });
            },
            else => comptime unreachable,
        };
    }
}

const bad_main_ret = "expected return type of main to be 'void', '!void', 'noreturn', 'u8', or '!u8'";

inline fn wrapMain(result: anytype) u8 {
    const ReturnType = @TypeOf(result);
    switch (ReturnType) {
        void => return 0,
        noreturn => unreachable,
        u8 => return result,
        else => {},
    }
    if (@typeInfo(ReturnType) != .error_union) @compileError(bad_main_ret);

    const unwrapped_result = result catch |err| @panic(@errorName(err));

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
const mango = zitrus.mango;
const environment = horizon.environment;

const ErrorDisplayManager = horizon.ErrorDisplayManager;
