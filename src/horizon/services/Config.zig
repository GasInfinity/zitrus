// https://www.3dbrew.org/wiki/Config_Services
const service_names = [_][]const u8{ "cfg:i", "cfg:s", "cfg:u" };

pub const Error = Session.RequestError;

pub const SystemModel = enum(u8) {
    ctr,
    spr,
    ktr,
    ftr,
    red,
    jan,

    pub fn description(model: SystemModel) [:0]const u8 {
        return switch(model) {
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
    twn
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

session: Session,

pub fn init(srv: ServiceManager) Error!Config {
    var last_error: Error = undefined;
    const config_session = used: for (service_names) |service_name| {
        const config_session = srv.getService(service_name, true) catch |err| {
            last_error = err;
            continue;
        };

        break :used config_session;
    } else return last_error;

    return Config{ .session = config_session };
}

pub fn deinit(config: *Config) void {
    config.session.deinit();
    config.* = undefined;
}

pub fn sendGetRegion(cfg: Config) Error!Region {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.get_region, .{}, .{});

    try cfg.session.sendRequest();
    return @enumFromInt(data.ipc.parameters[1]);
}

pub fn sendIsCoppacsSupported(cfg: Config) Error!bool {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.is_coppacs_supported, .{}, .{});

    try cfg.session.sendRequest();
    return data.ipc.parameters[1] != 0;
}

pub fn sendGetSystemModel(cfg: Config) Error!SystemModel {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.get_system_model, .{}, .{});

    try cfg.session.sendRequest();
    return @enumFromInt(data.ipc.parameters[1]);
}

pub fn sendIsModelNintendo2DS(cfg: Config) Error!bool {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.is_model_nintendo_2ds, .{}, .{});

    try cfg.session.sendRequest();
    return data.ipc.parameters[1] != 0;
}

pub fn sendGetCountryCodeString(cfg: Config, id: Country) Error![2]u8 {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.get_country_code_string, .{ @as(u32, @intFromEnum(id)) }, .{});

    try cfg.session.sendRequest();
    return .{ @truncate(data.ipc.parameters[1]), @truncate(data.ipc.parameters[1] >> 8) };
}

pub fn sendGetCountryCodeId(cfg: Config, string: *const [2]u8) Error!Country {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.get_country_code_id, .{ @as(u32, @as(u16, string.*)) }, .{});

    try cfg.session.sendRequest();
    return @enumFromInt(data.ipc.parameters[1]);
}

pub const Command = enum(u16) {
    get_config = 0x0001,
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

    get_config_info_blk8 = 0x0401,
    get_config_info_blk4,
    update_config_nand_savegame,
    get_local_friend_code_seed_data,
    get_local_friend_code_seed,
    s_get_region,
    secureinfo_get_byte_0x101,
    get_serial_no,
    update_config_blk_0x00040003,
    s_unknown_0,
    s_unknown_1,
    s_unknown_2,
    set_uuid_clock_sequence,
    get_uuid_clock_sequence,
    clear_parental_controls,

    pub inline fn normalParameters(cmd: Command) u6 {
        return switch (cmd) {
            .get_config => 2,
            .get_region => 0,
            .get_transferable_id => 1,
            .is_coppacs_supported => 0,
            .get_system_model => 0,
            .is_model_nintendo_2ds => 0,
            .write_unknown_0x00160000 => 1,
            .translate_country_info => 2,
            .get_country_code_string => 1,
            .get_country_code_id => 1,
            .is_fangate_supported => 0,

            else => @compileError("Not implemented"),
        };
    }

    pub inline fn translateParameters(cmd: Command) u6 {
        return switch (cmd) {
            .get_config => 2,
            .get_region => 0,
            .get_transferable_id => 0,
            .is_coppacs_supported => 0,
            .get_system_model => 0,
            .is_model_nintendo_2ds => 0,
            .write_unknown_0x00160000 => 0,
            .translate_country_info => 0,
            .get_country_code_string => 0,
            .get_country_code_id => 0,
            .is_fangate_supported => 0,

            else => @compileError("Not implemented"),
        };
    }
};

const Config = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.ResultCode;
const Session = horizon.Session;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;

const ServiceManager = zitrus.horizon.ServiceManager;
