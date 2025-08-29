//! Applet abstraction to manage and handle Application state
// NOTE: Lots of assumptions are made as there's not a lot of documentation.
// TODO: Do Applications get request's like lib/sys-applets? Wouldn't make sense but still needs research.

pub const Error = @import("Application/Error.zig");
pub const SoftwareKeyboard = @import("Application/SoftwareKeyboard.zig");

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
    must_close: bool = false,

    _: u5 = 0,
};

notification_event: Event,
parameters_event: Event,
chainload: Applet.ChainloadTarget,
flags: State,

pub fn init(apt: Applet, srv: ServiceManager) !Application {
    const attr: Applet.Attributes = .{ .pos = .app, .acquire_gpu = false, .acquire_dsp = false };
    const notification, const parameters = try apt.sendInitialize(srv, environment.program_meta.app_id, attr);

    try apt.sendEnable(srv, attr);

    // We must wait for the wakeup command we get after initializing and enabling ourselves
    {
        try parameters.wait(-1);
        var parameter = try apt.sendReceiveParameter(srv, environment.program_meta.app_id, &.{});
        defer parameter.deinit();

        std.debug.assert(parameter.cmd == .wakeup);
        resumeApplication(apt, srv);
    }

    return .{
        .notification_event = notification,
        .parameters_event = parameters,
        .chainload = if (environment.program_meta.runtime_flags.apt_chainload) .soft_reset else .none,
        .flags = .default,
    };
}

pub fn deinit(app: *Application, apt: Applet, srv: ServiceManager) void {
    const perform_apt_exit = if (app.flags.must_close)
        true
    else if (environment.program_meta.runtime_flags.apt_reinit) ri: {
        apt.sendFinalize(srv, environment.program_meta.app_id) catch unreachable;
        break :ri false;
    } else switch (app.chainload) {
        .none => true,
        else => close: {
            const program_id: u64, const media_type: Filesystem.MediaType, const flags: Applet.command.PrepareToDoApplicationJump.Request.Flags, const parameters: []const u8, const hmac: *const [0x20]u8 = switch (app.chainload) {
                .caller => .{ 0x00, .nand, .use_ns_parameters, &.{}, &@splat(0) },
                .soft_reset => .{ 0x00, .nand, .use_app_id_parameters, &.{}, &@splat(0) },
                else => @panic("TODO: chainload"),
            };

            const man_info = apt.sendGetAppletManInfo(srv, .none) catch unreachable;

            if ((apt.sendIsRegistered(srv, man_info.home_menu) catch false)) {
                apt.sendPrepareToDoApplicationJump(srv, flags, program_id, media_type) catch unreachable;
                apt.sendDoApplicationJump(srv, parameters, hmac) catch unreachable;
            } else {
                apt.sendFinalize(srv, man_info.home_menu) catch unreachable;
                @panic("TODO: 'Dirty' Luma3DS chainloading");
            }

            environment.exit_fn = null;
            break :close false;
        },
    };

    if (perform_apt_exit) {
        apt.sendPrepareToCloseApplication(srv, true) catch {};
        apt.sendCloseApplication(srv, &.{}, .null) catch {};
    }

    app.notification_event.deinit();
    app.parameters_event.deinit();
    app.* = undefined;
}

pub fn setSleepAllowed(app: *Application, apt: Applet, srv: ServiceManager, allow: bool) void {
    const was_allowed = app.flags.allow_sleep;
    app.flags.allow_sleep = allow;

    if (!was_allowed and allow) {
        apt.sendSleepIfShellClosed(srv) catch unreachable;
    } else if (was_allowed and !allow) {
        apt.sendReplySleepQuery(srv, environment.program_meta.app_id, .reject) catch unreachable;
    }
}

pub fn waitNotification(app: *Application, apt: Applet, srv: ServiceManager) !NotificationResult {
    return (try app.waitNotificationTimeout(apt, srv, -1)).?;
}

pub fn pollNotification(app: *Application, apt: Applet, srv: ServiceManager) !?NotificationResult {
    return app.waitNotificationTimeout(apt, srv, 0);
}

