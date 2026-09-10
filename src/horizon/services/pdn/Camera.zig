//! `pdn:c`

pub const service = "pdn:c";

session: ClientSession,

pub fn open(srv: ServiceManager) !Camera {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pdn: Camera) void {
    pdn.session.close();
}

pub fn sendControl(pdn: Camera, enable: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.Control, .{
        .enable = enable,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendIsEnabled(pdn: Camera) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.IsEnabled, .{}, .{})).cases()) {
        .success => |r| r.value.enabled,
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    pub const Control = ipc.Command(Id, .control, struct { enable: bool }, struct {});
    pub const IsEnabled = ipc.Command(Id, .is_enabled, struct {}, struct { enabled: bool });

    pub const Id = enum(u16) {
        control = 0x0001,
        is_enabled,
    };
};

const Camera = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
