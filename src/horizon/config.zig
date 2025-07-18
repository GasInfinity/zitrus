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

pub const KernelConfig = extern struct {
    version: packed struct(u32) { unknown: u8, revision: u8, minor: u8, major: u8 },
    update_flag: u32,
    ns_tid: u64,
    syscore_version: u32,
    environment_info: packed struct(u8) { retail: bool, j_tag_connected: bool, _: u6 },
    unit_info: UnitType,
    previous_firm: PreviousFirmwareType,
    ctr_sdk_version: u32,
    firm_launch_flags: u32,
    app_memory_type: u32,
    app_memory_alloc: u32,
    sys_memory_alloc: u32,
    base_memory_alloc: u32,
    firm_version: packed struct(u32) { unknown: u8, revision: u8, minor: u8, major: u8 },
    firm_syscore_version: u32,
    firm_ctr_sdk_version: u32,
};

pub const HardwareType = enum(u8) { product, devboard, debugger, capture, unknown };

pub const DateTime = extern struct {
    unix: u64,
    last_update_tick: u32,
    _reserved0: u32,
    _reserved1: u32,
    _reserved2: u32,
    _reserved3: u32,
};

pub const WifiLevel = enum(u8) {
    poor,
    low,
    mid,
    great,
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

pub const SharedConfig = extern struct {
    datetime_select: u32,
    hardware: HardwareType,
    mcu_hardware_info: u8,
    datetime_0: DateTime,
    datetime_1: DateTime,
    wifi_mac: [6]u8,
    wifi_link: WifiLevel,
    network: NetworkState,
    slider_state_3d: f32,
    led_state_3d: u8,
    led_state_battery: packed struct(u8) { connected: bool, charging: bool, level: u2, _: u4 },
    done_writing: u8,
    menu_tid: u64,
    active_menu_tid: u64,
    headset_connected: u8,
};

const zitrus = @import("zitrus");
