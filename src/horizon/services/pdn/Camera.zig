//! `pdn:c`

pub const service = "pdn:c";

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendSetEnabled(pdn: Camera, enable: bool) !void {
    return switch ((try pdn.send(.SetEnabled, enable, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendIsEnabled(pdn: Camera) !bool {
    return switch ((try pdn.send(.IsEnabled, {}, .{})).cases()) {
        .success => |r| r.value,
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    pub const SetEnabled = ipc.Command(Id, .set_enabled, bool, void);
    pub const IsEnabled = ipc.Command(Id, .is_enabled, void, bool);

    pub const Id = enum(u16) {
        set_enabled = 0x0001,
        is_enabled,
    };
};

const Camera = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
