//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/GSP_Services#GSP_service_%22gsp::Lcd%22

// TODO: Only missing methods

pub const service = "gsp::Lcd";

pub const Target = enum(u8) {
    top = 1,
    bottom,
    both,
};

pub const Brightness = enum(u8) {
    pub const Level = enum(u8) { @"1" = 0, @"2", @"3", @"4", @"5" };
    pub const min: Brightness = @enumFromInt(0x10);
    pub const max: Brightness = @enumFromInt(0xAC);

    _,
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const EnableAbl = ipc.Command(Id, .enable_abl, Target, void);
    pub const DisableAbl = ipc.Command(Id, .disable_abl, Target, void);
    pub const SetRsLut = ipc.Command(Id, .set_rs_lut, struct { screen: Target, level: u8 }, void);
    pub const SetRsParams = ipc.Command(Id, .set_rs_params, struct { screen: Target, min: u32, max: u32 }, void);
    pub const SetAblArea = ipc.Command(Id, .set_abl_area, struct { screen: Target, x: u32, width: u32, y: u32, height: u32 }, void);
    pub const SetInertia = ipc.Command(Id, .set_inertia, struct { screen: Target, inertia: u32 }, void);
    pub const SetDitherMode = ipc.Command(Id, .set_dither_mode, struct { screen: Target, unk0: bool, unk1: bool }, void);
    pub const SetDitherParams = ipc.Command(Id, .set_dither_params, struct { screen: Target, unk0: u32, unk1: u32, unk2: u32, unk3: u32 }, struct {});
    pub const SetBrightnessRaw = ipc.Command(Id, .set_brightness_raw, struct { screen: Target, value: Brightness }, void);
    pub const SetBrightness = ipc.Command(Id, .set_brightness, struct { screen: Target, level: Brightness.Level }, void);
    pub const ReloadConfig = ipc.Command(Id, .reload_config, struct { screen: Target }, void);
    pub const RestoreConfig = ipc.Command(Id, .restore_config, struct { screen: Target }, void);
    pub const GetPowerState = ipc.Command(Id, .get_power_state, void, struct { flags: u8 });
    pub const PowerOnAllBacklights = ipc.Command(Id, .power_on_all_backlights, void, void);
    pub const PowerOffAllBacklights = ipc.Command(Id, .power_off_all_backlights, void, void);
    pub const PowerOnBacklight = ipc.Command(Id, .power_on_backlight, Target, void);
    pub const PowerOffBacklight = ipc.Command(Id, .power_off_backlight, Target, void);
    pub const SetLedForceOff = ipc.Command(Id, .set_led_force_off, bool, void);
    pub const GetVendor = ipc.Command(Id, .get_vendor, void, u8);
    pub const GetBrightness = ipc.Command(Id, .get_brightness, Target, Brightness);

    pub const Id = enum(u16) {
        enable_abl = 0x0001,
        disable_abl,
        set_rs_lut,
        set_rs_params,
        set_abl_area,
        _unknown0,
        set_inertia,
        set_dither_mode,
        set_dither_params,
        set_brightness_raw,
        set_brightness,
        reload_config,
        restore_config,
        get_power_state,
        power_on_all_backlights,
        power_off_all_backlights,
        power_on_backlight,
        power_off_backlight,
        set_led_force_off,
        get_vendor,
        get_brightness,
    };
};

const Lcd = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
