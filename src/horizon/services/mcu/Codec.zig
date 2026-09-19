//! `mcu::CDC`

pub const service = "mcu::CDC";

session: horizon.Session.Client,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const Initialize = ipc.Command(Id, .initialize, void, void);

    pub const Id = enum(u16) {
        // NOTE: Temporal name as it is called on initialization
        initialize = 0x0001,
    };
};

const I2s = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;
