//! Mid-level Applet abstraction to manage and handle Application state.
//!
//! It is overloaded to accept the `Applet` service it is working with.

// NOTE: Lots of assumptions are made as there's not a lot of documentation.
// TODO: Do Applications get request's like lib/sys-applets? Wouldn't make sense but still needs research.

pub const Error = @import("Application/Error.zig");
pub const SoftwareKeyboard = @import("Application/SoftwareKeyboard.zig");
pub const InternetBrowser = @import("Application/InternetBrowser.zig");

pub const NotificationResult = enum {
    no_operation,
    jump_home,
    jump_home_by_power,
    jump_home_rejected,
    sleeping,
    sleep_wakeup,
    must_close_by_shutdown,
    must_close,
};

pub const ExecutionResult = enum {
    resumed,
    jump_home,
    must_close,
};

pub const AppletResult = union(enum) {
    execution: ExecutionResult,
    message: Applet.ParameterResult,
};

pub const State = packed struct(u8) {
    pub const default: State = .{ .allow_home = true, .allow_sleep = true };
    pub const safe: State = .{ .allow_home = false, .allow_sleep = true };

    allow_home: bool = false,
    allow_sleep: bool = false,
    sleeping: bool = false,
    must_close: bool = false,

    _: u4 = 0,
};

notification_event: Event,
parameters_event: Event,
chainload: Applet.ChainloadTarget,
flags: State,
capture_copy_memory: [*]align(horizon.heap.page_size) u8,

pub fn init(apt: Applet, service: Applet.Service, srv: ServiceManager) !Application {
    const attr: Applet.Attributes = .{ .pos = .app, .acquire_gpu = false, .acquire_dsp = false };
    const notification, const parameters = try apt.sendInitialize(service, srv, environment.program_meta.app_id, attr);

    try apt.sendEnable(service, srv, attr);

    // We must wait for the wakeup command we get after initializing and enabling ourselves
    {
        try parameters.wait(.none);
        var parameter = try apt.sendReceiveParameter(service, srv, environment.program_meta.app_id, &.{});
        defer parameter.deinit();

        std.debug.assert(parameter.cmd == .wakeup);
        resumeApplication(apt, service, srv);
    }

    // NOTE: enough for any capture
    const capture_conversion_memory = horizon.heap.allocShared(400 * 256 * 4 * 2 + 320 * 256 * 4 * 2);

    return .{
        .notification_event = notification,
        .parameters_event = parameters,
        .chainload = if (environment.program_meta.runtime_flags.apt_chainload) .soft_reset else .none,
        .flags = .default,
        .capture_copy_memory = capture_conversion_memory,
    };
}

pub fn deinit(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager) void {
    const perform_apt_exit = if (app.flags.must_close)
        true
    else if (environment.program_meta.runtime_flags.apt_reinit) ri: {
        apt.sendFinalize(service, srv, environment.program_meta.app_id) catch unreachable;
        break :ri false;
    } else switch (app.chainload) {
        .none => true,
        else => close: {
            const program_id: u64, const media_type: Filesystem.MediaType, const flags: Applet.command.PrepareToDoApplicationJump.Request.Flags, const parameters: []const u8, const hmac: *const [0x20]u8 = switch (app.chainload) {
                .caller => .{ 0x00, .nand, .use_ns_parameters, &.{}, &@splat(0) },
                .soft_reset => .{ 0x00, .nand, .use_app_id_parameters, &.{}, &@splat(0) },
                else => @panic("TODO: chainload"),
            };

            const man_info = apt.sendGetAppletManInfo(service, srv, .none) catch unreachable;

            if ((apt.sendIsRegistered(service, srv, man_info.home_menu) catch false)) {
                apt.sendPrepareToDoApplicationJump(service, srv, flags, program_id, media_type) catch unreachable;
                apt.sendDoApplicationJump(service, srv, parameters, hmac) catch unreachable;
            } else {
                apt.sendFinalize(service, srv, man_info.home_menu) catch unreachable;
                @panic("TODO: 'Dirty' Luma3DS chainloading");
            }

            break :close false;
        },
    };

    if (perform_apt_exit) {
        apt.sendPrepareToCloseApplication(service, srv, true) catch {};
        apt.sendCloseApplication(service, srv, &.{}, .none) catch {};
    }

    app.notification_event.close();
    app.parameters_event.close();
    app.* = undefined;
}

