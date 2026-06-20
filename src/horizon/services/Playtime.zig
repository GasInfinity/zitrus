//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/PTM_Services

// TODO: missing commands and methods

pub const Service = enum(u8) {
    /// Can access:
    /// * `RegisterAlarmClient`
    /// * `SetRtcAlarm`
    /// * `GetRtcAlarm`
    /// * `CancelRtcAlarm`
    /// * `IsAdapterConnected`
    /// * `IsShellOpened`
    /// * `GetBatteryLevel`
    /// * `IsBatteryCharging`
    /// * `IsPedometerCounting`
    /// * `GetStepHistoryEntry`
    /// * `GetStepHistory`
    /// * `GetTotalStepCount`
    /// * `SetPedometerRecordingMode`
    /// * `GetPedometerRecordingMode`
    /// * `GetAllStepHistory`
    user,
    /// Can access all commands `user` can, including:
    /// * `GetPlayHistory`
    /// * `GetPlayHistoryStart`
    /// * `GetPlayHistoryLength`
    /// * `CalculatePlayHistoryStart`
    play_history,
    /// Can access all commands, excluding `GetSystemTime`
    system,
    /// Identical to `system` in terms of access
    system_menu,
    /// Can access all commands `user` can, including `GetSystemTime`
    get_system_time,

    pub fn name(srv: Service) [:0]const u8 {
        return switch (srv) {
            .user => "ptm:u",
            .play_history => "ptm:play",
            .system => "ptm:s",
            .system_menu => "ptm:sysm",
            .get_system_time => "ptm:gets",
        };
    }
};

pub const BatteryLevel = enum(u8) {
    /// 0%
    shutdown,
    /// 1-5%
    very_low,
    /// 6-10%
    low,
    /// 11-30%
    good,
    /// 31-60%
    great,
    /// 61-100%
    high,
    _,
};

session: ClientSession,

pub fn open(srv: ServiceManager, service: Service) !Playtime {
    return .{ .session = try srv.getService(service.name(), .wait) };
}

pub fn close(ptm: Playtime) void {
    ptm.session.close();
}

pub fn sendIsAdapterConnected(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.IsAdapterConnected, .{}, .{})).cases()) {
        .success => |s| s.value.connected,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsShellOpened(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.IsShellOpened, .{}, .{})).cases()) {
        .success => |s| s.value.open,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetBatteryLevel(ptm: Playtime) !BatteryLevel {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.GetBatteryLevel, .{}, .{})).cases()) {
        .success => |s| s.value.level,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsBatteryCharging(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.IsBatteryCharging, .{}, .{})).cases()) {
        .success => |s| s.value.charging,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsPedometerCounting(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.IsPedometerCounting, .{}, .{})).cases()) {
        .success => |s| s.value.counting,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetTotalStepCount(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.GetTotalStepCount, .{}, .{})).cases()) {
        .success => |s| s.value.steps,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsNew3DS(ptm: Playtime) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.IsNew3DS, .{}, .{})).cases()) {
        .success => |s| s.value.is_new_3ds,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendConfigureCpuCache(ptm: Playtime, config: horizon.ControlSystem.ConfigureCpuCache) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ptm.session, command.ConfigureCpuCache, .{ .config = config }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const IsAdapterConnected = ipc.Command(Id, .is_adapter_connected, struct {}, struct {
        connected: bool,
    });
    pub const IsShellOpened = ipc.Command(Id, .is_shell_opened, struct {}, struct {
        open: bool,
    });
    pub const GetBatteryLevel = ipc.Command(Id, .get_battery_level, struct {}, struct {
        level: BatteryLevel,
    });
    pub const IsBatteryCharging = ipc.Command(Id, .is_battery_charging, struct {}, struct {
        charging: bool,
    });
    pub const IsPedometerCounting = ipc.Command(Id, .is_pedometer_counting, struct {}, struct {
        counting: bool,
    });
    pub const GetTotalStepCount = ipc.Command(Id, .get_total_step_count, struct {}, struct {
        steps: u32,
    });
    pub const IsNew3DS = ipc.Command(Id, .is_new_3ds, struct {}, struct {
        is_new_3ds: bool,
    });
    pub const ConfigureCpuCache = ipc.Command(Id, .configure_cpu_cache, struct {
        config: horizon.ControlSystem.ConfigureCpuCache,
    }, struct {});

    pub const Id = enum(u16) {
        register_alarm_client = 0x0001,
        set_rtc_alarm,
        get_rtc_alarm,
        cancel_rtc_alarm,
        is_adapter_connected,
        is_shell_opened,
        get_battery_level,
        is_battery_charging,
        is_pedometer_counting,
        get_step_history_entry,
        get_step_history,
        get_total_step_count,
        set_pedometer_recording_mode,
        get_pedometer_recording_mode,
        get_step_history_all,

        set_rtc_alarm_ex = 0x0401,
        reply_sleep_query,
        notify_sleep_wakeup_preparation_complete,
        set_wakeup_trigger,
        get_awake_reason,
        request_sleep,
        shutdown_async,
        awake,
        reboot_async,
        is_new_3ds,

        set_info_led_pattern = 0x0801,
        set_info_led_pattern_header,
        get_info_led_status,
        set_battery_empty_led_pattern,
        clear_step_history,
        set_step_history,
        get_play_history,
        get_play_history_start,
        get_play_history_length,
        clear_play_history,
        calculate_play_history_start,
        set_user_time,
        invalidate_system_time,
        notify_play_event,
        get_software_closed_flag,
        clear_software_closed_flag,
        get_shell_status,
        is_shutdown_by_battery_empty,
        format_savedata,
        get_legacy_jump_prohibited,
        set_play_history_recording_mode,
        get_system_clock,
        set_system_clock,
        configure_cpu_cache,
    };
};

comptime {
    _ = sendIsAdapterConnected;
    _ = sendIsShellOpened;
    _ = sendGetBatteryLevel;
    _ = sendIsBatteryCharging;
    _ = sendIsPedometerCounting;
    _ = sendGetTotalStepCount;
    _ = sendIsNew3DS;
    _ = sendConfigureCpuCache;
}

const Playtime = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Filesystem = horizon.services.Filesystem;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
