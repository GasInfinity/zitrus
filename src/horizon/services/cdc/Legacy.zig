//! `cdc:LGY`

pub const service = "cdc:LGY";

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

// NOTE: Temporary names, as this has never been named.

pub const command = struct {
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const Initialize = ipc.Command(Id, .initialize, void, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetTouch3ds = ipc.Command(Id, .set_touch_3ds, bool, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetMicBias = ipc.Command(Id, .set_mic_bias, bool, void);

    pub const Id = enum(u16) {
        initialize = 0x0001,
        set_touch_3ds,
        set_mic_bias,
    };
};

const Legacy = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