pub fn setSleepAllowed(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, allow: bool) void {
    const was_allowed = app.flags.allow_sleep;
    app.flags.allow_sleep = allow;

    if (!was_allowed and allow) {
        apt.sendSleepIfShellClosed(service, srv) catch unreachable;
    } else if (was_allowed and !allow) {
        apt.sendReplySleepQuery(service, srv, environment.program_meta.app_id, .reject) catch unreachable;
    }
}

pub fn waitNotification(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager) !NotificationResult {
    return (try app.waitNotificationTimeout(apt, service, srv, .none)).?;
}

pub fn pollNotification(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager) !?NotificationResult {
    return app.waitNotificationTimeout(apt, service, srv, .fromNanoseconds(0));
}

pub fn waitNotificationTimeout(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, timeout: horizon.Timeout) !?NotificationResult {
    app.notification_event.wait(timeout) catch |err| switch (err) {
        error.Timeout => return null,
        else => return err,
    };

    const notification = try apt.sendInquireNotification(service, srv, environment.program_meta.app_id);
    notif_handling: switch (notification) {
        .none => {},
        .home_button_1, .home_button_2 => {
            if (!app.flags.allow_home) {
                clearJumpToHome(apt, service, srv);
                return .jump_home_rejected;
            } else {
                return .jump_home;
            }
        },
        .sleep_query => {
            const reply: Applet.QueryReply = if (app.flags.allow_sleep)
                .accept
            else
                .reject;
            try apt.sendReplySleepQuery(service, srv, environment.program_meta.app_id, reply);
        },
        .sleep_accepted => {
            app.flags.sleeping = true;
            try apt.sendReplySleepNotificationComplete(service, srv, environment.program_meta.app_id);
            return .sleeping;
        },
        .sleep_canceled_by_open => continue :notif_handling .sleep_wakeup,
        .sleep_wakeup => blk: {
            if (!app.flags.sleeping) break :blk;

            app.flags.sleeping = false;
            return .sleep_wakeup;
        },
        .shutdown => {
            app.flags.must_close = true;
            return .must_close_by_shutdown;
        },
        .power_button_click => return .jump_home_by_power,
        .power_button_clear => {},
        .try_sleep => {}, // TODO
        .order_to_close => {
            app.flags.must_close = true;
            return .must_close;
        },
        else => {},
    }

    return .no_operation;
}

fn waitParameterConsumingNotifications(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, parameter: []u8) !Applet.ParameterResult {
    while (true) {
        const is_parameter = try Event.waitMany(&.{ app.notification_event, app.parameters_event }, false, .none) == 1;

        if (!is_parameter) {
            notif_handling: switch (try apt.sendInquireNotification(service, srv, environment.program_meta.app_id)) {
                .none, .home_button_1, .home_button_2, .power_button_click, .power_button_clear => {},
                // We're waiting so just accept it!
                .sleep_query => try apt.sendReplySleepQuery(service, srv, environment.program_meta.app_id, .accept),
                .sleep_accepted => {
                    app.flags.sleeping = true;
                    try apt.sendReplySleepNotificationComplete(service, srv, environment.program_meta.app_id);
                },
                .sleep_canceled_by_open => continue :notif_handling .sleep_wakeup,
                .sleep_wakeup => blk: {
                    if (!app.flags.sleeping) break :blk;
                    app.flags.sleeping = false;
                },
                .shutdown => app.flags.must_close = true,
                .try_sleep => {}, // TODO
                .order_to_close => app.flags.must_close = true,
                else => {},
            }

            continue;
        }

        return try apt.sendReceiveParameter(service, srv, environment.program_meta.app_id, parameter);
    }
}

