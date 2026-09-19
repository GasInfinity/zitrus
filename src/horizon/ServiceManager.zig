//! A connection to the `Horizon` service manager.
//!
//! This port manages all service registration and retrieval,
//! while also checking the process service control list.

pub const port = "srv:";

pub const PortAccessError = error{
    /// The name was too long, `0` or has embedded `\0`.
    BadPortName,
    /// Process doesn't have access to the specified service/port.
    AccessDenied,
};

pub const PortRetrievalError = error{
    /// The port was not registered.
    PortNotFound,
};

pub const ServiceRetrievalError = horizon.ClientPort.CreateSessionError;

pub const PortRegistrationError = error{
    /// The name was too long, `0` or has embedded `\0`.
    BadPortName,
    /// The service/port is already registered.
    PortAlreadyExists,
    /// Service Manager is out of memory for services.
    SystemResources,
};

pub const PortUnregistrationError = error{
    /// Tried to unregister a service/port that was not registered.
    PortNotFound,
    /// Tried to unregister a service/port not owned by this process.
    AccessDenied,
};

pub const NotificationError = error{
    /// Tried to enable notifications without registering the process.
    ProcessNotFound,
};

pub const Notification = enum(u32) {
    must_terminate = 0x100,

    // These names come from libctru as 3dbrew has outdated info
    // Published by ptm
    sleep_requested,
    sleep_denied,
    sleep_allowed,
    entering_sleep,
    waking_up,
    awake,
    half_awake,
    shutdown,

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
            return try man.waitNotificationTimeout(srv, .none).?;
        }

        pub fn pollNotification(man: Manager, srv: ServiceManager) !?Notification {
            return try man.waitNotificationTimeout(srv, .fromNanoseconds(0));
        }

        pub fn waitNotificationTimeout(man: Manager, srv: ServiceManager, timeout: horizon.Timeout) !?Notification {
            man.notification.wait(timeout) catch |err| switch (err) {
                error.Timeout => return null,
                else => |e| return e,
            };
            _ = man.notification.release(1);

            return try srv.sendReceiveNotification();
        }
    };
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openPort;
pub const openWithResult = horizon.services.Methods(@This()).openPortWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = ipc.ServiceSend(@This()).send;
pub const sendWithResult = ipc.ServiceSend(@This()).sendWithResult;

pub fn getService(srv: ServiceManager, name: []const u8, error_if_full: bool) !ClientSession {
    if (environment.findService(name)) |service| {
        return service;
    }

    return srv.sendGetService(name, error_if_full);
}

