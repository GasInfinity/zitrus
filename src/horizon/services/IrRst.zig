//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/IR_Services#IR_Service_%22ir:rst%22

pub const service = "ir:rst";

session: ClientSession,

pub fn open(srv: ServiceManager) !IrRst {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(rst: IrRst) void {
    rst.session.close();
}

pub const Handles = struct {
    shm: horizon.MemoryBlock,
    ev: horizon.Event,
};

pub fn sendGetHandles(rst: IrRst) !Handles {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.GetIPCHandles, .{}, .{})).cases()) {
        .success => |s| .{
            .shm = @bitCast(@intFromEnum(s.value.response.handles[0])),
            .ev = @bitCast(@intFromEnum(s.value.response.handles[1])),
        },
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInitialize(rst: IrRst, ms_update_period: u32, use_raw_c_stick: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.Initialize, .{ .ms_update_period = ms_update_period, .use_raw_c_stick = use_raw_c_stick }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendShutdown(rst: IrRst) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(rst.session, command.Shutdown, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const GetHandles = ipc.Command(Id, .get_handles, struct {}, struct {
        shm_event: [2]horizon.Object,
    });
    pub const Initialize = ipc.Command(Id, .initialize, struct { ms_update_period: u32, use_raw_c_stick: bool }, struct {});
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {}, struct {});

    pub const Id = enum(u16) {
        get_handles = 0x0001,
        initialize,
        shutdown,
    };
};

const IrRst = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