pub fn waitAppletResult(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, parameter: []u8) !AppletResult {
    const parameters = try app.waitParameterConsumingNotifications(apt, service, srv, parameter);
    switch (parameters.cmd) {
        .wakeup, .request, .response => unreachable, // NOTE: Should only be sent at Application start? + do we get requests? + we're not waiting for a response!
        .wakeup_by_exit, .wakeup_by_cancel, .wakeup_by_cancelall, .wakeup_by_pause, .wakeup_to_jump_home, .wakeup_by_power_button_click => |cmd| {
            defer switch (cmd) {
                .wakeup_to_jump_home, .wakeup_by_power_button_click => apt.sendLockTransition(service, srv, .jump_home, true) catch unreachable,
                else => {
                    resumeApplication(apt, service, srv);
                    clearJumpToHome(apt, service, srv);
                },
            };

            switch (cmd) {
                .wakeup_by_cancel, .wakeup_by_cancelall => app.flags.must_close = true,
                else => {},
            }

            return .{ .execution = switch (cmd) {
                .wakeup_by_pause, .wakeup_by_exit => .resumed,
                .wakeup_by_cancel, .wakeup_by_cancelall => .must_close,
                .wakeup_to_jump_home, .wakeup_by_power_button_click => .jump_home,
                else => unreachable,
            } };
        },
        .message => return .{ .message = parameters },
        else => unreachable,
    }
}

// NOTE: we also need to wakeup the dsp if needed when implemented. but not here!
pub fn jumpToHome(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, capture: GraphicsServerGpu.ScreenCapture, params: Applet.JumpToHomeParameters) !ExecutionResult {
    const last_allow_sleep = app.flags.allow_sleep;

    app.setSleepAllowed(apt, service, srv, false);
    defer app.setSleepAllowed(apt, service, srv, last_allow_sleep);

    try apt.sendPrepareToJumpToHomeMenu(service, srv);

    const home_app_id = (try apt.sendGetAppletManInfo(service, srv, .none)).home_menu;
    try app.screenTransfer(apt, service, srv, capture, home_app_id, false);

    try apt.sendJumpToHomeMenu(service, srv, params);

    // XXX: Does the home menu return any kind of parameters?
    return switch (try app.waitAppletResult(apt, service, srv, &.{})) {
        .execution => |e| switch (e) {
            .jump_home => unreachable, // NOTE: Doesn't make sense, you jump home and wake me up to return to you again? Only makes sense for applets.
            else => e,
        },
        .message => unreachable,
    };
}

pub fn startLibraryApplet(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, capture: GraphicsServerGpu.ScreenCapture, app_id: Applet.AppId, param_handle: Object, param: []const u8) !void {
    const last_allow_sleep = app.flags.allow_sleep;

    app.setSleepAllowed(apt, service, srv, false);
    defer app.setSleepAllowed(apt, service, srv, last_allow_sleep);

    try apt.sendPrepareToStartLibraryApplet(service, srv, app_id);
    try app.screenTransfer(apt, service, srv, capture, app_id, true);

    // Sleep dsp
    try apt.sendStartLibraryApplet(service, srv, app_id, param_handle, param);
}

// NOTE: This will stay with the same interface as jump to home as I don't know of a system applet which returns data.
pub fn launchSystemApplet(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, capture: GraphicsServerGpu.ScreenCapture, app_id: Applet.AppId, param_handle: Object, param: []const u8) !ExecutionResult {
    const last_allow_sleep = app.flags.allow_sleep;

    app.setSleepAllowed(apt, service, srv, false);
    defer app.setSleepAllowed(apt, service, srv, last_allow_sleep);

    try apt.sendPrepareToStartSystemApplet(srv, service, app_id);
    try apt.sendStartSystemApplet(srv, app_id, param_handle, param);
    try app.screenTransfer(apt, srv, service, capture, app_id, false);

    return switch (try app.waitAppletResult(apt, srv, &.{})) {
        .execution => |e| e,
        .message => unreachable, // XXX: Same as with jumping to home...
    };
}