pub fn sendRegisterClient(srv: ServiceManager) !void {
    return switch ((try srv.send(.RegisterClient, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendEnableNotification(srv: ServiceManager) !Semaphore {
    return switch ((try srv.send(.EnableNotification, {}, .{})).cases()) {
        .success => |s| s.value,
        .failure => |code| switch (code) {
            .srv_process_not_registered => error.ProcessNotFound,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub fn sendRegisterService(srv: ServiceManager, name: []const u8, max_sessions: i16) !ServerPort {
    return switch ((try srv.send(.RegisterService, .init(name, max_sessions), .{})).cases()) {
        .success => |s| s.value.wrapped,
        .failure => |code| switch (code) {
            .srv_name_out_of_bounds => error.BadPortName,
            .srv_name_embedded_null => error.BadPortName,
            .os_already_exists => error.PortAlreadyExists,
            .srv_out_of_services => error.SystemResources,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub fn sendUnregisterService(srv: ServiceManager, name: []const u8) !void {
    return switch ((try srv.send(.UnregisterService, .init(name), .{})).cases()) {
        .success => {},
        .failure => |code| switch (code) {
            .os_not_found => error.PortNotFound,
            .srv_access_denied => error.AccessDenied,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub fn sendGetService(srv: ServiceManager, name: []const u8, error_if_full: bool) !ClientSession {
    return switch ((try srv.send(.GetService, .init(name, error_if_full), .{})).cases()) {
        .success => |s| s.value.wrapped,
        .failure => |code| switch (code) {
            .kernel_invalid_handle => unreachable,
            .srv_access_denied => error.AccessDenied,
            .out_of_sessions, .kernel_out_of_handles, .os_out_of_kernel_memory => error.SystemResources,
            .os_port_busy => error.PortBusy,
            .srv_name_out_of_bounds, .srv_name_embedded_null => error.BadPortName,
            .os_not_found => error.PortNotFound,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub fn sendRegisterPort(srv: ServiceManager, name: []const u8, registering_port: ClientPort) !ServerPort {
    const C = horizon.result.Code;
    std.debug.assert(name.len <= 8);

    var req: command.RegisterPort.Request = .{
        .name = @splat(0),
        .name_len = name.len,
        .port = registering_port,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.RegisterPort, req, .{})).cases()) {
        .success => |s| s.value.server,
        .failure => |code| if (code == C.srv_name_out_of_bounds or code == C.srv_name_embedded_null) error.BadPortName else if (code == C.os_already_exists) error.PortAlreadyExists else if (code == C.srv_out_of_services) error.SystemResources else horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterPort(srv: ServiceManager, name: []const u8) !void {
    const C = horizon.result.Code;
    std.debug.assert(name.len <= 8);

    var req: command.UnregisterPort.Request = .{
        .name = @splat(0),
        .name_len = name.len,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.UnregisterPort, req, .{})).cases()) {
        .success => {},
        .failure => |code| if (C.os_not_found) error.PortNotFound else if (C.srv_access_denied) error.AccessDenied else horizon.unexpectedResult(code),
    };
}

pub fn sendGetPort(srv: ServiceManager, name: []const u8, wait_until_found: bool) !ClientPort {
    const C = horizon.result.Code;
    std.debug.assert(name.len <= 8);

    var req: command.GetPort.Request = .{
        .name = @splat(0),
        .name_len = name.len,
        .wait_until_found = wait_until_found,
    };
    @memcpy(req.name[0..name.len], name);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(srv.session, command.GetPort, req, .{})).cases()) {
        .success => |s| s.value.wrapped,
        .failure => |code| if (code == C.srv_access_denied) error.AccessDenied else if (code == C.srv_name_out_of_bounds or code == C.srv_name_embedded_null) error.BadPortName else if (code == C.os_not_found) error.PortNotFound else horizon.unexpectedResult(code),
    };
}

pub fn sendSubscribe(srv: ServiceManager, notification: Notification) !void {
    return switch ((try srv.send(.Subscribe, notification, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnsubscribe(srv: ServiceManager, notification: Notification) !void {
    return switch ((try srv.send(.Unsubscribe, notification, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReceiveNotification(srv: ServiceManager) !Notification {
    return switch ((try srv.send(.ReceiveNotification, {}, .{})).cases()) {
        .success => |s| s.value,
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
        .success => |s| s.value,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsServiceRegistered(srv: ServiceManager, name: []const u8) !bool {
    return switch ((try srv.send(.IsServiceRegistered, .init(name), .{})).cases()) {
        .success => |s| s.value,
        .failure => |code| switch (code) {
            .srv_access_denied => error.AccessDenied,
            .srv_name_out_of_bounds => error.BadPortName,
            .srv_name_embedded_null => error.BadPortName,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub const command = struct {
    pub const RegisterClient = ipc.Command(Id, .register_client, struct { pid: ipc.ReplaceByProcessId = .replace }, void);
    pub const EnableNotification = ipc.Command(Id, .enable_notification, void, Semaphore);
    pub const RegisterService = ipc.Command(Id, .register_service, struct {
        name: ipc.EmbeddedSentinel(8, u8, .post, 0),
        max_sessions: i16,

        pub fn init(name: []const u8, max_sessions: i16) @This() {
            std.debug.assert(name.len <= 8);
            return .{ .name = .embedded(name), .max_sessions = max_sessions };
        }
    }, ipc.MoveHandles(ServerPort));
    pub const UnregisterService = ipc.Command(Id, .unregister_service, ipc.EmbeddedSentinel(8, u8, .post, 0), void);
    pub const GetService = ipc.Command(Id, .get_service, struct {
        name: ipc.EmbeddedSentinel(8, u8, .post, 0),
        error_if_full: bool,

        pub fn init(name: []const u8, error_if_full: bool) @This() {
            return .{ .name = .embedded(name), .error_if_full = error_if_full };
        }
    }, ipc.MoveHandles(ClientSession));
    pub const RegisterPort = ipc.Command(Id, .register_port, struct {
        name: ipc.EmbeddedSentinel(8, u8, .post, 0),
        port: ClientPort,
    }, void);
    pub const UnregisterPort = ipc.Command(Id, .unregister_port, ipc.EmbeddedSentinel(8, u8, .post, 0), void);
    pub const GetPort = ipc.Command(Id, .get_port, struct {
        name: ipc.EmbeddedSentinel(8, u8, .post, 0),
        error_if_full: bool,
    }, ipc.MoveHandles(ClientPort));
    pub const Subscribe = ipc.Command(Id, .subscribe, Notification, void);
    pub const Unsubscribe = ipc.Command(Id, .unsubscribe, Notification, void);
    pub const ReceiveNotification = ipc.Command(Id, .receive_notification, void, Notification);
    pub const PublishToSubscriber = ipc.Command(Id, .publish_to_subscriber, struct {
        pub const Flags = packed struct(u32) {
            fire_if_not_pending: bool = false,
            no_error_if_full: bool = false,
            _: u30 = 0,
        };

        notification: Notification,
        flags: Flags,
    }, void);
    pub const PublishAndGetSubscriber = ipc.Command(Id, .publish_and_get_subscriber, Notification, ipc.Embedded(61, horizon.Process.Id, .pre));
    pub const IsServiceRegistered = ipc.Command(Id, .is_service_registered, ipc.EmbeddedSentinel(8, u8, .post, 0), bool);

    pub const Id = enum(u16) {
        register_client = 0x0001,
        enable_notification,
        register_service,
        unregister_service,
        get_service,
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
const ClientSession = horizon.Session.Client;
const ServerPort = horizon.Port.Server;
const ClientPort = horizon.Port.Client;
const ResultCode = horizon.result.Code;
