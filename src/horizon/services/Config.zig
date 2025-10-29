//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Config_Services

// TODO: Missing methods / commands

const service_names = [_][]const u8{ "cfg:i", "cfg:s", "cfg:u" };

pub const Service = enum(u2) {
    user,
    system,
    internal,

    pub fn name(srv: Service) [:0]const u8 {
        return switch (srv) {
            .user => "cfg:u",
            .system => "cfg:s",
            .internal => "cfg:i",
        };
    }
};

pub const SystemModel = enum(u8) {
    ctr,
    spr,
    ktr,
    ftr,
    red,
    jan,

    pub fn description(model: SystemModel) [:0]const u8 {
        return switch (model) {
            .ctr => "Nintendo 3DS",
            .spr => "Nintendo 3DS XL",
            .ktr => "New Nintendo 3DS",
            .ftr => "Nintendo 2DS",
            .red => "New Nintendo 3DS XL",
            .jan => "New Nintendo 2DS XL",
        };
    }
};

pub const Region = enum(u8) {
    jpn,
    usa,
    eur,
    aus,
    chn,
    kor,
    twn,
};

// https://www.3dbrew.org/wiki/Country_Code_List
pub const Country = enum(u16) {
    jp = 1,
    ai = 8,
    ag = 9,
    ar,
    aw,
    bs,
    bb,
    bz,
    bo,
    br,
    vg,
    ca,
    ky,
    cl,
    co,
    cr,
    dm,
    do,
    ec,
    sv,
    gf,
    gd,
    gp,
    gt,
    gy,
    ht,
    hn,
    jm,
    mq,
    mx,
    ms,
    an,
    ni,
    pa,
    py,
    pe,
    kn,
    lc,
    vc,
    sr,
    tt,
    tc,
    us,
    uy,
    vi,
    ve,

    al = 64,
    au,
    at,
    be,
    ba,
    bw,
    bg,
    hr,
    cy,
    cz,
    dk,
    ee,
    fi,
    fr,
    de,
    gr,
    hu,
    is,
    ie,
    it,
    lv,
    ls,
    li,
    lt,
    lu,
    mk,
    mt,
    me,
    mz,
    na,
    nl,
    nz,
    no,
    pl,
    pt,
    ro,
    ru,
    rs,
    sk,
    si,
    za,
    es,
    sz,
    tr,
    gb,
    zm,
    zw,
    az,
    mr,
    ml,
    ne,
    td,
    sd,
    er,
    dj,
    so,
    ad,
    gi,
    gg,
    im,
    je,
    mc,
    tw,

    kr = 136,
    hk,
    mo,
    id,
    sg,
    th,
    ph,
    my,
    cn,
    ae,
    in,
    eg,
    om,
    qa,
    kw,
    sa,
    sy,
    bh,
    jo,
    sm,
    va,
    bm,
};

pub const Language = enum(u8) {
    jp,
    en,
    fr,
    de,
    it,
    es,
    zh,
    ko,
    nl,
    pt,
    ru,
    tw,
};

pub const Birthday = extern struct {
    month: u8,
    day: u8,
};

pub const CountryInfo = extern struct { _unknown0: [2]u8 = @splat(0), province_code: u8, country_code: u8 };

pub const UserName = extern struct {
    name: [11]u16,
    inappropiate: u16,
    inappropiate_version: u32,
};

pub const ParentalControls = extern struct {
    pub const EmailQuestion = extern struct {
        email_registered: bool,
        address: [0x101]u8,
        custom_secret_question: [52]u16,
    };

    pub const Twl = extern struct {
        _unknown0: [13]u8,
        pin: [4]u8,
        secret_answer: [32]u16,
    };

    pub const RestrictionMask = packed struct(u32) {
        enable: bool,
        internet_browser: bool,
        enable_3d: bool,
        share_data: bool,
        online_interaction: bool,
        streetpass: bool,
        friend_registration: bool,
        ds_download_play: bool,
        shopping_services: bool,
        view_videos: bool,
        view_miiverse: bool,
        post_miiverse: bool,
        _unused0: u19,
        coppa: bool,
    };

    restrictions: RestrictionMask,
    _unknown0: u32 = 0,
    rating: u8,
    maximum_allowed_age: u8,
    secret_question_type: u8, // TODO: enum
    _unknown1: u8 = 0,
    parental_pin: [8]u8,
    secret_answer: [34]u16,
};

