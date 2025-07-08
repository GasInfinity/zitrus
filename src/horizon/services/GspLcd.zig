// TODO: gsp::Lcd

const service_name = "gsp::Lcd";

pub const command = struct {
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
