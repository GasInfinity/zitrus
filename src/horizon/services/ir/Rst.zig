//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/IR_Services#IR_Service_%22ir:rst%22

pub const Input = @import("Rst/Input.zig");

pub const service = "ir:rst";

pub const Pad = extern struct {
    pub const State = packed struct(u32) {
        _unused0: u14 = 0,
        zl: bool,
        zr: bool,
        _unused1: u8 = 0,
        c_stick_right: bool,
        c_stick_left: bool,
        c_stick_up: bool,
        c_stick_down: bool,
        _unused2: u4 = 0,
    };

    pub const CStickState = extern struct { x: i16, y: i16 };
    pub const Entry = extern struct { current: State, pressed: State, released: State, c_stick: CStickState };

    tick: u64,
    last_tick: u64,
    index: u32,
    _pad0: u32 = 0,
    entries: [8]Entry,
};

pub const Shared = extern struct {
    pad: Pad,
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const Handles = struct {
    shm: horizon.MemoryBlock,
    ev: horizon.Event,

    pub fn close(handles: Handles) void {
        handles.shm.close();
        handles.ev.close();
    }
};

pub fn sendGetHandles(rst: Rst) !Handles {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.GetHandles, {}, .{})).cases()) {
        .success => |s| s.value.wrapped,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInitialize(rst: Rst, ms_update_period: u32, use_raw_c_stick: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.Initialize, .{ .ms_update_period = ms_update_period, .use_raw_c_stick = use_raw_c_stick }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendShutdown(rst: Rst) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.Shutdown, {}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const GetHandles = ipc.Command(Id, .get_handles, void, ipc.HandleArray(Handles));
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        ms_update_period: u32,
        use_raw_c_stick: bool,
    }, void);
    pub const Shutdown = ipc.Command(Id, .shutdown, void, void);

    pub const Id = enum(u16) {
        get_handles = 0x0001,
        initialize,
        shutdown,
    };
};

const Rst = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
