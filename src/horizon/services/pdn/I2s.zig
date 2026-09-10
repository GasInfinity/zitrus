//! `pdn:i`

pub const service = "pdn:i";

session: ClientSession,

pub fn open(srv: ServiceManager) !I2s {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pdn: I2s) void {
    pdn.session.close();
}

pub fn sendControl1(pdn: I2s, enable: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.Control1, .{ .enable = enable }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendControl2(pdn: I2s, enable: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.Control2, .{ .enable = enable }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    pub const Control1 = ipc.Command(Id, .control_1, struct { enable: bool }, struct {});
    pub const Control2 = ipc.Command(Id, .control_2, struct { enable: bool }, struct {});

    pub const Id = enum(u16) {
        control_1 = 0x0001,
        control_2,
    };
};

const I2s = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
