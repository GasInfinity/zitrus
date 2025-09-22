//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Manager_Services

pub const service = "pm:app";

pub const LaunchFlags = packed struct(u32) {
    normal_application: bool = true,
    load_exheader_dependencies: bool = true,
    publish_termination_srv_notification: bool = false,
    queue_execution: bool = false,
    notification_offset: u4 = 0,
    _unused0: u8,
    use_update_title: bool = false,
    _unused1: u15 = 0,
};

session: ClientSession,

pub fn open(srv: ServiceManager) !PmApp {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(pma: PmApp) void {
    pma.session.close();
}

pub const command = struct {
    pub const Id = enum(u16) {
        launch_title = 0x0001,
        launch_firm,
        terminate_application,
        terminate_title,
        terminate_process,
        prepare_for_reboot,
        get_firm_launch_parameters,
        get_title_exheader_flags,
        set_firm_launch_parameters,
        set_app_resource_limit,
        get_app_resource_limit,
        unregister_process,
        launch_title_update,
    };
};

const PmApp = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
