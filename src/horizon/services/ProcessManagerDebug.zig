//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Manager_Services

pub const service = "pm:dbg";

session: ClientSession,

pub fn open(srv: ServiceManager) !PmDbg {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pmd: PmDbg) void {
    pmd.session.close();
}

pub fn sendLaunchAppDebug(pmd: PmDbg, program_info: Filesystem.ProgramInfo, launch_flags: PmApp.LaunchFlags) !Debug {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pmd.session, command.LaunchAppDebug, .{
        .program_info = program_info,
        .launch_flags = launch_flags,
    }, .{})).cases()) {
        .success => |s| s.value.app_debug,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendLaunchApp(pmd: PmDbg, program_info: Filesystem.ProgramInfo, launch_flags: PmApp.LaunchFlags) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pmd.session, command.LaunchApp, .{
        .program_info = program_info,
        .launch_flags = launch_flags,
    }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRunQueuedProcess(pmd: PmDbg) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(pmd.session, command.RunQueuedProcess, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const LaunchAppDebug = ipc.Command(Id, .launch_app_debug, struct { program_info: Filesystem.ProgramInfo, launch_flags: PmApp.LaunchFlags }, struct { _: u32, app_debug: Debug });
    pub const LaunchApp = ipc.Command(Id, .launch_app, struct { program_info: Filesystem.ProgramInfo, launch_flags: PmApp.LaunchFlags }, struct {});
    pub const RunQueuedProcess = ipc.Command(Id, .run_queued_process, struct {}, struct { app_debug: Debug });

    pub const Id = enum(u16) {
        launch_app_debug = 0x0001,
        launch_app,
        run_queued_process,
    };
};

const PmDbg = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Filesystem = horizon.services.Filesystem;
const PmApp = horizon.services.ProcessManagerApplication;

const ClientSession = horizon.ClientSession;
const Debug = horizon.Debug;
const ServiceManager = horizon.ServiceManager;
