// https://www.3dbrew.org/wiki/Configuration_Memory#ARM11_Kernel_Config_Fields

pub const UnitType = enum(u8) {
    prod,
    dev,
    debugger,
    firm,
};

pub const PreviousFirmwareType = enum(u8) {
    cold,
    reset_ctr,
    reset_twl,
    reset_ntr,
    reset_agb,
};

pub const MemoryType = enum(u8) {
    pub const default_old: MemoryType = .o64mb;
    pub const default_new: MemoryType = .n124mb_prod;

    o64mb,
    o96mb = 2,
    o80mb,
    o72mb,
    o32mb,

    n124mb_prod = 6,
    n178mb,
    n124mb_dev,
};

pub const Kernel = extern struct {
    pub const Version = packed struct(u32) { unknown: u8, revision: u8, minor: u8, major: u8 };

    version: Version,
    update_flag: u32,
    ns_tid: u64,
    syscore_version: u32,
    environment_info: packed struct(u8) { retail: bool, j_tag_connected: bool, _: u6 },
    unit_info: UnitType,
    previous_firm: PreviousFirmwareType,
    ctr_sdk_version: u32,
    _unused0: u32,
    firm_launch_flags: u32,
    _unused1: [3]u32,
    app_memory_type: MemoryType,
    _unused2: [3]u32,
    application_total_memory: u32,
    system_total_memory: u32,
    base_total_memory: u32,
    _unused3: [5]u32,
    firm_version: Version,
    firm_syscore_version: u32,
    firm_ctr_sdk_version: u32,
};

pub const HardwareType = enum(u8) { product, devboard, debugger, capture, unknown };

pub const SystemTime = extern struct {
    ms_since_january_1900: u64,
    /// in CPU ticks
    last_update: u64,
    /// ticks/s
    system_clock_frequency: u64,
    rtc_drift: i64,

    pub fn current(time: SystemTime) u64 {
        const elapsed_ms = ((horizon.getSystemTick() - time.last_update) * std.time.ms_per_s) / time.system_clock_frequency;
        return time.ms_since_january_1900 + elapsed_ms;
    }
};

pub const WifiLevel = enum(u8) {
    poor,
    low,
    mid,
    great,
    _,
};

pub const NetworkState = enum(u8) {
    _,

    pub fn isInternet(state: NetworkState) bool {
        return @as(u8, @intFromEnum(state)) == 2;
    }

    pub fn isLocal(state: NetworkState) bool {
        return switch (@as(u8, @intFromEnum(state))) {
            3, 4, 6 => true,
            else => false,
        };
    }

    pub fn isDisabled(state: NetworkState) bool {
        return @as(u8, @intFromEnum(state)) == 7;
    }

    pub fn isEnabled(state: NetworkState) bool {
        return !state.isInternet() and !state.isLocal() and !state.isDisabled();
    }
};

pub const Shared = extern struct {
    /// Published by PTM, updated hourly
    system_time_select: std.atomic.Value(hardware.LsbRegister(u1)),
    hardware: HardwareType,
    mcu_hardware_info: u8,
    _unknown0: [26]u8,
    /// Published by PTM, updated hourly
    system_time: [2]SystemTime,
    wifi_mac: [6]u8,
    wifi_link: WifiLevel,
    network: NetworkState,
    _unknown1: [24]u8,
    slider_state_3d: f32,
    led_state_3d: u8,
    led_state_battery: packed struct(u8) { connected: bool, charging: bool, level: u2, _: u4 },
    _unknown2: [26]u8,
    done_writing: u8,
    menu_tid: u64,
    active_menu_tid: u64,
    _unknown3: [24]u8,
    headset_connected: u8,

    pub fn latestSystemTime(shared: *Shared) SystemTime {
        var current = shared.system_time_select.load(.acquire);
        var last: hardware.LsbRegister(u1) = current;

        return time: while (true) {
            const time = shared.system_time[current.value];

            last = current;
            current = shared.system_time_select.load(.acquire);
            if (current == last) break :time time;
        };
    }
};

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const horizon = zitrus.horizon;
