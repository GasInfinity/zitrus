//! `pdn:d`

pub const service = "pdn:d";

session: ClientSession,

pub fn open(srv: ServiceManager) !Dsp {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pdn: Dsp) void {
    pdn.session.close();
}

pub fn sendControl(pdn: Dsp, enable: bool, reset: bool, reset_registers: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pdn.session, command.Control, .{
        .enable = enable,
        .reset = reset,
        .reset_registers = reset_registers,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| switch (c) {
            .pdn_invalid_arg => horizon.resultBug(c),
            else => horizon.unexpectedResult(c),
        },
    };
}

pub const command = struct {
    /// May fail
    pub const Control = ipc.Command(Id, .control, struct {
        enable: bool,
        reset: bool,
        reset_registers: bool,
    }, struct {});

    pub const Id = enum(u16) {
        control = 0x0001,
    };
};

const Dsp = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
