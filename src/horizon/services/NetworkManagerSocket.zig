pub const service = "nwm::SOC";

session: ClientSession,

pub fn open(srv: ServiceManager) !NetworkManagerSocket {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(nwmsoc: NetworkManagerSocket) void {
    nwmsoc.session.close();
}

pub const command = struct {
    pub const Id = enum(u16) {};
};

const NetworkManagerSocket = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
