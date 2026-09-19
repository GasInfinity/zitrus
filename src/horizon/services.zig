//! All `Horizon` services. See `ServiceManager`.

pub const ProcessManagerApplication = @import("services/ProcessManagerApp.zig");
pub const ProcessManagerDebug = @import("services/ProcessManagerDebug.zig");
pub const NUserShell = @import("services/NUserShell.zig");
pub const NUserShellPower = @import("services/NUserShellPower.zig");
pub const Applet = @import("services/Applet.zig");
/// Deprecated: use `gsp.Gpu`
pub const GraphicsServerGpu = gsp.Gpu;
/// Deprecated: use `gsp.Lcd`
pub const GraphicsServerLcd = gsp.Lcd;
pub const Hid = @import("services/Hid.zig");
pub const Cfg = @import("services/Cfg.zig");
/// Deprecated: use `Cfg`
pub const Config = Cfg;
pub const Filesystem = @import("services/Filesystem.zig");
pub const CSnd = @import("services/CSnd.zig");
/// Deprecated: use `CSnd`
pub const ChannelSound = CSnd;
pub const Dsp = @import("services/Dsp.zig");
/// Deprecated: use `ir.Rst`
pub const IrRst = ir.Rst;
pub const MicU = @import("services/MicU.zig");
/// Deprecated: Use MicU
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

pub const gsp = @import("services/gsp.zig");
pub const ir = @import("services/ir.zig");
pub const soc = @import("services/soc.zig");
pub const cdc = @import("services/cdc.zig");
pub const pdn = @import("services/pdn.zig");
pub const mcu = @import("services/mcu.zig");
pub const I2c = @import("services/I2c.zig");
pub const Spi = @import("services/Spi.zig");
pub const Gpio = @import("services/Gpio.zig");

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
            return .{ .session = try srv.sendGetService(T.service, false) };
        }

        pub fn openServiceWithResult(srv: horizon.ServiceManager) horizon.Result(T) {
            if (horizon.environment.findService(T.service)) |session| return .of(.success, .{ .session = session });
            return switch (srv.sendWithResult(.GetService, .init(T.service, false), .{}).cases()) {
                .success => |r| .of(r.code, .{ .session = r.value.wrapped }),
                .failure => |c| .of(c, undefined),
            };
        }

        // When multiple services can use more than one command
        pub fn openServiceMulti(srv: horizon.ServiceManager, service: T.Service) !T {
            if (horizon.environment.findService(service.name())) |session| return .{ .session = session };
            return .{ .session = try srv.sendGetService(service.name(), false) };
        }

        pub fn openServiceMultiWithResult(srv: horizon.ServiceManager, service: T.Service) horizon.Result(T) {
            if (horizon.environment.findService(service.name())) |session| return .of(.success, .{ .session = session });
            return switch ((srv.sendWithResult(.GetService, .init(service.name(), false), .{})).cases()) {
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
    _ = gsp;
    _ = Hid;
    _ = Config;
    _ = Filesystem;
    _ = ChannelSound;
    _ = Dsp;
    _ = IrRst;
    _ = Playtime;
    _ = Process;
    _ = PxiProcess9;
    _ = soc;
    _ = Loader;
    _ = NetworkDaemon;
    _ = NetworkManagerInfrastructure;
    _ = NetworkManagerSocket;

    _ = ir;
    _ = I2c;
    _ = Spi;
    _ = cdc;
    _ = pdn;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
