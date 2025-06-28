// https://www.3dbrew.org/wiki/NS_and_APT_Services
// TODO: Refactor this (some things could be moved around, etc...)
const service_names = [_][]const u8{ "APT:S", "APT:A", "APT:U" };

pub const Error = Mutex.WaitError || Event.WaitError || Session.RequestError;

pub const AppId = enum(u32) {
    none = 0x00,
    home_menu = 0x101,
    alternate_menu = 0x103,
    camera_applet = 0x110,
    friends_list_applet = 0x112,
    game_notes_applet = 0x113,
    internet_browser = 0x114,
    instruction_manual_applet = 0x115,
    notifications_applet = 0x116,
    miiverse_applet = 0x117,
    miiverse_posting_applet = 0x118,
    amiibo_settings = 0x119,

    shell_software_keyboard = 0x201,
    shell_mii_selector = 0x202,
    shell_photo_selector = 0x204,
    shell_sound_selector = 0x205,
    shell_error_display = 0x206,
    shell_eshop_applet = 0x207,
    shell_circle_pad_pro_calibrator = 0x208,
    shell_notepad = 0x209,

    application = 0x300,
    eshop = 0x301,

    application_software_keyboard = 0x401,
    application_mii_selector = 0x402,
    application_photo_selector = 0x404,
    application_sound_selector = 0x405,
    application_error_display = 0x406,
    application_eshop_applet = 0x407,
    application_circle_pad_pro_calibrator = 0x408,
    application_notepad = 0x409,
};

pub const Position = enum(u3) {
    none = 0b111,
    app = 0,
    app_lib,
    sys,
    sys_lib,
    resident,
};

pub const Attributes = packed struct(u32) {
    pos: Position,
    acquire_gpu: bool,
    acquire_dsp: bool,
    _reserved: u27 = 0,
};

pub const QueryReply = enum(u32) { reject, accept, later };

pub const Notification = enum(u32) {
    none,
    home_button_1,
    home_button_2,
    sleep_query,
    sleep_canceled_by_open,
    sleep_accepted,
    sleep_wakeup,
    shutdown,
    power_button_click,
    power_button_clear,
    try_sleep,
    order_to_close,
    _,
};

pub const Utility = enum(u32) {
    clear_power_button_state,
    unknown0,
    set_current_apt_to_home,
    clear_exclusive_control,
    sleep_if_shell_closed,
    lock_transition,
    try_lock_transition,
    unlock_transition,
    start_exit_task = 10,
    set_initial_sender_id,
    set_power_button_click,
    unlock_cart_and_sd_slot = 16,
    unknown1,
    unknown2,
};

pub const AppCommand = enum(u32) {
    none,
    wakeup,
    request,
    response,
    exit,
    message,
    home_button_single,
    home_button_double,
    dsp_sleep,
    dsp_wakeup,
    wakeup_by_exit,
    wakeup_by_pause,
    wakeup_by_cancel,
    wakeup_by_cancelall,
    wakeup_by_power_button_click,
    wakeup_to_jump_home,
    request_for_sys_applet,
    wakeup_to_launch_application,
    unknown_home_menu_boot = 0x41,
};

pub const Transition = enum(u32) {
    jump_home = 0x01,
    unlock_resume = 0x10,
};

pub const CaptureBuffer = extern struct {
    pub const Info = extern struct { left_offset: usize, right_offset: usize, color_format: u32 };

    size: usize,
    enabled_3d: bool,
    _reserved0: [3]u8 = @splat(0),
    top: Info,
    bottom: Info,

    // TODO: Finish this
    pub inline fn init(capture: GspGpu.ScreenCapture) CaptureBuffer {
        return CaptureBuffer{
            .size = 0,
            .enabled_3d = capture.top.format.mode() == .@"3d",
            .top = Info{
                .left_offset = 0,
                .right_offset = 0,
                .color_format = @intFromEnum(capture.top.format.color_format),
            },
            .bottom = Info{
                // XXX: These values work? Why? They've been tested with Bgr8 (24bpp tf?)
                .left_offset = 400 * 240 * 4,
                .right_offset = 0,
                .color_format = @intFromEnum(capture.bottom.format.color_format),
            },
        };
    }
};

pub const TransitionState = enum {
    active,
    enable,
    jump_to_menu,
    sys_applet,
    lib_applet,
    cancel_lib,
    close_app,
    app_jump,
};

pub const EventResult = union(enum) {
    success,
    request,
    request_for_sys_applet,
    response,
    message,

    /// Internal, should be unreachable to user code
    transition_completed: AppCommand,
    sleep_wakeup,
};

pub const Flags = packed struct(u8) {
    pub const default = Flags{ .allow_home = true, .allow_sleep = true };
    pub const safe = Flags{ .allow_home = false, .allow_sleep = true };

    allow_home: bool = false,
    allow_sleep: bool = false,

    sleeping: bool = false,
    power_requested: bool = false,

    should_close: bool = false,

    _: u3 = 0,
};

