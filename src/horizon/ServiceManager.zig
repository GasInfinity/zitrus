pub const Error = Session.RequestError;

pub const Notification = enum(u32) {
    must_terminate = 0x100,
    sleep_mode_entry,
    sleep_mode_related,
    sleep_mode_entry_fired,
    system_entering_sleep,
    system_exited_sleep,
    post_sleep_mode_exit,
    ptm_unknown_event,
    system_power_down,
    cfg_lcd_brightness_changed = 0x109,
    cfg_camera_modified = 0x10B,
    application_started,
    application_exited = 0x110,
    all_non_ptm_ns_terminated = 0x179,
    pre_sleep_exit_signal = 0x200,
    power_button_pressed = 0x202,
    power_button_long_press,
    home_button_pressed,
    home_button_released,
    wifi_slider_state_changed,
    sd_card_inserted,
    game_card_inserted,
    sd_card_removed,
    game_card_removed,
    game_card_toggled,
    fatal_hardware_condition,
    charger_unplugged,
    charger_plugged,
    charging_started,
    charging_stopped,
    battery_very_low,
    battery_low,
    shell_opened,
    shell_closed,
    post_sleep_boot = 0x300,
    pre_sleep_exit_boot,
    wifi_turning_off,
    wifi_turned_off,
    _,
};

session: Session,
notification: ?Semaphore = null,

pub fn init(port: [:0]const u8) !SrvManager {
    const srv_session = try Session.connect(port);
    var srv = SrvManager{
        .session = srv_session,
    };
    errdefer srv.deinit();

    try srv.sendRegisterClient();
    srv.notification = try srv.sendEnableNotification();
    return srv;
}

pub fn deinit(srv: *SrvManager) void {
    if (srv.notification) |*notif| {
        notif.deinit();
    }

    srv.session.deinit();
    srv.* = undefined;
}

pub fn waitNotification(srv: SrvManager) Error!Notification {
    return try srv.waitNotificationTimeout(-1).?;
}

pub fn pollNotification(srv: SrvManager) Error!?Notification {
    return try srv.waitNotificationTimeout(0);
}

pub fn waitNotificationTimeout(srv: SrvManager, timeout_ns: i64) Error!?Notification {
    const notification = srv.notification.?;

    notification.wait(timeout_ns) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    };

    return try srv.sendReceiveNotification();
}

pub fn getService(srv: SrvManager, name: []const u8, wait: bool) Error!Session {
    if (environment.findService(name)) |service| {
        return service;
    }

    return srv.sendGetServiceHandle(name, wait);
}

pub fn sendRegisterClient(srv: SrvManager) !void {
    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(ServiceManagerCommand.register_client, .{}, .{ ipc.HandleTranslationDescriptor.replace_by_proccess_id, @as(u32, 0) });
    try srv.session.sendRequest();
    // @as(horizon.ResultCode, @bitCast(data.ipc.parameters[1])).;
}

pub fn sendEnableNotification(srv: SrvManager) !Semaphore {
    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(ServiceManagerCommand.enable_notification, .{}, .{});
    try srv.session.sendRequest();
    // try data.ipc.checkLastResult();
    return @as(Semaphore, @bitCast(data.ipc.parameters[2]));
}

pub fn sendGetServiceHandle(srv: SrvManager, name: []const u8, wait: bool) !Session {
    std.debug.assert(name.len <= 8);
    const data = tls.getThreadLocalStorage();

    const first: u32, const second: u32 = if (name.len <= 4) short: {
        var first: u32 = 0;
        @memcpy(std.mem.asBytes(&first)[0..name.len], name);
        break :short .{ first, 0 };
    } else long: {
        const remaining = name.len - 4;
        var second: u32 = 0;
        @memcpy(std.mem.asBytes(&second)[0..remaining], name[4..][0..remaining]);

        break :long .{ @as(u32, @bitCast(name[0..4].*)), second };
    };

    data.ipc.fillCommand(ServiceManagerCommand.get_service_handle, .{ first, second, @as(u32, @intCast(name.len)), @as(u32, @intFromBool(!wait)) }, .{});
    try srv.session.sendRequest();

    // const get_handle_result: ResultCode = @bitCast(data.ipc.parameters[0]);
    // try get_handle_result.ziggify();

    return @as(Session, @bitCast(data.ipc.parameters[2]));
}

pub fn sendSubscribe(srv: SrvManager, notification: Notification) !void {
    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(ServiceManagerCommand.subscribe, .{notification}, .{});
    try srv.session.sendRequest();
    // try data.ipc.checkLastResult();
}

pub fn sendUnsubscribe(srv: SrvManager, notification: Notification) !void {
    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(ServiceManagerCommand.unsubscribe, .{notification}, .{});
    try srv.session.sendRequest();
    // try data.ipc.checkLastResult();
}

pub fn sendReceiveNotification(srv: SrvManager) !Notification {
    const data = tls.getThreadLocalStorage();

    data.ipc.fillCommand(ServiceManagerCommand.receive_notification, .{}, .{});
    try srv.session.sendRequest();
    // try data.ipc.checkLastResult();
    return @enumFromInt(data.ipc.parameters[1]);
}

pub const ServiceManagerCommand = enum(u16) {
    register_client = 0x0001,
    enable_notification,
    register_service,
    unregister_service,
    get_service_handle,
    register_port,
    unregister_port,
    get_port,
    subscribe,
    unsubscribe,
    receive_notification,
    publish_to_subscriber,
    publish_and_get_subscriber,
    is_service_registered,

    // Only available to "srv:pm"
    // TODO: Split this
    publish_to_process = 0x0401,
    publish_to_all,
    register_process,
    unregister_process,

    pub inline fn normalParameters(cmd: ServiceManagerCommand) u6 {
        return switch (cmd) {
            .register_client => 0,
            .enable_notification => 0,
            .register_service => 4,
            .unregister_service => 3,
            .get_service_handle => 4,
            .register_port => 3,
            .unregister_port => 3,
            .get_port => 4,
            .subscribe => 1,
            .unsubscribe => 1,
            .receive_notification => 0,
            .publish_to_subscriber => 2,
            .publish_and_get_subscriber => 1,
            .is_service_registered => 3,
            .publish_to_process => 1,
            .publish_to_all => 1,
            .register_process => 2,
            .unregister_process => 1,
        };
    }

    pub inline fn translateParameters(cmd: ServiceManagerCommand) u6 {
        return switch (cmd) {
            .register_client => 2,
            .enable_notification => 0,
            .register_service => 0,
            .unregister_service => 0,
            .get_service_handle => 0,
            .register_port => 2,
            .unregister_port => 0,
            .get_port => 0,
            .subscribe => 0,
            .unsubscribe => 0,
            .receive_notification => 0,
            .publish_to_subscriber => 0,
            .publish_and_get_subscriber => 0,
            .is_service_registered => 0,
            .publish_to_process => 2,
            .publish_to_all => 0,
            .register_process => 2,
            .unregister_process => 0,
        };
    }
};

const SrvManager = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Event = horizon.Event;
const Semaphore = horizon.Semaphore;
const Session = horizon.ClientSession;
const ResultCode = horizon.ResultCode;
