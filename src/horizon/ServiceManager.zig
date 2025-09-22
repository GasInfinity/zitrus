//! A connection to the `Horizon` service manager.
//!
//! This port manages all service registration and retrieval,
//! while also checking the process service control list.

pub const port = "srv:";

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

    pub const Manager = struct {
        notification: Semaphore,

        pub fn init(srv: ServiceManager) !Manager {
            return .{ .notification = try srv.sendEnableNotification() };
        }

        pub fn deinit(man: *Manager) void {
            man.notification.close();
            man.* = undefined;
        }

        pub fn waitNotification(man: Manager, srv: ServiceManager) !Notification {
            return try man.waitNotificationTimeout(srv, -1).?;
        }

        pub fn pollNotification(man: Manager, srv: ServiceManager) !?Notification {
            return try man.waitNotificationTimeout(srv, 0);
        }

        pub fn waitNotificationTimeout(man: Manager, srv: ServiceManager, timeout_ns: i64) !?Notification {
            man.notification.wait(timeout_ns) catch |err| switch (err) {
                error.Timeout => return null,
                else => |e| return e,
            };
            _ = man.notification.release(1);

            return try srv.sendReceiveNotification();
        }
    };
};

session: ClientSession,

pub fn open() !ServiceManager {
    return .{ .session = try ClientSession.connect(port) };
}

pub fn close(srv: ServiceManager) void {
    srv.session.close();
}

pub fn getService(srv: ServiceManager, name: []const u8, flags: command.GetServiceHandle.Request.Flags) !ClientSession {
    if (environment.findService(name)) |service| {
        return service;
    }

    return srv.sendGetServiceHandle(name, flags);
}

