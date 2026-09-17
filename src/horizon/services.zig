//! All `Horizon` services. See `ServiceManager`.

pub const ProcessManagerApplication = @import("services/ProcessManagerApp.zig");
pub const ProcessManagerDebug = @import("services/ProcessManagerDebug.zig");
pub const NUserShell = @import("services/NUserShell.zig");
pub const NUserShellPower = @import("services/NUserShellPower.zig");
pub const Applet = @import("services/Applet.zig");
pub const GraphicsServerGpu = @import("services/GraphicsServerGpu.zig");
pub const GraphicsServerLcd = @import("services/GraphicsServerLcd.zig");
pub const Hid = @import("services/Hid.zig");
pub const Config = @import("services/Config.zig");
pub const Filesystem = @import("services/Filesystem.zig");
pub const ChannelSound = @import("services/ChannelSound.zig");
pub const Dsp = @import("services/Dsp.zig");
pub const IrRst = @import("services/IrRst.zig");
pub const MicU = @import("services/MicU.zig");
/// Deprecated: Use Ptm
pub const MicrophoneUser = MicU;

pub const Ptm = @import("services/Ptm.zig");
/// Deprecated: Use Ptm
pub const Playtime = Ptm;

pub const Process = @import("services/Process.zig");
pub const PxiProcess9 = @import("services/PxiProcess9.zig");
///! Deprecated: Use `soc.User`
pub const SocketUser = soc.User;

pub const Loader = @import("services/Loader.zig");

pub const NetworkDaemon = @import("services/NetworkDaemon.zig");
pub const NetworkManagerInfrastructure = @import("services/NetworkManagerInfrastructure.zig");
pub const NetworkManagerSocket = @import("services/NetworkManagerSocket.zig");

pub const soc = @import("services/soc.zig");
pub const cdc = @import("services/cdc.zig");
pub const pdn = @import("services/pdn.zig");
pub const I2c = @import("services/I2c.zig");
pub const Spi = @import("services/Spi.zig");

pub fn Methods(comptime T: type) type {
    if (!@hasField(T, "session") or @FieldType(T, "session") != horizon.Session.Client) @compileError("Service must wrap a session");
    if (!@hasDecl(T, "command") or !@hasDecl(T.command, "Id")) @compileError("Service must have commands");

    const ipc = horizon.ipc;
    const CmdEnum = std.meta.DeclEnum(T.command);

    return struct {
        pub fn openPort() !T {
            return .{ .session = try .connect(T.port) };
        }

        pub fn openPortWithResult() horizon.Result(T) {
            return switch (horizon.connectToPort(T.port).cases()) {
                .success => |r| .of(r.code, .{ .session = r.value }),
                .failure => |c| .of(c, undefined),
            };
        }

        pub fn openService(srv: horizon.ServiceManager) !T {
            if (horizon.environment.findService(T.service)) |session| return .{ .session = session };
            return .{ .session = try srv.sendGetService(T.service, .wait) };
        }

        pub fn openServiceWithResult(srv: horizon.ServiceManager) horizon.Result(T) {
            if (horizon.environment.findService(T.service)) |session| return .of(.success, .{ .session = session });
            return switch (srv.sendWithResult(.GetService, .init(T.service, .wait), .{}).cases()) {
                .success => |r| .of(r.code, .{ .session = r.value.wrapped }),
                .failure => |c| .of(c, undefined),
            };
        }

        // When multiple services can use more than one command
        pub fn openServiceMulti(srv: horizon.ServiceManager, service: T.Service) !T {
            if (horizon.environment.findService(service.name())) |session| return .{ .session = session };
            return .{ .session = try srv.sendGetService(service.name(), .wait) };
        }

        pub fn openServiceMultiWithResult(srv: horizon.ServiceManager, service: T.Service) horizon.Result(T) {
            if (horizon.environment.findService(service.name())) |session| return .of(.success, .{ .session = session });
            return switch ((srv.sendWithResult(.GetService, .init(service.name(), .wait), .{})).cases()) {
                .success => |r| .of(r.code, .{ .session = r.value.wrapped }),
                .failure => |c| .of(c, undefined),
            };
        }

        pub fn close(service: T) void {
            service.session.close();
        }

        pub fn send(service: T, comptime cmd: CmdEnum, req: Cmd(cmd).Request, static_output: Cmd(cmd).RequestStaticOutput) ipc.Buffer.SendRequestError!horizon.Result(Cmd(cmd).Response) {
            return horizon.tls.get().ipc.sendRequest(service.session, Cmd(cmd), req, static_output);
        }

        pub fn sendWithResult(service: T, comptime cmd: CmdEnum, req: Cmd(cmd).Request, static_output: Cmd(cmd).RequestStaticOutput) horizon.Result(Cmd(cmd).Response) {
            return horizon.tls.get().ipc.sendRequestWithResult(service.session, Cmd(cmd), req, static_output);
        }

        fn Cmd(cmd: CmdEnum) type {
            return @field(T.command, @tagName(cmd));
        }
    };
}

comptime {
    _ = ProcessManagerApplication;
    _ = ProcessManagerDebug;
    _ = NUserShell;
    _ = NUserShellPower;
    _ = Applet;
    _ = GraphicsServerGpu;
    _ = GraphicsServerLcd;
    _ = Hid;
    _ = Config;
    _ = Filesystem;
    _ = ChannelSound;
    _ = Dsp;
    _ = IrRst;
    _ = Playtime;
    _ = Process;
    _ = PxiProcess9;
    _ = SocketUser;
    _ = Loader;
    _ = NetworkDaemon;
    _ = NetworkManagerInfrastructure;
    _ = NetworkManagerSocket;

    _ = I2c;
    _ = Spi;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