// NOTE: This is just straight up taken from libctru. I didn't know why jumping to home was not working, now I know :p
pub fn screenTransfer(app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, capture: GraphicsServerGpu.ScreenCapture, target_app_id: Applet.AppId, copy_framebuffers: bool) !void {
    const apt_capture_info = Applet.CaptureBuffer.init(capture);

    while (!(try apt.sendIsRegistered(service, srv, target_app_id))) {
        // XXX: Maybe this could be adjusted? Currently it follows the same behaviour as libctru
        horizon.sleepThread(1000000);
    }

    try apt.sendSendParameter(service, srv, environment.program_meta.app_id, target_app_id, if (copy_framebuffers) .request else .request_for_sys_applet, .none, std.mem.asBytes(&apt_capture_info));

    try app.parameters_event.wait(.none);
    var parameters = try apt.sendReceiveParameter(service, srv, environment.program_meta.app_id, &.{});
    defer parameters.deinit();

    std.debug.assert(parameters.cmd == .response);

    if (copy_framebuffers) {
        const pica = zitrus.hardware.pica;
        const capture_shm: horizon.MemoryBlock = @bitCast(parameters.handle);

        const mem = app.capture_copy_memory;

        try capture_shm.map(mem, .rw, .rw);
        defer capture_shm.unmap(mem);

        if (apt_capture_info.bottom.format.native()) |pfmt| pica.morton.convert2(
            .tile,
            8,
            mem[apt_capture_info.bottom.left_offset..][0 .. pica.Screen.height(.bottom) * pica.Screen.width_po2 * pfmt.bytesPerPixel()],
            @as([*]u8, @ptrCast(capture.bottom.left_vaddr))[0 .. pica.Screen.height(.bottom) * pica.Screen.width(.bottom) * pfmt.bytesPerPixel()],
            .{
                .input_x = 0,
                .input_y = 0,
                .input_stride = pica.Screen.width(.bottom) * pfmt.bytesPerPixel(),

                .output_x = 0,
                .output_y = 0,
                .output_stride = pica.Screen.width_po2 * pfmt.bytesPerPixel(),

                .width = pica.Screen.width(.bottom),
                .height = pica.Screen.height(.bottom),

                .pixel_size = pfmt.bytesPerPixel(),
            },
        );

        if (apt_capture_info.top.format.native()) |pfmt| {
            const bpp = pfmt.bytesPerPixel();
            const po2_stride = pica.Screen.width_po2 * bpp;
            const stride = pica.Screen.width(.top) * bpp;
            const total_byte_size = pica.Screen.height(.top) * po2_stride;

            pica.morton.convert2(
                .tile,
                8,
                mem[apt_capture_info.top.left_offset..][0..total_byte_size],
                @as([*]u8, @ptrCast(capture.top.left_vaddr))[0 .. pica.Screen.height(.top) * stride],
                .{
                    .input_x = 0,
                    .input_y = 0,
                    .input_stride = stride,

                    .output_x = 0,
                    .output_y = 0,
                    .output_stride = po2_stride,

                    .width = pica.Screen.width(.top),
                    .height = pica.Screen.height(.top),

                    .pixel_size = bpp,
                },
            );

            if (apt_capture_info.enabled_3d) pica.morton.convert2(
                .tile,
                8,
                mem[apt_capture_info.top.right_offset..][0..total_byte_size],
                @as([*]u8, @ptrCast(capture.top.right_vaddr))[0 .. pica.Screen.height(.top) * stride],
                .{
                    .input_x = 0,
                    .input_y = 0,
                    .input_stride = stride,

                    .output_x = 0,
                    .output_y = 0,
                    .output_stride = po2_stride,

                    .width = pica.Screen.width(.top),
                    .height = pica.Screen.height(.top),

                    .pixel_size = bpp,
                },
            );
        }
    }

    try apt.sendSendCaptureBufferInfo(service, srv, &apt_capture_info);
}

fn clearJumpToHome(apt: Applet, service: Applet.Service, srv: ServiceManager) void {
    apt.sendUnlockTransition(service, srv, .jump_home) catch unreachable;
    apt.sendSleepIfShellClosed(service, srv) catch unreachable;
}

fn resumeApplication(apt: Applet, service: Applet.Service, srv: ServiceManager) void {
    apt.sendUnlockTransition(service, srv, .unlock_resume) catch unreachable;
    apt.sendSleepIfShellClosed(service, srv) catch unreachable;
}

const Application = @This();
const Applet = horizon.services.Applet;
const GraphicsServerGpu = horizon.services.GraphicsServerGpu;
const Filesystem = horizon.services.Filesystem;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Result = horizon.Result;
const ResultCode = horizon.result.Code;
const Object = horizon.Object;
const Session = horizon.Session.Client;
const Event = horizon.Event;
const Mutex = horizon.Mutex;
const ServiceManager = zitrus.horizon.ServiceManager;