pub const ChainloadTarget = union(enum) {
    pub const Application = struct {
        program_id: u64,
        media_type: Filesystem.MediaType,
        arguments: []const u8,
        hmac: ?*const [0x20]u8,
    };

    none,
    caller,
    soft_reset,
    application: Application,
};

lock: Mutex,
available_service_name: []const u8,
events: ?[2]Event = null,
current_transition: TransitionState,
flags: Flags,
chainload: ChainloadTarget = .none,

pub fn init(srv: ServiceManager) !Applet {
    var last_error: anyerror = undefined;
    const available_service_name, var available_service: Session = used: for (service_names) |service_name| {
        const service_handle = srv.sendGetServiceHandle(service_name, true) catch |err| {
            last_error = err;
            continue;
        };

        break :used .{ service_name, service_handle };
    } else return last_error;

    const data = tls.getThreadLocalStorage();

    var lock: Mutex = lock: {
        defer available_service.deinit();

        data.ipc.fillCommand(Command.get_lock_handle, .{@as(u32, 0x0)}, .{});
        try available_service.sendRequest();

        break :lock @bitCast(data.ipc.parameters[4]);
    };

    errdefer lock.deinit();

    var apt = Applet{
        .lock = lock,
        .available_service_name = available_service_name,
        .current_transition = .active,
        // TODO: Handle safe firm (just an if)
        .flags = .default,
    };

    const attr = Applet.Attributes{ .pos = .app, .acquire_gpu = false, .acquire_dsp = false };
    apt.events = try apt.sendInitialize(srv, environment.program_meta.app_id, attr);

    try apt.sendEnable(srv, attr);
    apt.chainload = if (environment.program_meta.runtime_flags.apt_chainload) .soft_reset else .none;

    // XXX: Here we don't need the gsp to wakeup
    _ = try apt.waitForWakeup(srv, .enable, null);
    return apt;
}

