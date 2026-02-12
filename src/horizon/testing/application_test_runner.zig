comptime {
    if (!builtin.cpu.arch.isArm() or builtin.os.tag != .@"3ds") {
        @compileError("this test runner is only intended for tests on Horizon!");
    }
}

pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;
pub const std_options_debug_io: std.Io = hio.io();
pub const std_options: std.Options = .{
    .logFn = log,
    .allow_stack_tracing = true,
};

var hio: horizon.Io = undefined;
var debug_buffer: [8 * 1024]u8 = undefined;
var debug_writer: std.Io.Writer = horizon.outputDebugWriter(&debug_buffer);
var log_err_count: usize = 0;

pub fn main() !void {
    @disableInstrumentation();

    const arbiter = horizon.AddressArbiter.create() catch @panic("Error creating address arbiter");
    defer arbiter.close();

    horizon.testing.arbiter = arbiter;
    defer horizon.testing.arbiter = undefined;

    var common_allocator: horizon.heap.CommitAllocator = .init(arbiter, horizon.memory.heap_begin);
    defer common_allocator.deinit();

    hio = try .init(common_allocator.allocator(), arbiter);
    defer hio.deinit();

    const srv = horizon.ServiceManager.open() catch @panic("Error opening connection to srv:");
    defer srv.close();

    srv.sendRegisterClient() catch @panic("Error registering in srv:");

    var notif_man = horizon.ServiceManager.Notification.Manager.init(srv) catch @panic("Error initializing Notification Manager");
    defer notif_man.deinit();

    horizon.testing.srv = srv;
    defer horizon.testing.srv = undefined;

    const apt = horizon.services.Applet.open(.app, srv) catch @panic("Error opening connection to APT:A");
    defer apt.close();

    horizon.testing.apt = apt;
    defer horizon.testing.apt = undefined;

    const gsp = horizon.services.GspGpu.open(srv) catch @panic("Error opening connection to gsp::GPU");
    defer gsp.close();

    horizon.testing.gsp = gsp;
    defer horizon.testing.gsp = undefined;

    var app = horizon.services.Applet.Application.init(apt, .app, srv) catch @panic("Error initializing Application");
    defer app.deinit(apt, .app, srv);

    // NOTE: We want std.debug.print behaviour, we don't want to lose our logged info if the app crashes!
    const test_fn_list = builtin.test_functions;

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;
    var leaks: usize = 0;

    for (test_fn_list, 0..) |test_fn, i| {
        testing.log_level = .warn;

        horizon.testing.allocator_instance = .{ .backing_allocator = common_allocator.allocator() };
        horizon.testing.io_instance = try .init(horizon.testing.allocator, arbiter);

        defer {
            horizon.testing.io_instance.deinit();
            if (horizon.testing.allocator_instance.deinit() == .leak) leaks += 1;
        }

        debug_writer.print("{d}/{d} {s}... ", .{ i + 1, test_fn_list.len, test_fn.name }) catch {};
        debug_writer.flush() catch {};

        if (test_fn.func()) |_| {
            ok_count += 1;
            debug_writer.writeAll("OK\n") catch {};
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                debug_writer.writeAll("SKIP\n") catch {};
            },
            else => {
                fail_count += 1;
                debug_writer.print("FAIL ({t})\n", .{err}) catch {};

                if (@errorReturnTrace()) |trace| {
                    std.debug.writeStackTrace(trace, .{ .writer = &debug_writer, .mode = .no_color }) catch {};
                }
            },
        }

        debug_writer.flush() catch {};
    }

    if (ok_count == test_fn_list.len) {
        debug_writer.print("All {d} tests passed.\n", .{ok_count}) catch {};
    } else {
        debug_writer.print("{d} passed; {d} skipped; {d} failed.\n", .{ ok_count, skip_count, fail_count }) catch {};
    }

    if (log_err_count != 0) {
        debug_writer.print("{d} errors were logged.\n", .{log_err_count}) catch {};
    }

    if (leaks != 0) {
        debug_writer.print("{d} tests leaked memory.\n", .{leaks}) catch {};
    }

    debug_writer.flush() catch {};

    if (log_err_count != 0 or fail_count != 0) {
        const hid = horizon.services.Hid.open(.user, srv) catch @panic("Error opening connection to hid:USER");
        defer hid.close();

        var input = horizon.services.Hid.Input.init(hid) catch @panic("Error initializing Hid Input");
        defer input.deinit();

        // TODO: we could wait instead!
        while (true) {
            const polled_pad = input.pollPad();
            const current = polled_pad.current;

            if (current.a or current.start) {
                break;
            }
        }
    }
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    @disableInstrumentation();

    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) {
        log_err_count +|= 1;
    }

    if (@intFromEnum(message_level) <= @intFromEnum(testing.log_level)) {
        debug_writer.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n",
            args,
        ) catch {};

        debug_writer.flush() catch {};
    }
}

const testing = std.testing;

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
