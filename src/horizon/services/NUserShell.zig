const service_name = "ns:s";

session: ClientSession,

pub fn open(srv: ServiceManager) !NUserShell {
    return .{ .session = try srv.getService(service_name, .wait) };
}

pub fn close(ns: NUserShell) void {
    ns.session.close();
}

pub const RebootSystemOptions = union(enum(u1)) {
    pub const LaunchOptions = struct { program: Filesystem.ProgramInfo, memory_type: config.MemoryType };

    none,
    launch: LaunchOptions,
};

pub fn sendRebootSystem(ns: NUserShell, options: RebootSystemOptions) !void {
    const launch_on_boot: bool, const program_info: Filesystem.ProgramInfo, const memory_type: config.MemoryType = switch (options) {
        .none => .{ false, undefined, undefined },
        .launch => |opt| .{ true, opt.program, opt.memory_type },
    };

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ns.session, command.RebootSystem, .{ .launch_title_on_boot = launch_on_boot, .launched_program = program_info, .new_memory_type = memory_type }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    // TODO: implement the missing commands
    pub const LaunchFirm = ipc.Command(Id, .launch_firm, struct { title_id: u64 }, struct {});
    pub const ShutdownAsync = ipc.Command(Id, .shutdown_async, struct {}, struct {});
    pub const RebootSystem = ipc.Command(Id, .reboot_system, struct { launch_title_on_boot: bool, launched_program_info: Filesystem.ProgramInfo, new_mem_type: config.MemoryType }, struct {});
    pub const TerminateTitle = ipc.Command(Id, .terminate_title, struct { program_id: u64, timeout: u64 }, struct {});
    pub const SetApplicationCpuTimeLimit = ipc.Command(Id, .set_application_cpu_time_limit, struct { must_be_one: u32 = 1, percentage: u32, lock_percentage: bool }, struct {});
    pub const LaunchApplication = ipc.Command(Id, .launch_application, struct { program_info: Filesystem.ProgramInfo, flags: ProcessManagerApplication.LaunchFlags }, struct {});
    pub const RebootSystemClean = ipc.Command(Id, .reboot_system_clean, struct {}, struct {});

    pub const Id = enum(u16) {
        launch_firm = 0x0001,
        launch_title,
        terminate_application,
        terminate_process,
        launch_application_firm,
        set_wireless_reboot_info,
        card_update_initialize,
        card_update_shutdown,
        unknown_gamecard_related0,
        unknown_gamecard_related1,
        unknown_gamecard_related2,
        unknown_gamecard_related3,
        set_twl_banner_hmac,
        shutdown_async,
        unknown_applet_utility,
        reboot_system,
        terminate_title,
        set_application_cpu_time_limit,
        unknown0,
        unknown1,
        launch_application,
        reboot_system_clean,
    };
};

const NUserShell = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;
const config = horizon.config;

const ClientSession = horizon.ClientSession;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;

const ServiceManager = horizon.ServiceManager;
const Filesystem = horizon.services.Filesystem;
const ProcessManagerApplication = horizon.services.ProcessManagerApplication;
