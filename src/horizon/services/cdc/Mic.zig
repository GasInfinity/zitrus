//! `cdc:MIC`

pub const service = "cdc:MIC";

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

/// Returns `true` if gain changed, `false` if the console is sleeping.
pub fn sendSetGain(mic: Mic, gain: u7) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.SetGain, .{
        .gain = gain,
    }, .{})).cases()) {
        .success => true,
        .failure => |c| switch (c) {
            .cdc_status_changed => false,
            else => horizon.unexpectedResult(c),
        },
    };
}

/// Returns `true` if mic power status changed, `false` if the console is sleeping.
pub fn sendSetPowered(mic: Mic, powered: bool) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.SetPowered, .{
        .powered = powered,
    }, .{})).cases()) {
        .success => true,
        .failure => |c| switch (c) {
            .cdc_status_changed => false,
            else => horizon.unexpectedResult(c),
        },
    };
}

pub const command = struct {
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetGain = ipc.Command(Id, .set_gain, u7, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const GetGain = ipc.Command(Id, .get_gain, void, u7);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetPowered = ipc.Command(Id, .set_powered, bool, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const IsPowered = ipc.Command(Id, .is_powered, void, bool);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetIirFilter = ipc.Command(Id, .set_iir_filter, struct {
        size: u32,
        data: ipc.Mapped(.r),
    }, struct {
        data: ipc.Mapped(.r),
    });

    pub const Id = enum(u16) {
        set_gain = 0x0001,
        get_gain,
        set_powered,
        is_powered,
        set_iir_filter,
    };
};

const Mic = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
