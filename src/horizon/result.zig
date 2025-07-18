pub const ResultLevel = enum(u5) {
    success,
    info,
    status,
    temporary,
    permanent,
    usage,
    reinitialize,
    reset,
    fatal,
    _,
};

pub const ResultSummary = enum(u6) {
    success,
    nop,
    would_block,
    out_of_resource,
    not_found,
    invalid_state,
    not_supported,
    invalid_arg,
    wrong_arg,
    canceled,
    status_changed,
    internal,
    invalid_result_value = 63,
    _,
};

pub const ResultModule = enum(u8) {
    common,
    kernel,
    util,
    file_server,
    loader_server,
    tcb,
    os,
    dbg,
    dmnt,
    pdn,
    gsp,
    i2c,
    gpio,
    dd,
    codec,
    spi,
    pxi,
    fs,
    di,
    hid,
    cam,
    pi,
    pm,
    pm_low,
    fsi,
    srv,
    ndm,
    nwm,
    soc,
    ldr,
    acc,
    romfs,
    am,
    hio,
    updater,
    mic,
    fnd,
    mp,
    mpwl,
    ac,
    http,
    dsp,
    snd,
    dlp,
    hio_low,
    csnd,
    ssl,
    am_low,
    nex,
    friends,
    rdt,
    applet,
    nim,
    ptm,
    midi,
    mc,
    swc,
    fatfs,
    ngc,
    card,
    cardnor,
    sdmc,
    boss,
    dbm,
    config,
    ps,
    cec,
    ir,
    uds,
    pl,
    cup,
    gyroscope,
    mcu,
    ns,
    news,
    ro,
    gd,
    card_spi,
    ec,
    web_browser,
    @"test",
    enc,
    pia,
    act,
    vctl,
    olv,
    neia,
    npns,
    avd = 90,
    l2b,
    mvd,
    nfc,
    uart,
    spm,
    qtm,
    nfp,
    application = 254,
    invalid_result_value,
    _,
};

pub const ResultDescription = enum(u10) {
    success,
    invalid_selection = 0x3E8,
    too_large,
    not_authorized,
    already_done,
    invalid_size,
    invalid_enum_value,
    invalid_combination,
    no_data,
    busy,
    misaligned_address,
    misaligned_size,
    out_of_memory,
    not_implemented,
    invalid_address,
    invalid_pointer,
    invalid_handle,
    not_initialized,
    already_initialized,
    not_found,
    cancel_requested,
    already_exists,
    out_of_range,
    timeout,
    invalid_result_value,
    _,
};

pub const ResultCode = packed struct(i32) {
    pub const success: ResultCode = @bitCast(@as(u32, 0));

    pub const timeout: ResultCode = @bitCast(@as(u32, 0x09401BFE));
    pub const out_of_sync_objects: ResultCode = @bitCast(@as(u32, 0xC8601801));
    pub const out_of_memory_blocks: ResultCode = @bitCast(@as(u32, 0xC8601802));
    pub const out_of_sessions: ResultCode = @bitCast(@as(u32, 0xC8601809));
    pub const out_of_memory: ResultCode = @bitCast(@as(u32, 0xC860180A));
    pub const port_not_found: ResultCode = @bitCast(@as(u32, 0xD88007FA));
    pub const session_closed: ResultCode = @bitCast(@as(u32, 0xC920181A));

    description: ResultDescription = .success,
    module: ResultModule = .common,
    _reserved0: u3 = 0,
    summary: ResultSummary = .success,
    level: ResultLevel = .success,

    pub inline fn isSuccess(code: ResultCode) bool {
        return @as(i32, @bitCast(code)) >= 0;
    }
};

pub fn Result(T: type) type {
    return union(enum) {
        const Res = @This();

        pub const Success = struct { code: ResultCode, value: T };

        success: Success,
        failure: ResultCode,

        pub inline fn of(code: ResultCode, value: T) Res {
            return if (code.isSuccess()) .{ .success = .{ .code = code, .value = value } } else .{ .failure = code };
        }
    };
}