pub fn deinit(apt: *Applet, srv: ServiceManager) void {
    const perform_apt_exit = if (apt.flags.should_close)
        true
    else if (environment.program_meta.runtime_flags.apt_reinit) ri: {
        apt.sendFinalize(srv, environment.program_meta.app_id) catch unreachable;
        break :ri false;
    } else switch (apt.chainload) {
        .none => true,
        else => close: {
            const program_id: u64, const media_type: Filesystem.MediaType, const flags: ApplicationJumpFlags, const parameters: []const u8, const hmac: *const [0x20]u8 = switch (apt.chainload) {
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
        apt.sendCloseApplication(srv, &.{}, null) catch {};
    }

    apt.lock.deinit();

    var events = apt.events.?;
    inline for (&events) |*ev| {
        ev.deinit();
    }

    apt.* = undefined;
}

pub fn waitEvent(apt: *Applet, srv: ServiceManager, gsp: ?*GspGpu) Error!EventResult {
    return (try apt.waitEventTimeout(srv, -1, gsp)).?;
}

pub fn pollEvent(apt: *Applet, srv: ServiceManager, gsp: ?*GspGpu) Error!?EventResult {
    return apt.waitEventTimeout(srv, 0, gsp);
}

pub fn waitEventTimeout(apt: *Applet, srv: ServiceManager, timeout_ns: i64, gsp: ?*GspGpu) Error!?EventResult {
    const events = apt.events.?;

    const id = Event.waitMultiple(&events, false, timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => return err,
    };

    switch (id) {
        0 => {
            notif_handling: switch (try apt.sendInquireNotification(srv, environment.program_meta.app_id)) {
                .none => {},
                .home_button_1, .home_button_2 => {
                    if (apt.current_transition != .active) {
                        break :notif_handling;
                    } else if (!apt.flags.allow_home) {
                        try apt.clearJumpToHome(srv);
                    } else {
                        try apt.jumpToHome(srv, gsp.?, .none);
                    }
                },
                .sleep_query => {
                    const reply: QueryReply = if (apt.current_transition != .active or apt.flags.allow_sleep)
                        .accept
                    else
                        .reject;

                    try apt.sendReplySleepQuery(srv, environment.program_meta.app_id, reply);
                },
                .sleep_accepted => {
                    // sleep dsp if needed
                    try apt.acceptSleep(srv, gsp.?.*);
                },
                .sleep_canceled_by_open => continue :notif_handling .sleep_wakeup,
                .sleep_wakeup => {
                    // wakeup dsp
                    if (apt.current_transition != .active) {
                        break :notif_handling;
                    }

                    if (apt.flags.sleeping) {
                        return .sleep_wakeup;
                    }
                },
                .shutdown => try apt.jumpToHome(srv, gsp.?, .none),
                .power_button_click => try apt.jumpToHome(srv, gsp.?, .none),
                .power_button_clear => {},
                .try_sleep => {},
                .order_to_close => apt.flags.should_close = true,
                else => {},
            }
        },
        1 => {
            const params = try apt.sendGlanceParameter(srv, environment.program_meta.app_id, &.{});
            defer params.deinit();

            const cmd = params.command;

            sw: switch (cmd) {
                .dsp_sleep => {},
                .dsp_wakeup => {},
                .wakeup_by_pause => {
                    // Handle hax 2.0 spurious wakeup
                    continue :sw .wakeup;
                },
                .wakeup, .wakeup_by_exit, .wakeup_by_cancel, .wakeup_by_cancelall, .wakeup_by_power_button_click, .wakeup_to_jump_home, .wakeup_to_launch_application => {
                    const handling_transition = apt.current_transition;
                    apt.current_transition = .active;

                    // XXX: How?
                    if (handling_transition == .active) {
                        unreachable;
                    }

                    _ = try apt.sendCancelParameter(srv, .none, environment.program_meta.app_id);

                    // This only if its not cancel_lib
                    if (handling_transition != .cancel_lib and cmd != .wakeup and cmd != .wakeup_by_cancel) {
                        // NOTE: Give a name to these flags, investigate/debug in the future
                        const valid_gsp = gsp.?;

                        try valid_gsp.acquireRight(0);
                        try valid_gsp.sendRestoreVRAMSysArea();
                    }

                    switch (cmd) {
                        .wakeup_by_cancel, .wakeup_by_cancelall => {
                            // dsp cancel/sleep

                            if (cmd == .wakeup_by_cancel) {
                                apt.flags.should_close = true;
                            }
                        },
                        else => |v| if (v != .wakeup_to_launch_application) {
                            // dsp wakeup
                        },
                    }

                    if (cmd != .wakeup_to_jump_home) {
                        try apt.sendUnlockTransition(srv, .unlock_resume);
                        try apt.sendSleepIfShellClosed(srv);

                        switch (handling_transition) {
                            .jump_to_menu, .lib_applet, .sys_applet, .app_jump => try apt.clearJumpToHome(srv),
                            else => {},
                        }
                    } else {
                        try apt.sendLockTransition(srv, .jump_home, true);
                        try apt.jumpToHome(srv, gsp.?, .none);
                    }

                    return .{ .transition_completed = cmd };
                },
                .request => return .request,
                .request_for_sys_applet => return .request_for_sys_applet,
                .response => return .response,
                .message => return .message,
                else => unreachable,
            }
        },
        else => unreachable,
    }

    return .success;
}

pub fn waitForWakeup(apt: *Applet, srv: ServiceManager, transition: TransitionState, gsp: ?*GspGpu) Error!void {
    std.debug.assert(transition != .active);

    try apt.sendNotifyToWait(srv, environment.program_meta.app_id);
    apt.current_transition = transition;

    if (transition != .enable) {
        try apt.sendSleepIfShellClosed(srv);
    }

    while (true) switch (try apt.waitEvent(srv, gsp)) {
        .transition_completed => |_| return,
        else => {},
    };
}

pub fn jumpToHome(apt: *Applet, srv: ServiceManager, gsp: *GspGpu, params: JumpToHomeParameters) Error!void {
    const last_allow_sleep = apt.flags.allow_sleep;

    try apt.setSleepAllowed(srv, false);
    try apt.sendPrepareToJumpToHomeMenu(srv);

    try gsp.sendSaveVRAMSysArea();

    const home_app_id = (try apt.sendGetAppletManInfo(srv, .none)).home_menu;
    try apt.screenTransfer(srv, gsp, home_app_id, false);

    // Sleep dsp
    try gsp.releaseRight();
    try apt.sendJumpToHomeMenu(srv, params);

    _ = try apt.waitForWakeup(srv, .jump_to_menu, gsp);
    try apt.setSleepAllowed(srv, last_allow_sleep);
}

pub fn acceptSleep(apt: *Applet, srv: ServiceManager, gsp: GspGpu) Error!void {
    apt.sendReplySleepNotificationComplete(srv, environment.program_meta.app_id) catch unreachable;

    // We're already waiting, we'll eventually wake up
    if (apt.current_transition != .active) {
        return;
    }

    apt.flags.sleeping = true;
    while (true) switch (try apt.waitEvent(srv, null)) {
        .sleep_wakeup => break,
        else => {},
    };

    try gsp.sendSetLcdForceBlack(false);
}

pub fn setSleepAllowed(apt: *Applet, srv: ServiceManager, allow: bool) Error!void {
    const was_allowed = apt.flags.allow_sleep;
    apt.flags.allow_sleep = allow;

    if (!was_allowed and allow) {
        try apt.sendSleepIfShellClosed(srv);
    } else if (was_allowed and !allow) {
        try apt.sendReplySleepQuery(srv, environment.program_meta.app_id, .reject);
    }
}

pub fn clearJumpToHome(apt: Applet, srv: ServiceManager) Error!void {
    try apt.sendUnlockTransition(srv, .jump_home);
    try apt.sendSleepIfShellClosed(srv);
}

// NOTE: This is just straight up taken from libctru. I didn't know why jumping to home was not working, now I know :p
pub fn screenTransfer(apt: *Applet, srv: ServiceManager, gsp: *GspGpu, target_app_id: AppId, is_library_applet: bool) Error!void {
    const gsp_capture_info = try gsp.sendImportDisplayCaptureInfo();
    const apt_capture_info = CaptureBuffer.init(gsp_capture_info);

    while (!(try apt.sendIsRegistered(srv, target_app_id))) {
        // XXX: Maybe this could be adjusted? Currently it follows the same behaviour as libctru
        horizon.sleepThread(10000000);
    }

    try apt.sendSendParameter(srv, environment.program_meta.app_id, target_app_id, if (is_library_applet) .request else .request_for_sys_applet, null, std.mem.asBytes(&apt_capture_info));

    // NOTE: Recursion here!
    const capture_memory_handle = capture_handle_wait: while (true) switch (try apt.waitEvent(srv, gsp)) {
        .response => {
            var handle: ?*Handle = null;
            const params = try apt.sendReceiveParameter(srv, environment.program_meta.app_id, std.mem.asBytes(&handle));
            defer params.deinit();

            break :capture_handle_wait handle;
        },
        else => unreachable,
    } else unreachable;
    defer if (capture_memory_handle) |cap_handle| {
        _ = horizon.closeHandle(cap_handle);
    };

    if (is_library_applet) {
        // TODO: Do the conversion ourselves
    }

    try apt.sendSendCaptureBufferInfo(srv, &apt_capture_info);
}

pub fn sendInitialize(apt: Applet, srv: ServiceManager, app_id: AppId, attr: Attributes) Error![2]Event {
    try apt.lockSendCommand(srv, Command.initialize, .{ app_id, attr }, .{}, null);

    const data = tls.getThreadLocalStorage();
    // NOTE: notification, resume
    return .{ @bitCast(data.ipc.parameters[2]), @bitCast(data.ipc.parameters[3]) };
}

pub fn sendEnable(apt: Applet, srv: ServiceManager, attr: Attributes) Error!void {
    return try apt.lockSendCommand(srv, Command.enable, .{attr}, .{}, null);
}

pub fn sendFinalize(apt: Applet, srv: ServiceManager, app_id: AppId) !void {
    return apt.lockSendCommand(srv, Command.finalize, .{app_id}, .{}, null);
}

pub const ManagerInfo = struct {
    position: Position,
    requested: AppId,
    home_menu: AppId,
    current: AppId,
};

pub fn sendGetAppletManInfo(apt: Applet, srv: ServiceManager, position: Position) !ManagerInfo {
    try apt.lockSendCommand(srv, Command.get_applet_man_info, .{@as(u32, @intFromEnum(position))}, .{}, null);

    const data = tls.getThreadLocalStorage();
    return ManagerInfo{
        .position = @enumFromInt(data.ipc.parameters[1]),
        .requested = @enumFromInt(data.ipc.parameters[2]),
        .home_menu = @enumFromInt(data.ipc.parameters[3]),
        .current = @enumFromInt(data.ipc.parameters[4]),
    };
}

pub fn sendIsRegistered(apt: Applet, srv: ServiceManager, app_id: AppId) !bool {
    try apt.lockSendCommand(srv, Command.is_registered, .{app_id}, .{}, null);

    const data = tls.getThreadLocalStorage();
    return data.ipc.parameters[1] != 0;
}

pub fn sendInquireNotification(apt: Applet, srv: ServiceManager, app_id: AppId) !Notification {
    try apt.lockSendCommand(srv, Command.inquire_notification, .{app_id}, .{}, null);

    const data = tls.getThreadLocalStorage();
    return @as(Notification, @enumFromInt(data.ipc.parameters[1]));
}

pub fn sendSendParameter(apt: Applet, srv: ServiceManager, src: AppId, dst: AppId, cmd: AppCommand, handle: ?*Handle, parameter: []const u8) !void {
    try apt.lockSendCommand(srv, Command.send_parameter, .{ @intFromEnum(src), @intFromEnum(dst), @intFromEnum(cmd), parameter.len }, .{ ipc.HandleTranslationDescriptor.init(0), (if (handle) |h| @intFromPtr(h) else 0), ipc.StaticBufferTranslationDescriptor.init(parameter.len, 0), @intFromPtr(parameter.ptr) }, null);
}

pub const ParameterResult = struct {
    sender: AppId,
    command: AppCommand,
    actual_size: usize,
    parameter: ?*Handle,

    pub fn deinit(result: ParameterResult) void {
        if (result.parameter) |handle| {
            _ = horizon.closeHandle(handle);
        }
    }
};

fn sendQueryParameter(apt: Applet, comptime cmd: Command, srv: ServiceManager, app_id: AppId, parameter: []u8) !ParameterResult {
    try apt.lockSendCommand(srv, cmd, .{ app_id, parameter.len }, .{}, &.{ @bitCast(ipc.StaticBufferTranslationDescriptor.init(parameter.len, 0)), @intFromPtr(parameter.ptr) });

    const data = tls.getThreadLocalStorage();
    return ParameterResult{
        .sender = @enumFromInt(data.ipc.parameters[1]),
        .command = @enumFromInt(data.ipc.parameters[2]),
        .actual_size = data.ipc.parameters[3],
        .parameter = if (data.ipc.parameters[5] == 0) null else @ptrFromInt(data.ipc.parameters[5]),
    };
}

pub fn sendReceiveParameter(apt: Applet, srv: ServiceManager, app_id: AppId, parameter: []u8) !ParameterResult {
    return apt.sendQueryParameter(.receive_parameter, srv, app_id, parameter);
}

pub fn sendGlanceParameter(apt: Applet, srv: ServiceManager, app_id: AppId, parameter: []u8) !ParameterResult {
    return apt.sendQueryParameter(.glance_parameter, srv, app_id, parameter);
}

pub fn sendCancelParameter(apt: Applet, srv: ServiceManager, src: AppId, dst: AppId) !bool {
    try apt.lockSendCommand(srv, Command.cancel_parameter, .{}, .{ @as(u32, @intFromBool(src != .none)), src, @as(u32, @intFromBool(dst != .none)), dst }, null);

    const data = tls.getThreadLocalStorage();
    return data.ipc.parameters[1] != 0;
}

pub fn sendPrepareToCloseApplication(apt: Applet, srv: ServiceManager, cancel: bool) !void {
    return apt.lockSendCommand(srv, Command.prepare_to_close_application, .{@as(u32, @intFromBool(cancel))}, .{}, null);
}

pub fn sendCloseApplication(apt: Applet, srv: ServiceManager, parameters: []const u8, handle: ?*Handle) !void {
    return apt.lockSendCommand(srv, Command.close_application, .{parameters.len}, .{ ipc.HandleTranslationDescriptor.init(0), if (handle) |h| @intFromPtr(h) else 0, ipc.StaticBufferTranslationDescriptor.init(parameters.len, 0), @intFromPtr(parameters.ptr) }, null);
}

pub fn sendPrepareToJumpToHomeMenu(apt: Applet, srv: ServiceManager) !void {
    return apt.lockSendCommand(srv, Command.prepare_to_jump_to_home_menu, .{}, .{}, null);
}

pub const JumpToHomeCommand = enum(u8) {
    none,
    open_manual,
    download_theme,
    open_badge_picker,
};

pub const JumpToHomeParameters = union(JumpToHomeCommand) {
    none,
    open_manual,
    download_theme,
    open_badge_picker,
};

pub fn sendJumpToHomeMenu(apt: Applet, srv: ServiceManager, params: JumpToHomeParameters) Error!void {
    const parameters: []const u8 = &(switch (params) {
        .download_theme => |theme| .{ 'A', 'S', 'H', 'P', @intFromEnum(JumpToHomeCommand.download_theme), 0x00, 0x00, 0x00 } ++ std.mem.asBytes(&theme).*,
        else => .{ 'A', 'S', 'H', 'P', @intFromEnum(params) },
    });

    return apt.lockSendCommand(srv, Command.jump_to_home_menu, .{parameters.len}, .{ ipc.HandleTranslationDescriptor.init(0), @as(usize, 0x00), ipc.StaticBufferTranslationDescriptor.init(parameters.len, 0), @intFromPtr(parameters.ptr) }, null);
}

pub const ApplicationJumpFlags = enum(u8) {
    use_input_parameters,
    use_ns_parameters,
    use_app_id_parameters,
};

pub fn sendPrepareToDoApplicationJump(apt: Applet, srv: ServiceManager, flags: ApplicationJumpFlags, program_id: u64, media_type: Filesystem.MediaType) !void {
    return apt.lockSendCommand(srv, Command.prepare_to_do_application_jump, .{ @as(u32, @intFromEnum(flags)), @as(u32, @truncate(program_id)), @as(u32, @intCast(program_id >> 32)), @as(u32, @intFromEnum(media_type)) }, .{}, null);
}

pub fn sendDoApplicationJump(apt: Applet, srv: ServiceManager, parameters: []const u8, hmac: *const [0x20]u8) Error!void {
    return apt.lockSendCommand(srv, Command.do_application_jump, .{ parameters.len, hmac.len }, .{ ipc.StaticBufferTranslationDescriptor.init(parameters.len, 0), @intFromPtr(parameters.ptr), ipc.StaticBufferTranslationDescriptor.init(hmac.len, 2), @intFromPtr(hmac) }, null);
}

pub fn sendDspSleep(apt: Applet, srv: ServiceManager, app_id: AppId, handle: *Handle) Error!void {
    return apt.lockSendCommand(srv, Command.send_dsp_sleep, .{app_id}, .{ ipc.StaticBufferTranslationDescriptor.init(0), @intFromPtr(handle) }, null);
}

pub fn sendDspWakeup(apt: Applet, srv: ServiceManager, app_id: AppId, handle: *Handle) Error!void {
    return apt.lockSendCommand(srv, Command.send_dsp_wake_up, .{app_id}, .{ ipc.StaticBufferTranslationDescriptor.init(0), @intFromPtr(handle) }, null);
}

pub fn sendReplySleepQuery(apt: Applet, srv: ServiceManager, app_id: AppId, reply: QueryReply) Error!void {
    return apt.lockSendCommand(srv, Command.reply_sleep_query, .{ app_id, reply }, .{}, null);
}

pub fn sendReplySleepNotificationComplete(apt: Applet, srv: ServiceManager, app_id: AppId) Error!void {
    return apt.lockSendCommand(srv, Command.reply_sleep_notification_complete, .{app_id}, .{}, null);
}

pub fn sendSendCaptureBufferInfo(apt: Applet, srv: ServiceManager, info: *const CaptureBuffer) Error!void {
    return apt.lockSendCommand(srv, Command.send_capture_buffer_info, .{@as(usize, @sizeOf(CaptureBuffer))}, .{ ipc.StaticBufferTranslationDescriptor.init(@sizeOf(CaptureBuffer), 0), @intFromPtr(info) }, null);
}

pub fn sendNotifyToWait(apt: Applet, srv: ServiceManager, app_id: AppId) Error!void {
    return apt.lockSendCommand(srv, Command.notify_to_wait, .{app_id}, .{}, null);
}

pub fn sendAppletUtility(apt: Applet, srv: ServiceManager, utility: Utility, input: []const u8, output: []u8) Error!void {
    try apt.lockSendCommand(srv, Command.applet_utility, .{ utility, input.len, output.len }, .{ ipc.StaticBufferTranslationDescriptor.init(input.len, 1), @intFromPtr(input.ptr) }, &.{ @bitCast(ipc.StaticBufferTranslationDescriptor.init(output.len, 0)), @intFromPtr(output.ptr) });
}

pub fn sendSleepIfShellClosed(apt: Applet, srv: ServiceManager) Error!void {
    return apt.sendAppletUtility(srv, .sleep_if_shell_closed, &.{}, &.{});
}

pub fn sendLockTransition(apt: Applet, srv: ServiceManager, transition: Transition, flag: bool) Error!void {
    const transition_data: extern struct { transition: Transition, flag: bool, pad: [3]u8 = @splat(0) } = .{ .transition = transition, .flag = flag };
    return apt.sendAppletUtility(srv, .lock_transition, std.mem.asBytes(&transition_data), &.{});
}

pub fn sendTryLockTransition(apt: Applet, srv: ServiceManager, transition: Transition) Error!bool {
    var success: bool = undefined;
    try apt.sendAppletUtility(srv, .try_lock_transition, std.mem.asBytes(&transition), std.mem.asBytes(&success));
    return success;
}

pub fn sendUnlockTransition(apt: Applet, srv: ServiceManager, transition: Transition) Error!void {
    return apt.sendAppletUtility(srv, .unlock_transition, std.mem.asBytes(&transition), &.{});
}

pub fn lockSendCommand(apt: Applet, srv: ServiceManager, comptime cmd: Command, normal: anytype, translate: anytype, static_buffers: ?[]const u32) Error!void {
    try apt.lock.wait(-1);
    defer apt.lock.release();

    var fresh_session = try srv.sendGetServiceHandle(apt.available_service_name, true);
    defer fresh_session.deinit();

    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(cmd, normal, translate);
    if (static_buffers) |buffers| {
        std.debug.assert(buffers.len < data.ipc_static_buffers.len);
        @memcpy(data.ipc_static_buffers[0..buffers.len], buffers);
    }

    try fresh_session.sendRequest();
}

// TODO: Finish this, some currently unused commands may not be accurate
pub const Command = enum(u16) {
    get_lock_handle = 0x0001,
    initialize,
    enable,
    finalize,
    get_applet_man_info,
    get_applet_info,
    get_last_signaled_applet_id,
    count_registered_applet,
    is_registered,
    get_attribute,
    inquire_notification,
    send_parameter,
    receive_parameter,
    glance_parameter,
    cancel_parameter,
    debug_func,
    map_program_id_for_debug,
    set_home_menu_applet_id_for_debug,
    get_preparation_state,
    set_preparation_state,
    prepare_to_start_application,
    preload_library_applet,
    finish_preloading_library_applet,
    prepare_to_start_library_applet,
    prepare_to_start_system_applet,
    prepare_to_start_newest_home_menu,
    start_application,
    wakeup_application,
    cancel_application,
    start_library_applet,
    start_system_applet,
    start_newest_home_menu,
    order_to_close_application,
    prepare_to_close_application,
    prepare_to_jump_to_application,
    jump_to_application,
    prepare_to_close_library_applet,
    prepare_to_close_system_applet,
    close_application,
    close_library_applet,
    close_system_applet,
    order_to_close_system_applet,
    prepare_to_jump_to_home_menu,
    jump_to_home_menu,
    prepare_to_leave_home_menu,
    leave_home_menu,
    prepare_to_leave_resident_applet,
    leave_resident_applet,
    prepare_to_do_application_jump,
    do_application_jump,
    get_program_id_on_application_jump,
    send_deliver_arg,
    receive_deliver_arg,
    load_sys_menu_arg,
    store_sys_menu_arg,
    preload_resident_applet,
    prepare_to_start_resident_applet,
    start_resident_applet,
    cancel_library_applet,
    send_dsp_sleep,
    send_dsp_wake_up,
    reply_sleep_query,
    reply_sleep_notification_complete,
    send_capture_buffer_info,
    receive_capture_buffer_info,
    sleep_system,
    notify_to_wait,
    get_shared_font,
    get_wireless_reboot_info,
    wrap,
    unwrap,
    get_program_info,
    reboot,
    get_capture_info,
    applet_utility,
    set_fatal_err_disp_mode,
    get_applet_program_info,
    hardware_reset_async,
    set_application_cpu_time_limit,
    get_application_cpu_time_limit,
    get_startup_argument,
    wrap1,
    unwrap1,
    unknown_0054,
    set_screen_capture_post_permission,
    get_screen_capture_post_permission,
    wakeup_application2,
    get_program_id = 0x0058,
    get_target_platform = 0x0101,
    check_new_3ds,
    get_application_running_mode,
    is_standard_memory_layout,
    is_title_allowed,

    pub inline fn normalParameters(cmd: Command) u6 {
        return switch (cmd) {
            .get_lock_handle => 1,
            .initialize => 2,
            .enable => 1,
            .finalize => 1,
            .get_applet_man_info => 1,
            .get_applet_info => 1,
            .get_last_signaled_applet_id => 0,
            .count_registered_applet => 0,
            .is_registered => 1,
            .get_attribute => 1,
            .inquire_notification => 1,
            .send_parameter => 4,
            .receive_parameter => 2,
            .glance_parameter => 2,
            .cancel_parameter => 0,
            .debug_func => 3,
            .map_program_id_for_debug => 3,
            .set_home_menu_applet_id_for_debug => 1,
            .get_preparation_state => 0,
            .set_preparation_state => 1,
            .prepare_to_start_application => 5,
            .preload_library_applet => 1,
            .finish_preloading_library_applet => 1,
            .prepare_to_start_library_applet => 1,
            .prepare_to_start_system_applet => 1,
            .prepare_to_start_newest_home_menu => 0,
            .start_application => 5,
            .wakeup_application => 0,
            .cancel_application => 0,
            .start_library_applet => 3,
            .start_system_applet => 3,
            .start_newest_home_menu => 1,
            .order_to_close_application => 0,
            .prepare_to_close_application => 1,
            .prepare_to_jump_to_application => 1,
            .jump_to_application => 1,
            .prepare_to_close_library_applet => 3,
            .prepare_to_close_system_applet => 0,
            .close_application => 1,
            .close_library_applet => 1,
            .close_system_applet => 1,
            .order_to_close_system_applet => 0,
            .prepare_to_jump_to_home_menu => 0,
            .jump_to_home_menu => 1,
            .prepare_to_leave_home_menu => 0,
            .leave_home_menu => 1,
            .prepare_to_leave_resident_applet => 1,
            .leave_resident_applet => 1,
            .prepare_to_do_application_jump => 4,
            .do_application_jump => 2,
            .get_program_id_on_application_jump => 0,
            .send_deliver_arg => 2,
            .receive_deliver_arg => 2,
            .load_sys_menu_arg => 1,
            .store_sys_menu_arg => 1,
            .preload_resident_applet => 1,
            .prepare_to_start_resident_applet => 1,
            .start_resident_applet => 1,
            .cancel_library_applet => 1,
            .send_dsp_sleep => 1,
            .send_dsp_wake_up => 1,
            .reply_sleep_query => 2,
            .reply_sleep_notification_complete => 1,
            .send_capture_buffer_info => 1,
            .receive_capture_buffer_info => 1,
            .sleep_system => 2,
            .notify_to_wait => 1,
            .get_shared_font => 0,
            .get_wireless_reboot_info => 1,
            .wrap => 4,
            .unwrap => 4,
            .get_program_info => 1,
            .reboot => 6,
            .get_capture_info => 1,
            .applet_utility => 3,
            .set_fatal_err_disp_mode => 0,
            .get_applet_program_info => 1,
            .hardware_reset_async => 0,
            .set_application_cpu_time_limit => 2,
            .get_application_cpu_time_limit => 1,
            .get_startup_argument => 2,
            .wrap1 => 4,
            .unwrap1 => 4,
            .unknown_0054 => 1,
            .set_screen_capture_post_permission => 1,
            .get_screen_capture_post_permission => 0,
            .wakeup_application2 => 1,
            .get_program_id => 2,
            .get_target_platform => 0,
            .check_new_3ds => 0,
            .get_application_running_mode => 0,
            .is_standard_memory_layout => 0,
            .is_title_allowed => 1,
        };
    }

    pub inline fn translateParameters(cmd: Command) u6 {
        return switch (cmd) {
            .get_lock_handle => 0,
            .initialize => 0,
            .enable => 0,
            .finalize => 0,
            .get_applet_man_info => 0,
            .get_applet_info => 0,
            .get_last_signaled_applet_id => 0,
            .count_registered_applet => 0,
            .is_registered => 0,
            .get_attribute => 0,
            .inquire_notification => 0,
            .send_parameter => 4,
            .receive_parameter => 0,
            .glance_parameter => 0,
            .cancel_parameter => 4,
            .debug_func => 2,
            .map_program_id_for_debug => 0,
            .set_home_menu_applet_id_for_debug => 0,
            .get_preparation_state => 0,
            .set_preparation_state => 0,
            .prepare_to_start_application => 1,
            .preload_library_applet => 0,
            .finish_preloading_library_applet => 0,
            .prepare_to_start_library_applet => 0,
            .prepare_to_start_system_applet => 0,
            .prepare_to_start_newest_home_menu => 0,
            .start_application => 1,
            .wakeup_application => 0,
            .cancel_application => 0,
            .start_library_applet => 2,
            .start_system_applet => 2,
            .start_newest_home_menu => 1,
            .order_to_close_application => 0,
            .prepare_to_close_application => 0,
            .prepare_to_jump_to_application => 0,
            .jump_to_application => 1,
            .prepare_to_close_library_applet => 0,
            .prepare_to_close_system_applet => 0,
            .close_application => 4,
            .close_library_applet => 0,
            .close_system_applet => 0,
            .order_to_close_system_applet => 0,
            .prepare_to_jump_to_home_menu => 0,
            .jump_to_home_menu => 4,
            .prepare_to_leave_home_menu => 0,
            .leave_home_menu => 1,
            .prepare_to_leave_resident_applet => 0,
            .leave_resident_applet => 0,
            .prepare_to_do_application_jump => 0,
            .do_application_jump => 4,
            .get_program_id_on_application_jump => 0,
            .send_deliver_arg => 0,
            .receive_deliver_arg => 0,
            .load_sys_menu_arg => 0,
            .store_sys_menu_arg => 2,
            .preload_resident_applet => 0,
            .prepare_to_start_resident_applet => 0,
            .start_resident_applet => 0,
            .cancel_library_applet => 0,
            .send_dsp_sleep => 1,
            .send_dsp_wake_up => 1,
            .reply_sleep_query => 0,
            .reply_sleep_notification_complete => 0,
            .send_capture_buffer_info => 2,
            .receive_capture_buffer_info => 0,
            .sleep_system => 0,
            .notify_to_wait => 0,
            .get_shared_font => 0,
            .get_wireless_reboot_info => 0,
            .wrap => 1,
            .unwrap => 1,
            .get_program_info => 0,
            .reboot => 3,
            .get_capture_info => 0,
            .applet_utility => 2,
            .set_fatal_err_disp_mode => 0,
            .get_applet_program_info => 0,
            .hardware_reset_async => 0,
            .set_application_cpu_time_limit => 2,
            .get_application_cpu_time_limit => 0,
            .get_startup_argument => 0,
            .wrap1 => 1,
            .unwrap1 => 1,
            .unknown_0054 => 0,
            .set_screen_capture_post_permission => 0,
            .get_screen_capture_post_permission => 0,
            .wakeup_application2 => 1,
            .get_program_id => 0,
            .get_target_platform => 0,
            .check_new_3ds => 0,
            .get_application_running_mode => 0,
            .is_standard_memory_layout => 0,
            .is_title_allowed => 1,
        };
    }
};

const Applet = @This();
const GspGpu = horizon.services.GspGpu;
const Filesystem = horizon.services.Filesystem;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.ResultCode;
const Handle = horizon.Handle;
const Session = horizon.Session;
const Event = horizon.Event;
const Mutex = horizon.Mutex;
const ServiceManager = zitrus.horizon.ServiceManager;