pub fn sendRegisterClient(srv: ServiceManager) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.RegisterClient, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendEnableNotification(srv: ServiceManager) !Semaphore {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.EnableNotification, .{}, .{})).cases()) {
        .success => |s| s.value.response.notification_received,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRegisterService(srv: ServiceManager, name: []const u8, max_sessions: i16) !ServerPort {
    std.debug.assert(name.len <= 8);

    var req: command.RegisterService.Request = .{
        .name = undefined,
        .name_len = @intCast(name.len),
        .max_sessions = max_sessions,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.RegisterService, req, .{})).cases()) {
        .success => |s| s.value.response.server,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterService(srv: ServiceManager, name: []const u8) !void {
    std.debug.assert(name.len <= 8);

    var req: command.UnregisterService.Request = .{
        .name = undefined,
        .name_len = @intCast(name.len),
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.UnregisterService, req, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const GetServiceHandleError = error{ AccessDenied, PortFull };

// FIXME: Handle errors properly!
pub fn sendGetServiceHandle(srv: ServiceManager, name: []const u8, flags: command.GetServiceHandle.Request.Flags) !ClientSession {
    std.debug.assert(name.len <= 8);

    var req: command.GetServiceHandle.Request = .{
        .name = undefined,
        .name_len = name.len,
        .flags = flags,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.GetServiceHandle, req, .{})).cases()) {
        .success => |s| s.value.response.service.handle,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRegisterPort(srv: ServiceManager, name: []const u8, registering_port: ClientPort) !ServerPort {
    std.debug.assert(name.len <= 8);

    var req: command.RegisterPort.Request = .{
        .name = undefined,
        .name_len = name.len,
        .port = registering_port,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.RegisterPort, req, .{})).cases()) {
        .success => |s| s.value.response.server,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterPort(srv: ServiceManager, name: []const u8) !void {
    std.debug.assert(name.len <= 8);

    var req: command.UnregisterPort.Request = .{
        .name = undefined,
        .name_len = name.len,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.UnregisterPort, req, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetPort(srv: ServiceManager, name: []const u8, wait_until_found: bool) !ClientPort {
    std.debug.assert(name.len <= 8);

    var req: command.GetPort.Request = .{
        .name = undefined,
        .name_len = name.len,
        .wait_until_found = wait_until_found,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.GetPort, req, .{})).cases()) {
        .success => |s| s.value.response.service,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendSubscribe(srv: ServiceManager, notification: Notification) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.Subscribe, .{ .notification = notification }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnsubscribe(srv: ServiceManager, notification: Notification) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.Unsubscribe, .{ .notification = notification }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReceiveNotification(srv: ServiceManager) !Notification {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.ReceiveNotification, .{}, .{})).cases()) {
        .success => |s| s.value.response.notification,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPublishToSubscriber(srv: ServiceManager, notification: Notification, flags: command.PublishToSubscriber.Request.Flags) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.PublishToSubscriber, .{ .notification = notification, .flags = flags }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPublishAndGetSubscriber(srv: ServiceManager, notification: Notification) !command.PublishAndGetSubscriber.Response {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.PublishAndGetSubscriber, .{ .notification = notification }, .{})).cases()) {
        .success => |s| s.value.response,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsServiceRegistered(srv: ServiceManager, name: []const u8) !bool {
    std.debug.assert(name.len <= 8);

    var req: command.IsServiceRegistered.Request = .{
        .name = undefined,
        .name_len = name.len,
    };

    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.IsServiceRegistered, req, .{})).cases()) {
        .success => |s| s.value.response.registered,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const RegisterClient = ipc.Command(Id, .register_client, struct { pid: ipc.ReplaceByProcessId = .replace }, struct {});
    pub const EnableNotification = ipc.Command(Id, .enable_notification, struct {}, struct { notification_received: Semaphore });
    pub const RegisterService = ipc.Command(Id, .register_service, struct {
        name: [8]u8,
        name_len: usize,
        max_sessions: i16,
    }, struct { server: ServerPort });
    pub const UnregisterService = ipc.Command(Id, .unregister_service, struct {
        name: [8]u8,
        name_len: usize,
    }, struct {});
    pub const GetServiceHandle = ipc.Command(Id, .get_service_handle, struct {
        pub const Flags = packed struct(u32) {
            pub const wait: Flags = .{};
            pub const poll: Flags = .{ .error_if_full = true };

            error_if_full: bool = false,
            _: u31 = 0,
        };
        name: [8]u8,
        name_len: usize,
        flags: Flags,
    }, struct { service: ipc.MoveHandle(ClientSession) });
    pub const RegisterPort = ipc.Command(Id, .register_port, struct {
        name: [8]u8,
        name_len: usize,
        port: ClientPort,
    }, struct {});
    pub const UnregisterPort = ipc.Command(Id, .unregister_port, struct {
        name: [8]u8,
        name_len: usize,
    }, struct {});
    // XXX: What kind of port does this retrieve? I suppose a client port, also check if its moved from~
    pub const GetPort = ipc.Command(Id, .get_port, struct {
        name: [8]u8,
        name_len: usize,
        wait_until_found: bool,
    }, struct { port: ClientPort });
    pub const Subscribe = ipc.Command(Id, .subscribe, struct {
        notification: Notification,
    }, struct {});
    pub const Unsubscribe = ipc.Command(Id, .unsubscribe, struct {
        notification: Notification,
    }, struct {});
    pub const ReceiveNotification = ipc.Command(Id, .receive_notification, struct {}, struct { notification: Notification });
    pub const PublishToSubscriber = ipc.Command(Id, .publish_to_subscriber, struct {
        pub const Flags = packed struct(u32) {
            fire_if_not_pending: bool = false,
            no_error_if_full: bool = false,
            _: u30 = 0,
        };

        notification: Notification,
        flags: Flags,
    }, struct {});
    pub const PublishAndGetSubscriber = ipc.Command(Id, .publish_and_get_subscriber, struct {
        notification: Notification,
    }, struct {
        pid_count: u6,
        pids: [61]u32,
    });
    pub const IsServiceRegistered = ipc.Command(Id, .is_service_registered, struct {
        name: [8]u8,
        name_len: u4,
    }, struct {
        registered: bool,
    });

    pub const Id = enum(u16) {
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
    };
};

const ServiceManager = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Event = horizon.Event;
const Semaphore = horizon.Semaphore;
const ClientSession = horizon.ClientSession;
const ServerPort = horizon.ServerPort;
const ClientPort = horizon.ClientPort;
const ResultCode = horizon.result.Code;
