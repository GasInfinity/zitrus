//! `pdn:d`

pub const service = "pdn:d";

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendControl(pdn: Dsp, enable: bool, reset: bool, reset_registers: bool) !void {
    return switch ((try pdn.send(.Control, .{
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
    }, void);

    pub const Id = enum(u16) {
        control = 0x0001,
    };
};

const Dsp = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
