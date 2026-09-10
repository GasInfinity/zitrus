//! `pdn:s`

pub const service = "pdn:s";

pub const Wake = hardware.pdn.Sleep.Wake;

session: ClientSession,

pub fn open(srv: ServiceManager) !Sleep {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pdn: Sleep) void {
    pdn.session.close();
}

pub fn sendGetWakeStatus(pdn: Sleep) !command.GetWakeStatus.Response {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.GetWakeStatus, .{}, .{})).cases()) {
        .success => |r| r.value,
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendConfigureWake(pdn: Sleep, enable: Wake, acknowledge: Wake) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.ConfigureWake, .{
        .enable = enable,
        .acknowledge = acknowledge,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendAcknowledgeWake(pdn: Sleep, acknowledge: Wake) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.AcknowledgeWake, .{
        .acknowledge = acknowledge,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    /// Cannot fail
    pub const GetWakeStatus = ipc.Command(Id, .get_wake_status, struct {}, struct {
        enabled: Wake,
        reason: Wake,
    });
    /// Cannot fail
    pub const ConfigureWake = ipc.Command(Id, .configure_wake, struct {
        enable: Wake,
        acknowledge: Wake,
    }, struct {});
    /// Cannot fail
    pub const AcknowledgeWake = ipc.Command(Id, .acknowledge_wake, struct {
        acknowledge: Wake,
    }, struct {});

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
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
