pub const service = "ndm:u";

pub const Daemon = enum(u32) {
    pub const Mask = packed struct(u32) {
        cec: bool = false,
        boss: bool = false,
        nim: bool = false,
        friends: bool = false,
        _: u28 = 0,
    };

    pub const Status = enum(u32) {
        busy,
        idle,
        suspending,
        suspended,
    };

    cec,
    boss,
    nim,
    friends,
};

pub const State = enum(u32) {
    pub const Exclusive = enum(u32) {
        none,
        infrastructure,
        local_communications,
        streetpass,
        streetpass_data,
    };

    initial,
    suspended,
    infrastructure_connecting,
    infrastructure_connected,
    infrastructure_working,
    infrastructure_suspending,
    infrastructure_force_suspending,
    infrastructure_disconnecting,
    infrastructure_force_disconnecting,
    cec_working,
    cec_force_suspending,
    cec_suspending,
};

session: ClientSession,

pub fn open(srv: ServiceManager) !NetworkDaemon {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(ndm: NetworkDaemon) void {
    ndm.session.close();
}

pub const command = struct {
    pub const Id = enum(u16) {
        enter_exclusive_state = 0x0001,
        leave_exclusive_state,
        get_exclusive_state,
        lock_state,
        unlock_state,
        suspend_daemons,
        resume_daemons,
        suspend_scheduler,
        resume_scheduler,
        get_current_state,
        get_target_state,
        get_status = 0x000D,
        get_daemon_disable_count,
        get_scheduler_disable_count,
        set_scan_interval,
        get_scan_interval,
        set_retry_interval,
        get_retry_interval,
        override_default_daemons,
        reset_default_daemons,
        get_default_daemons,
        clear_half_awake_mac_filter,
    };
};

const NetworkDaemon = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