pub const CountryName = extern struct { value: [16][64]u16 };

pub const StateName = extern struct { value: [16][64]u16 };

pub const Coordinates = packed struct(u32) {
    latitude: i16,
    longitude: i16,
};

pub const Block = enum(u32) {
    pub const AccessFlags = packed struct(u8) {
        pub const u = .{ .user_readable = true, .system_writable = true, .system_readable = true };
        pub const s = .{ .user_readable = false, .system_writable = true, .system_readable = true };

        _unused0: u1 = 0,
        user_readable: bool,
        system_writable: bool,
        system_readable: bool,
        _unused1: u4 = 0,
    };

    version = 0x00000000,
    rtc = 0x00010000,
    codec = 0x00020000,

    leap_year_counter = 0x00030000,
    user_time_offset,
    settings_time_offset,

    touch_calibration = 0x00040000,
    analog_stick_calibration,
    gyroscope,
    accelerometer,
    cstick_calibration,

    screen_flicker = 0x00050000,
    backlight_controls,
    backlight_pwm,
    power_saving_mode_calibration,
    power_saving_mode_calibration_legacy,
    stereo_display_settings,
    switching_delay_3d,
    unknown0,
    power_saving_mode_extra,
    new_3ds_backlight_control,

    unknown1 = 0x00060000,

    filters_3d = 0x00070000,
    sound_output_mode = 0x00070001,
    microphone_echo_cancellation_params,

    wifi_slot_0 = 0x00080000,
    wifi_slot_1,
    wifi_slot_2,

    console_unique_id = 0x00090000,
    console_unique_id_1,
    random,

    user_name = 0x000A0000,
    birthday,
    language,

    country_info = 0x000B0000,
    country_name,
    state_name,
    coordinates,

    parental_controls = 0x000C0000,
    coppacs_restriction_data,
    parental_controls_email_question,

    last_agreed_eula = 0x000D0000,

    spotpass_related = 0x000E0000,

    debug_configuration = 0x000F0000,

    unknown2 = 0x000F0001,
    home_menu_button_disable = 0x000F0003,
    system_model_unknown,
    network_updates_enabled,
    http_device_token,

    twl_eula_info = 0x00100000,
    twl_parental_control,
    twl_country_code,
    twl_unique_id,

    system_setup_required = 0x00110000,
    menu_to_launch,

    volume_slider_bounds = 0x00120000,

    debug_mode_enabled = 0x00130000,

    clock_sequence = 0x00150000,
    unknown3,
    nfs_environment,

    unknown4 = 0x00160000,

    miiverse_access_key = 0x00170000,

    qtm_ir_led = 0x00180000,
    qtm_calibration_data,

    nfc_unknown = 0x00190000,

    pub fn Data(comptime block: Block) type {
        return switch (block) {
            .version => u16,
            .rtc => u8,
            .codec => @compileError("TODO"),
            .leap_year_counter => u8,
            .user_time_offset => u64,
            .settings_time_offset => u64,

            .user_name => UserName,
            .birthday => Birthday,
            .language => Language,
            .country_info => CountryInfo,
            .country_name => CountryName,
            .state_name => StateName,
            .coordinates => Coordinates,

            .home_menu_button_disable => bool,
            .parental_controls => ParentalControls,
            .parental_controls_email_question => ParentalControls.EmailQuestion,
            else => @compileError("Not implemented"),
        };
    }
};

session: ClientSession,

pub fn open(service: Service, srv: ServiceManager) !Config {
    return .{ .session = try srv.getService(service.name(), .wait) };
}

pub fn close(config: Config) void {
    config.session.close();
}

