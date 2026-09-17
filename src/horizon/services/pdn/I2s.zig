//! `pdn:i`

pub const service = "pdn:i";

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendSetEnabled1(pdn: I2s, enable: bool) !void {
    return switch ((try pdn.send(.SetEnabled1, enable, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendSetEnabled2(pdn: I2s, enable: bool) !void {
    return switch ((try pdn.send(.SetEnabled2, enable, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    pub const SetEnabled1 = ipc.Command(Id, .set_enabled_1, bool, void);
    pub const SetEnabled2 = ipc.Command(Id, .set_enabled_2, bool, void);

    pub const Id = enum(u16) {
        set_enabled_1 = 0x0001,
        set_enabled_2,
    };
};

const I2s = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
