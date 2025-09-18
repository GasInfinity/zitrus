const service_name = "ns:p";

session: ClientSession,

pub fn open(srv: ServiceManager) !NUserShellPower {
    return .{ .session = try srv.getService(service_name, .wait) };
}

pub fn close(nsp: NUserShellPower) void {
    nsp.session.close();
}

pub fn sendRebootSystem(nsp: NUserShellPower, relaunch_on_boot: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(nsp.session, command.RebootSystem, .{ .relaunch_on_boot = relaunch_on_boot }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendShutdownAsync(nsp: NUserShellPower) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(nsp.session, command.ShutdownAsync, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const RebootSystem = ipc.Command(Id, .reboot_system, struct { relaunch_on_boot: bool }, struct {});
    pub const ShutdownAsync = ipc.Command(Id, .shutdown_async, struct {}, struct {});

    pub const Id = enum(u16) {
        reboot_system = 0x0001,
        shutdown_async,
    };
};

const NUserShellPower = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