pub fn getConfigUser(cfg: Config, comptime block: Block) !block.Data() {
    var value: block.Data() = undefined;
    try cfg.sendGetConfigUser(block, std.mem.asBytes(&value));
    return value;
}

pub fn sendGetConfigUser(cfg: Config, block: Block, output: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.GetConfigUser, .{ .size = output.len, .blk = block, .output = .mapped(output) }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetRegion(cfg: Config) !Region {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.GetRegion, .{}, .{})).cases()) {
        .success => |s| s.value.region,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsCoppacsSupported(cfg: Config) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.IsCoppacsSupported, .{}, .{})).cases()) {
        .success => |s| s.value.supported,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetSystemModel(cfg: Config) !SystemModel {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.GetSystemModel, .{}, .{})).cases()) {
        .success => |s| s.value.model,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendIsModelNintendo2ds(cfg: Config) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.IsModelNintendo2ds, .{}, .{})).cases()) {
        .success => |s| s.value.value,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetCountryCodeString(cfg: Config, id: Country) ![2]u8 {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.GetCountryCodeString, .{ .id = id }, .{})).cases()) {
        .success => |s| s.value.str,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetCountryCodeId(cfg: Config, string: [2]u8) !Country {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(cfg.session, command.GetCountryCodeId, .{ .str = string }, .{})).cases()) {
        .success => |s| s.value.id,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const GetConfigUser = ipc.Command(Id, .get_config_user, struct {
        size: usize,
        blk: Block,
        output: ipc.Mapped(.w),
    }, struct { output: ipc.Mapped(.w) });
    pub const GetRegion = ipc.Command(Id, .get_region, struct {}, struct { region: Region });
    pub const GetTransferableId = ipc.Command(Id, .get_transferable_id, struct { salt: u20 }, struct { hash: u64 });
    pub const IsCoppacsSupported = ipc.Command(Id, .is_coppacs_supported, struct {}, struct { supported: bool });
    pub const GetSystemModel = ipc.Command(Id, .get_system_model, struct {}, struct { model: SystemModel });
    pub const IsModelNintendo2ds = ipc.Command(Id, .is_model_nintendo_2ds, struct {}, struct { value: bool });
    pub const GetCountryCodeString = ipc.Command(Id, .get_country_code_string, struct { id: Country }, struct { str: [2]u8 });
    pub const GetCountryCodeId = ipc.Command(Id, .get_country_code_id, struct { str: [2]u8 }, struct { id: Country });

    pub const Id = enum(u16) {
        get_config_user = 0x0001,
        get_region,
        get_transferable_id,
        is_coppacs_supported,
        get_system_model,
        is_model_nintendo_2ds,
        write_unknown_0x00160000,
        translate_country_info,
        get_country_code_string,
        get_country_code_id,
        is_fangate_supported,

        get_config_system = 0x0401,
        set_config_system,
        update_config_nand_savegame,
        get_local_friend_code_seed_data,
        get_local_friend_code_seed,
        get_region_system,
        get_byte_0x101_system,
        get_serial_no_system,
        update_config_blk_0x00040003,
        unknown_0_system,
        unknown_1_system,
        unknown_2_system,
        set_uuid_clock_sequence,
        get_uuid_clock_sequence,
        clear_parental_controls,

        get_config_internal = 0x0801,
        set_config_internal,
        update_config_nand_savefile,
        create_config_info,
        delete_config_nand_savefile,
        format_config,
        nop0,
        updates_version_codec,
        updates_hwcal,
        reset_analog_stick_calibration_param,
        set_get_local_friend_code_seed_data,
        set_local_friend_code_seed_signature,
        delete_create_nand_local_friend_code_seed,
        verify_sig_local_friend_code_seed,
        get_local_friend_code_seed_data_internal,
        get_local_friend_code_seed_internal,
        set_secure_info,
        delete_create_nand_secure_info,
        verify_sig_secure_info,
        secure_info_get_data,
        secure_info_get_signature,
        get_region_internal,
        get_byte_0x101_internal,
        get_serial_no_internal,
    };
};

const Config = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
