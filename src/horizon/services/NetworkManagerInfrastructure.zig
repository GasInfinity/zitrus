pub const service = "nwm::INF";

session: ClientSession,

pub fn open(srv: ServiceManager) !NetworkManagerInfrastructure {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(nwminf: NetworkManagerInfrastructure) void {
    nwminf.session.close();
}

pub const command = struct {
    pub const Id = enum(u16) {};
};

const NetworkManagerInfrastructure = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
