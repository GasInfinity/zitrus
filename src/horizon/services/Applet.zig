// https://www.3dbrew.org/wiki/NS_and_APT_Services
// TODO: Refactor this (some things could be moved around, etc...)
const service_names = [_][]const u8{ "APT:S", "APT:A", "APT:U" };

// TODO: Refactor APT to make it not recursive
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

pub const Command = enum(u32) {
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
    transition_completed: Command,
    sleep_wakeup,
};

pub const State = packed struct(u8) {
    pub const default: State = .{ .allow_home = true, .allow_sleep = true };
    pub const safe: State = .{ .allow_home = false, .allow_sleep = true };

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
flags: State,
chainload: ChainloadTarget = .none,

pub fn init(srv: ServiceManager) !Applet {
    var last_error: anyerror = undefined;
    const available_service_name, var available_service: Session = used: for (service_names) |service_name| {
        const service_handle = srv.sendGetServiceHandle(service_name, .wait) catch |err| {
            last_error = err;
            continue;
        };

        break :used .{ service_name, service_handle };
    } else return last_error;

    const data = tls.getThreadLocalStorage();

    var lock: Mutex = lock: {
        defer available_service.deinit();

        break :lock switch (try data.ipc.sendRequest(available_service, command.GetLockHandle, .{ .flags = 0x0 }, .{})) {
            .success => |s| s.value.response.lock,
            .failure => |code| return horizon.unexpectedResult(code),
        };
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
            const program_id: u64, const media_type: Filesystem.MediaType, const flags: command.PrepareToDoApplicationJump.Request.Flags, const parameters: []const u8, const hmac: *const [0x20]u8 = switch (apt.chainload) {
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
            defer if (params.parameter_handle != .null) {
                _ = horizon.closeHandle(params.parameter_handle);
            };

            const cmd = params.cmd;

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

    try apt.sendSendParameter(srv, environment.program_meta.app_id, target_app_id, if (is_library_applet) .request else .request_for_sys_applet, .null, std.mem.asBytes(&apt_capture_info));

    // NOTE: Recursion here!
    const capture_memory_handle = capture_handle_wait: while (true) switch (try apt.waitEvent(srv, gsp)) {
        .response => {
            var handle: Object = .null;
            const params = try apt.sendReceiveParameter(srv, environment.program_meta.app_id, std.mem.asBytes(&handle));
            defer if (params.parameter_handle.handle != .null) {
                _ = horizon.closeHandle(params.parameter_handle.handle);
            };

            break :capture_handle_wait handle;
        },
        else => unreachable,
    } else unreachable;
    defer if (capture_memory_handle != .null) {
        _ = horizon.closeHandle(capture_memory_handle);
    };

    if (is_library_applet) {
        // TODO: Do the conversion ourselves
    }

    try apt.sendSendCaptureBufferInfo(srv, &apt_capture_info);
}

pub fn sendInitialize(apt: Applet, srv: ServiceManager, id: AppId, attr: Attributes) Error![2]Event {
    return switch (try apt.lockSendCommand(srv, command.Initialize, .{ .id = id, .attributes = attr }, .{})) {
        .success => |s| s.value.response.notification_resume,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendEnable(apt: Applet, srv: ServiceManager, attr: Attributes) Error!void {
    return switch (try apt.lockSendCommand(srv, command.Enable, .{ .attributes = attr }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendFinalize(apt: Applet, srv: ServiceManager, id: AppId) !void {
    return switch (try apt.lockSendCommand(srv, command.Finalize, .{ .id = id }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetAppletManInfo(apt: Applet, srv: ServiceManager, position: Position) !command.GetAppletManInfo.Response {
    return switch (try apt.lockSendCommand(srv, command.GetAppletManInfo, .{ .position = position }, .{})) {
        .success => |s| s.value.response,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsRegistered(apt: Applet, srv: ServiceManager, id: AppId) !bool {
    return switch (try apt.lockSendCommand(srv, command.IsRegistered, .{ .id = id }, .{})) {
        .success => |s| s.value.response.registered,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInquireNotification(apt: Applet, srv: ServiceManager, id: AppId) !Notification {
    return switch (try apt.lockSendCommand(srv, command.InquireNotification, .{ .id = id }, .{})) {
        .success => |s| s.value.response.notification,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSendParameter(apt: Applet, srv: ServiceManager, src: AppId, dst: AppId, cmd: Command, handle: Object, parameter: []const u8) !void {
    return switch (try apt.lockSendCommand(srv, command.SendParameter, .{ .src_id = src, .dst_id = dst, .cmd = cmd, .parameter_size = parameter.len, .parameter_handle = handle, .parameter = .init(parameter) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReceiveParameter(apt: Applet, srv: ServiceManager, id: AppId, parameter: []u8) !command.ReceiveParameter.Response {
    return switch (try apt.lockSendCommand(srv, command.ReceiveParameter, .{ .id = id, .parameter_size = parameter.len }, .{parameter})) {
        .success => |s| s.value.response,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGlanceParameter(apt: Applet, srv: ServiceManager, id: AppId, parameter: []u8) !command.GlanceParameter.Response {
    return switch (try apt.lockSendCommand(srv, command.GlanceParameter, .{ .id = id, .parameter_size = parameter.len }, .{parameter})) {
        .success => |s| s.value.response,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendCancelParameter(apt: Applet, srv: ServiceManager, src: AppId, dst: AppId) !bool {
    return switch (try apt.lockSendCommand(srv, command.CancelParameter, .{ .check_sender = src != .none, .sender = src, .check_receiver = dst != .none, .receiver = dst }, .{})) {
        .success => |s| s.value.response.success,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPrepareToCloseApplication(apt: Applet, srv: ServiceManager, cancel_preload: bool) !void {
    return switch (try apt.lockSendCommand(srv, command.PrepareToCloseApplication, .{ .cancel_preload = cancel_preload }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendCloseApplication(apt: Applet, srv: ServiceManager, parameters: []const u8, handle: Object) !void {
    return switch (try apt.lockSendCommand(srv, command.CloseApplication, .{ .parameters_size = parameters.len, .parameter_handle = handle, .parameters = .init(parameters) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPrepareToJumpToHomeMenu(apt: Applet, srv: ServiceManager) !void {
    return switch (try apt.lockSendCommand(srv, command.PrepareToJumpToHomeMenu, .{}, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
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

    return switch (try apt.lockSendCommand(srv, command.JumpToHomeMenu, .{ .parameters_size = parameters.len, .parameter_handle = .null, .parameters = .init(parameters) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPrepareToDoApplicationJump(apt: Applet, srv: ServiceManager, flags: command.PrepareToDoApplicationJump.Request.Flags, title_id: u64, media_type: Filesystem.MediaType) !void {
    return switch (try apt.lockSendCommand(srv, command.PrepareToDoApplicationJump, .{ .flags = flags, .title_id = title_id, .media_type = media_type }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendDoApplicationJump(apt: Applet, srv: ServiceManager, parameters: []const u8, hmac: *const [0x20]u8) Error!void {
    return switch (try apt.lockSendCommand(srv, command.DoApplicationJump, .{ .parameter_size = parameters.len, .hmac_size = hmac.len, .parameter = .init(parameters), .hmac = .init(hmac[0..20]) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSendDspSleep(apt: Applet, srv: ServiceManager, source: AppId, handle: Object) Error!void {
    return switch (try apt.lockSendCommand(srv, command.SendDspSleep, .{ .source = source, .handle = handle }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSendDspWakeup(apt: Applet, srv: ServiceManager, source: AppId, handle: Object) Error!void {
    return switch (try apt.lockSendCommand(srv, command.SendDspWakeup, .{ .source = source, .handle = handle }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReplySleepQuery(apt: Applet, srv: ServiceManager, id: AppId, reply: QueryReply) Error!void {
    return switch (try apt.lockSendCommand(srv, command.ReplySleepQuery, .{ .id = id, .reply = reply }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReplySleepNotificationComplete(apt: Applet, srv: ServiceManager, id: AppId) Error!void {
    return switch (try apt.lockSendCommand(srv, command.ReplySleepNotificationComplete, .{ .id = id }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSendCaptureBufferInfo(apt: Applet, srv: ServiceManager, info: *const CaptureBuffer) Error!void {
    return switch (try apt.lockSendCommand(srv, command.SendCaptureBufferInfo, .{ .capture_size = @sizeOf(CaptureBuffer), .capture = .init(std.mem.asBytes(info)) }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendNotifyToWait(apt: Applet, srv: ServiceManager, id: AppId) Error!void {
    return switch (try apt.lockSendCommand(srv, command.NotifyToWait, .{ .id = id }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendAppletUtility(apt: Applet, srv: ServiceManager, utility: Utility, input: []const u8, output: []u8) Error!void {
    // TODO: return the ResultCode from applet_result in the Response, waiting for ziglang# #24231
    return switch (try apt.lockSendCommand(srv, command.AppletUtility, .{ .utility = utility, .input_size = input.len, .output_size = output.len, .input = .init(input) }, .{output})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
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

// FIXME: returns wrong_arg error?
pub fn sendUnlockTransition(apt: Applet, srv: ServiceManager, transition: Transition) Error!void {
    return apt.sendAppletUtility(srv, .unlock_transition, std.mem.asBytes(&transition), &.{});
}

pub fn lockSendCommand(apt: Applet, srv: ServiceManager, comptime DefinedCommand: type, request: DefinedCommand.Request, static_buffers: [DefinedCommand.input_static_buffers][]u8) !Result(ipc.Response(DefinedCommand.Response, DefinedCommand.output_static_buffers)) {
    try apt.lock.wait(-1);
    defer apt.lock.release();

    var fresh_session = try srv.sendGetServiceHandle(apt.available_service_name, .wait);
    defer fresh_session.deinit();

    const data = tls.getThreadLocalStorage();

    return data.ipc.sendRequest(fresh_session, DefinedCommand, request, static_buffers);
}

pub const command = struct {
    pub const GetLockHandle = ipc.Command(Id, .get_lock_handle, struct { flags: u32 = 0 }, struct {
        pub const Flags = packed struct(u32) {
            power_button: bool,
            order_to_close: bool,
            _: u30 = 0,
        };

        attributes: Attributes,
        state: Flags,
        lock: Mutex,
    });
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        id: AppId,
        attributes: Attributes,
    }, struct {
        notification_resume: [2]Event,
    });
    pub const Enable = ipc.Command(Id, .enable, struct { attributes: Attributes }, struct {});
    pub const Finalize = ipc.Command(Id, .finalize, struct { id: AppId }, struct {});
    pub const GetAppletManInfo = ipc.Command(Id, .get_applet_man_info, struct {
        position: Position,
    }, struct {
        position: Position,
        requested: AppId,
        home_menu: AppId,
        current: AppId,
    });
    pub const GetAppletInfo = ipc.Command(Id, .get_applet_info, struct {
        id: AppId,
    }, struct {
        title_id: u64,
        media_type: Filesystem.MediaType,
        registered: bool,
        loaded: bool,
        attributes: Attributes,
    });
    pub const GetLastSignaledAppletId = ipc.Command(Id, .get_last_signaled_applet_id, struct {}, struct { id: AppId });
    pub const CountRegisteredApplet = ipc.Command(Id, .count_registered_applet, struct {}, struct { registered: u32 });
    pub const IsRegistered = ipc.Command(Id, .is_registered, struct { id: AppId }, struct { registered: bool });
    pub const GetAttribute = ipc.Command(Id, .get_attribute, struct { id: AppId }, struct { attributes: Attributes });
    pub const InquireNotification = ipc.Command(Id, .inquire_notification, struct { id: AppId }, struct { notification: Notification });
    pub const SendParameter = ipc.Command(Id, .send_parameter, struct {
        src_id: AppId,
        dst_id: AppId,
        cmd: Command,
        parameter_size: usize,
        parameter_handle: horizon.Object,
        parameter: ipc.StaticSlice(0),
    }, struct {});
    pub const ReceiveParameter = ipc.Command(Id, .receive_parameter, struct {
        pub const static_buffers = 1;
        id: AppId,
        parameter_size: usize,
    }, struct {
        sender: AppId,
        cmd: Command,
        actual_size: usize,
        parameter_handle: ipc.MoveHandle(horizon.Object),
        actual_parameter: ipc.StaticSlice(0),
    });
    pub const GlanceParameter = ipc.Command(Id, .glance_parameter, struct {
        pub const static_buffers = 1;
        id: AppId,
        parameter_size: usize,
    }, struct {
        sender: AppId,
        cmd: Command,
        actual_size: usize,
        parameter_handle: horizon.Object,
        actual_parameter: ipc.StaticSlice(0),
    });
    pub const CancelParameter = ipc.Command(Id, .cancel_parameter, struct {
        check_sender: bool,
        sender: AppId,
        check_receiver: bool,
        receiver: AppId,
    }, struct {
        success: bool,
    });
    // TODO: DebugFunc
    // TODO: MapProgramIdForDebug
    // TODO: SetHomeMenuAppletIdForDebug
    // TODO: GetPreparationState
    // TODO: SetPreparationState
    // TODO: PrepareToStartApplication
    // TODO: PreloadLibraryApplet
    // TODO: FinishPreloadingLibraryApplet
    // TODO: PrepareToStartLibraryApplet
    // TODO: PrepareToStartSystemApplet
    // TODO: PrepareToStartNewestHomeMenu
    // TODO: StartApplication
    // TODO: WakeupApplication
    // TODO: CancelApplication
    // TODO: StartLibraryApplet
    // TODO: StartSystemApplet
    // TODO: StartNewestHomeMenu
    // TODO: OrderToCloseApplcation
    pub const PrepareToCloseApplication = ipc.Command(Id, .prepare_to_close_application, struct { cancel_preload: bool }, struct {});
    // TODO: PrepareToJumpToApplication
    // TODO: JumpToApplication
    // TODO: PrepareToCloseLibraryApplet
    // TODO: PrepareToCloseSystemApplet
    pub const CloseApplication = ipc.Command(Id, .close_application, struct {
        parameters_size: usize,
        parameter_handle: horizon.Object,
        parameters: ipc.StaticSlice(0),
    }, struct {});
    // TODO: ...
    pub const PrepareToJumpToHomeMenu = ipc.Command(Id, .prepare_to_jump_to_home_menu, struct {}, struct {});
    pub const JumpToHomeMenu = ipc.Command(Id, .jump_to_home_menu, struct {
        parameters_size: usize,
        parameter_handle: horizon.Object,
        parameters: ipc.StaticSlice(0),
    }, struct {});
    // TODO: ...
    pub const PrepareToDoApplicationJump = ipc.Command(Id, .prepare_to_do_application_jump, struct {
        pub const Flags = enum(u8) {
            use_input_parameters,
            use_ns_parameters,
            use_app_id_parameters,
        };

        flags: Flags,
        title_id: u64,
        media_type: Filesystem.MediaType,
    }, struct {});
    pub const DoApplicationJump = ipc.Command(Id, .do_application_jump, struct {
        parameter_size: usize,
        hmac_size: usize,
        parameter: ipc.StaticSlice(0),
        hmac: ipc.StaticSlice(2),
    }, struct {});
    // TODO: ...
    pub const SendDspSleep = ipc.Command(Id, .send_dsp_sleep, struct { source: AppId, handle: horizon.Object }, struct {});
    pub const SendDspWakeup = ipc.Command(Id, .send_dsp_wakeup, struct { source: AppId, handle: horizon.Object }, struct {});
    pub const ReplySleepQuery = ipc.Command(Id, .reply_sleep_query, struct {
        id: AppId,
        reply: QueryReply,
    }, struct {});
    pub const ReplySleepNotificationComplete = ipc.Command(Id, .reply_sleep_notification_complete, struct {
        id: AppId,
    }, struct {});
    pub const SendCaptureBufferInfo = ipc.Command(Id, .send_capture_buffer_info, struct {
        capture_size: usize,
        capture: ipc.StaticSlice(0),
    }, struct {});
    // TODO: ...
    pub const NotifyToWait = ipc.Command(Id, .notify_to_wait, struct { id: AppId }, struct {});
    // TODO: ...
    pub const AppletUtility = ipc.Command(Id, .applet_utility, struct {
        pub const static_buffers = 1;
        utility: Utility,
        input_size: usize,
        output_size: usize,
        input: ipc.StaticSlice(1),
    }, struct { applet_result: ResultCode, output: ipc.StaticSlice(0) });
    // TODO: ...

    pub const Id = enum(u16) {
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
    };
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

const Result = horizon.Result;
const ResultCode = horizon.ResultCode;
const Object = horizon.Object;
const Session = horizon.ClientSession;
const Event = horizon.Event;
const Mutex = horizon.Mutex;
const ServiceManager = zitrus.horizon.ServiceManager;
