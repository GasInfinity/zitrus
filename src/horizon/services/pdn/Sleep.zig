//! `pdn:s`

pub const service = "pdn:s";

pub const Wake = hardware.pdn.Sleep.Wake;

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendGetWakeStatus(pdn: Sleep) !command.GetWakeStatus.Response {
    return switch ((try pdn.send(.GetWakeStatus, {}, .{})).cases()) {
        .success => |r| r.value,
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendConfigureWake(pdn: Sleep, enable: Wake, acknowledge: Wake) !void {
    return switch ((try pdn.send(.ConfigureWake, .{
        .enable = enable,
        .acknowledge = acknowledge,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendAcknowledgeWake(pdn: Sleep, acknowledge: Wake) !void {
    return switch ((try pdn.send(.AcknowledgeWake, .{
        .acknowledge = acknowledge,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    /// Cannot fail
    pub const GetWakeStatus = ipc.Command(Id, .get_wake_status, void, struct {
        enabled: Wake,
        reason: Wake,
    });
    /// Cannot fail
    pub const ConfigureWake = ipc.Command(Id, .configure_wake, struct {
        enable: Wake,
        acknowledge: Wake,
    }, void);
    /// Cannot fail
    pub const AcknowledgeWake = ipc.Command(Id, .acknowledge_wake, struct {
        acknowledge: Wake,
    }, void);

    pub const Id = enum(u16) {
        get_wake_status = 0x0001,
        configure_wake,
        acknowledge_wake,
    };
};

const Sleep = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const horizon = zitrus.horizon;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