pub fn waitNotificationTimeout(app: *Application, apt: Applet, srv: ServiceManager, timeout_ns: i64) !?NotificationResult {
    app.notification_event.wait(timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => return err,
    };

    notif_handling: switch (try apt.sendInquireNotification(srv, environment.program_meta.app_id)) {
        .none => {},
        .home_button_1, .home_button_2 => {
            if (!app.flags.allow_home) {
                clearJumpToHome(apt, srv);
                return .jump_home_rejected;
            } else {
                return .jump_home;
            }
        },
        .sleep_query => try apt.sendReplySleepQuery(srv, environment.program_meta.app_id, if (app.flags.allow_sleep)
            .accept
        else
            .reject),
        .sleep_accepted => {
            // sleep dsp if needed
            try apt.sendReplySleepNotificationComplete(srv, environment.program_meta.app_id);
            return .sleeping;
        },
        .sleep_canceled_by_open => continue :notif_handling .sleep_wakeup,
        .sleep_wakeup => {
            // wakeup dsp
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

fn waitParameterConsumingNotifications(app: *Application, apt: Applet, srv: ServiceManager, parameter: []u8) !Applet.ParameterResult {
    while (true) {
        const is_parameter = try Event.waitMultiple(&.{ app.notification_event, app.parameters_event }, false, -1) == 1;

        if (!is_parameter) {
            switch (try apt.sendInquireNotification(srv, environment.program_meta.app_id)) {
                else => {},
            }

            continue;
        }

        return try apt.sendReceiveParameter(srv, environment.program_meta.app_id, parameter);
    }
}

pub fn waitAppletResult(app: *Application, apt: Applet, srv: ServiceManager, gsp: *GspGpu, parameter: []u8) !AppletResult {
    const parameters = try app.waitParameterConsumingNotifications(apt, srv, parameter);
    switch (parameters.cmd) {
        .wakeup, .request, .response => unreachable, // NOTE: Should only be sent at Application start? + do we get requests? + we're not waiting for a response!
        .wakeup_by_exit, .wakeup_by_cancel, .wakeup_by_cancelall, .wakeup_by_pause, .wakeup_to_jump_home, .wakeup_by_power_button_click => |cmd| {
            defer switch (cmd) {
                .wakeup_to_jump_home, .wakeup_by_power_button_click => apt.sendLockTransition(srv, .jump_home, true) catch unreachable,
                else => {
                    resumeApplication(apt, srv);
                    clearJumpToHome(apt, srv);
                },
            };

            switch (cmd) {
                .wakeup_by_cancel, .wakeup_by_cancelall => app.flags.must_close = true,
                else => {
                    try gsp.acquireRight(0x0);
                    try gsp.sendRestoreVRAMSysArea();
                },
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

// NOTE: we also need to wakeup the dsp if needed when implemented
pub fn jumpToHome(app: *Application, apt: Applet, srv: ServiceManager, gsp: *GspGpu, params: Applet.JumpToHomeParameters) !ExecutionResult {
    const last_allow_sleep = app.flags.allow_sleep;

    app.setSleepAllowed(apt, srv, false);
    defer app.setSleepAllowed(apt, srv, last_allow_sleep);

    try apt.sendPrepareToJumpToHomeMenu(srv);
    try gsp.sendSaveVRAMSysArea();

    const home_app_id = (try apt.sendGetAppletManInfo(srv, .none)).home_menu;
    try app.screenTransfer(apt, srv, gsp, home_app_id, false);

    // Sleep dsp
    try gsp.releaseRight();
    try apt.sendJumpToHomeMenu(srv, params);

    // XXX: Does the home menu return any kind of parameters?
    return switch (try app.waitAppletResult(apt, srv, gsp, &.{})) {
        .execution => |e| switch (e) {
            .jump_home => unreachable, // NOTE: Doesn't make sense, you jump home and wake me up to return to you again? Only makes sense for applets.
            else => e,
        },
        .message => unreachable,
    };
}

pub fn startLibraryApplet(app: *Application, apt: Applet, srv: ServiceManager, gsp: *GspGpu, app_id: Applet.AppId, param_handle: Object, param: []const u8) !void {
    const last_allow_sleep = app.flags.allow_sleep;

    app.setSleepAllowed(apt, srv, false);
    defer app.setSleepAllowed(apt, srv, last_allow_sleep);

    try apt.sendPrepareToStartLibraryApplet(srv, app_id);
    try gsp.sendSaveVRAMSysArea();

    try app.screenTransfer(apt, srv, gsp, app_id, true);

    // Sleep dsp
    try gsp.releaseRight();
    try apt.sendStartLibraryApplet(srv, app_id, param_handle, param);
}

// NOTE: This is just straight up taken from libctru. I didn't know why jumping to home was not working, now I know :p
pub fn screenTransfer(app: *Application, apt: Applet, srv: ServiceManager, gsp: *GspGpu, target_app_id: Applet.AppId, is_library_applet: bool) !void {
    const gsp_capture_info = try gsp.sendImportDisplayCaptureInfo();
    const apt_capture_info = Applet.CaptureBuffer.init(gsp_capture_info);

    while (!(try apt.sendIsRegistered(srv, target_app_id))) {
        // XXX: Maybe this could be adjusted? Currently it follows the same behaviour as libctru
        horizon.sleepThread(1000000);
    }

    try apt.sendSendParameter(srv, environment.program_meta.app_id, target_app_id, if (is_library_applet) .request else .request_for_sys_applet, .null, std.mem.asBytes(&apt_capture_info));

    try app.parameters_event.wait(-1);
    var parameters = try apt.sendReceiveParameter(srv, environment.program_meta.app_id, &.{});
    defer parameters.deinit();

    std.debug.assert(parameters.cmd == .response);

    if (is_library_applet) {
        // TODO: We need to convert the framebuffers to a texture sized 256*Height (we must perform the swizzling ourselves). Could we take advantage of mango?
        // XXX: Do nothing right now (Garbage data will be shown instead)
    }

    try apt.sendSendCaptureBufferInfo(srv, &apt_capture_info);
}

fn clearJumpToHome(apt: Applet, srv: ServiceManager) void {
    apt.sendUnlockTransition(srv, .jump_home) catch unreachable;
    apt.sendSleepIfShellClosed(srv) catch unreachable;
}

fn resumeApplication(apt: Applet, srv: ServiceManager) void {
    apt.sendUnlockTransition(srv, .unlock_resume) catch unreachable;
    apt.sendSleepIfShellClosed(srv) catch unreachable;
}

const Application = @This();
const Applet = horizon.services.Applet;
const GspGpu = horizon.services.GspGpu;
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
const Session = horizon.ClientSession;
const Event = horizon.Event;
const Mutex = horizon.Mutex;
const ServiceManager = zitrus.horizon.ServiceManager;
