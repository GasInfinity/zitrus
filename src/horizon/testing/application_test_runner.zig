comptime {
    if (!builtin.cpu.arch.isArm() or builtin.os.tag != .other) {
        @compileError("this test runner is only intended for tests on the Nintendo 3DS OS");
    }

    // For `_start`
    _ = zitrus.horizon.start;
}

pub const std_options: std.Options = .{
    .logFn = log,
};

var debug_buffer: [8 * 1024]u8 = undefined;
var debug_writer: std.Io.Writer = horizon.outputDebugWriter(&debug_buffer);
var log_err_count: usize = 0;

pub fn main() void {
    @disableInstrumentation();

    const srv = horizon.ServiceManager.open() catch unreachable;
    defer srv.close();

    srv.sendRegisterClient() catch unreachable;

    var notif_man = horizon.ServiceManager.Notification.Manager.init(srv) catch unreachable;
    defer notif_man.deinit();

    const apt = horizon.services.Applet.open(.app, srv) catch unreachable;
    defer apt.close();

    horizon.testing.apt = apt;
    defer horizon.testing.apt = undefined;

    const gsp = horizon.services.GspGpu.open(srv) catch unreachable;
    defer gsp.close();

    horizon.testing.gsp = gsp;
    defer horizon.testing.gsp = undefined;

    var app = horizon.services.Applet.Application.init(apt, .app, srv) catch unreachable;
    defer app.deinit(apt, .app, srv);

    // NOTE: We want std.debug.print behaviour, we don't want to lose our logged info if the app crashes!
    const test_fn_list = builtin.test_functions;

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;

    for (test_fn_list, 0..) |test_fn, i| {
        // FIXME: Upstream blocker, cannot use DebugAllocator
        // testing.allocator_instance

        testing.log_level = .warn;

        if (test_fn.func()) |_| {
            ok_count += 1;
            debug_writer.print("{d}/{d} {s}... OK\n", .{ i + 1, test_fn_list.len, test_fn.name }) catch {};
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                debug_writer.print("{d}/{d} {s}... SKIP\n", .{ i + 1, test_fn_list.len, test_fn.name }) catch {};
            },
            else => {
                fail_count += 1;
                debug_writer.print("{d}/{d} {s}... FAIL\n", .{ i + 1, test_fn_list.len, test_fn.name }) catch {};

                if (@errorReturnTrace()) |_| {
                    // FIXME: Upstream blocker, dump trace / debug info
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

    debug_writer.flush() catch {};

    if (log_err_count != 0 or fail_count != 0) {
        const hid = horizon.services.Hid.open(.user, srv) catch unreachable;
        defer hid.close();

        var input = horizon.services.Hid.Input.init(hid) catch unreachable;
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
    comptime scope: @Type(.enum_literal),
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
