//! `Horizon` result definitions.
//!
//! A `Code` is composed of a `Level`, `Summary`,
//! `Module` and `Description`.
//!
//! Positive `Code`s are not considered `errors`.

pub const Level = enum(i5) {
    success,
    info,
    status = -7,
    temporary,
    permanent,
    usage,
    reinitialize,
    reset,
    fatal,
    _,
};

pub const Summary = enum(u6) {
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

pub const Module = enum(u8) {
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

    ztr = 253,
    application = 254,
    invalid_result_value,
    _,

    pub fn SpecificDescription(comptime module: Module) type {
        return switch (module) {
            .kernel => Description.Kernel,
            .os => Description.OperatingSystem,
            .srv => Description.ServiceManager,
            .fs => Description.Filesystem,
            .csnd => Description.ChannelSound,
            .mic => Description.Microphone,
            .pdn => Description.PowerDown,
            .dsp => Description.Dsp,
            .ztr => Description.Zitrus,
            else => Description,
        };
    }
};

// TODO: fill this table by testing each error condition.
// NOTE: we will have to split this into multiple (one for each module), it looks like different modules reuse the same description.
pub const Description = enum(u10) {
    pub const Kernel = enum(u10) {
        out_of_kernel_memory = 1,
        out_of_kernel_memory_for_memory_blocks = 2,
        out_of_client_sessions = 9,
        out_of_memory_blocks = 11,
        out_of_mutexes = 13,
        out_of_semaphores = 14,
        out_of_events = 15,
        out_of_timers = 16,
        out_of_handles = 19,
        invalid_string = 20,
        session_closed_by_remote = 26,
        string_too_big = 30,
        mutex_not_owned = 31,
        incompatible_permissions = 46,
        out_of_address_arbiters = 51,
        _,
    };

    pub const OperatingSystem = enum(u10) {
        session_closed_by_remote = 26,
        invalid_ipc_header = 47,
        invalid_ipc_parameters,
        out_of_shared_memory = 55,
        _,
    };

    pub const ServiceManager = enum(u10) {
        already_subscribed = 3,
        notifications_not_found = 4,
        too_many_subscriptions = 5,
        access_denied = 6,
        _,
    };

    pub const Filesystem = enum(u10) {
        entry_not_found = 120,
        entry_already_exists = 190,
        invalid_open_flags = 230,
        entry_not_of_kind = 250,

        invalid_path = 720,
        not_initialized = 731,
        _,
    };

    pub const ChannelSound = enum(u10) {
        direct_sound_sleeping = 1,
        direct_sound_priority = 2,
        _,
    };

    pub const Microphone = enum(u10) {
        shell_closed = 1,
        _,
    };

    pub const PowerDown = enum(u10) {
        invalid_reset = 1,
        _,
    };

    pub const Dsp = enum(u10) {
        not_active = 1,
        _,
    };

    pub const Zitrus = enum(u10) {
        panic = 1,
        invalid_response_ipc_header,
        invalid_response_ipc_parameters,
        _,
    };

    // common
    success,

    invalid_selection = 1000,
    too_large,
    permission_denied,
    already_done,
    invalid_size,
    invalid_enum_value,
    invalid_combination,
    no_data,
    busy,
    unaligned_address,
    unaligned_size,
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

    pub fn desc(value: u10) Description {
        return @enumFromInt(value);
    }
};

pub const Code = packed struct(i32) {
    /// Deprecated: use `ztr_panic`
    pub const failure = ztr_panic;

    // Custom codes, not real (obviously)
    /// 0xf943f401
    pub const ztr_panic: Code = .specificResult(.fatal, .status_changed, .ztr, .panic);

    /// 0xd8a3f402
    pub const ztr_invalid_response_ipc_header: Code = .specificResult(.permanent, .invalid_state, .ztr, .invalid_response_ipc_header);
    /// 0xd8a3f403
    pub const ztr_invalid_response_ipc_parameters: Code = .specificResult(.permanent, .invalid_state, .ztr, .invalid_response_ipc_parameters);

    pub const success: Code = @bitCast(@as(u32, 0));

    /// 0xe0e003ed
    pub const common_invalid_enum_value: Code = .result(.usage, .invalid_arg, .common, .invalid_enum_value);

    // :wilted_rose:
    pub const fnd_out_of_memory: Code = @bitCast(@as(u32, 0xD86093F3));
    /// 0xD8E007F7
    pub const kernel_invalid_handle: Code = .result(.permanent, .invalid_arg, .kernel, .invalid_handle);
    pub const kernel_out_of_memory: Code = @bitCast(@as(u32, 0xD86007F3));
    pub const kernel_out_of_handles: Code = @bitCast(@as(u32, 0xD8600413));
    pub const kernel_out_of_range: Code = @bitCast(@as(u32, 0xD8E007FD));
    pub const kernel_unaligned_address: Code = @bitCast(@as(u32, 0xD8E007F1));
    pub const kernel_unaligned_size: Code = @bitCast(@as(u32, 0xD8E007F2));
    /// 0xd92007ea
    pub const kernel_permission_denied: Code = .result(.permanent, .canceled, .kernel, .permission_denied);
    pub const kernel_invalid_pointer: Code = @bitCast(@as(u32, 0xD8E007F6));
    pub const kernel_invalid_combination: Code = @bitCast(@as(u32, 0xD90007EE));
    pub const kernel_invalid_result_value: Code = @bitCast(@as(u32, 0xD8A007FF));
    pub const kernel_mutex_not_owned: Code = @bitCast(@as(u32, 0xD8E0041F));
    pub const kernel_not_found: Code = @bitCast(@as(u32, 0xD88007FA));

    pub const os_invalid_handle: Code = @bitCast(@as(u32, 0xD9001BF7));
    pub const os_invalid_string: Code = @bitCast(@as(u32, 0xD9001814));
    pub const os_string_too_big: Code = @bitCast(@as(u32, 0xE0E0181E));
    pub const os_out_of_kernel_memory: Code = @bitCast(@as(u32, 0xC8601801));
    pub const os_out_of_kernel_memory_for_memory_blocks: Code = @bitCast(@as(u32, 0xC8601802));
    /// 0xe0e01bf1
    pub const os_unaligned_address: Code = .result(.usage, .invalid_arg, .os, .unaligned_address);
    /// 0xe0e01bf2
    pub const os_unaligned_size: Code = .result(.usage, .invalid_arg, .os, .unaligned_size);
    /// 0xe0e01be4
    pub const os_not_implemented: Code = .result(.usage, .invalid_arg, .os, .not_implemented);
    pub const os_invalid_address: Code = @bitCast(@as(u32, 0xE0E01BF5));
    pub const os_invalid_address_state: Code = @bitCast(@as(u32, 0xE0A01BF5));
    pub const os_invalid_combination: Code = @bitCast(@as(u32, 0xE0E01BEE));
    pub const os_out_of_range: Code = @bitCast(@as(u32, 0xE0E01BFD));
    pub const os_incompatible_permissions: Code = @bitCast(@as(u32, 0xD900182E));
    pub const os_out_of_client_sessions: Code = @bitCast(@as(u32, 0xC8601809));
    pub const os_out_of_memory_blocks: Code = @bitCast(@as(u32, 0xC860180B));
    pub const os_out_of_mutexes: Code = @bitCast(@as(u32, 0xC860180D));
    pub const os_out_of_semaphores: Code = @bitCast(@as(u32, 0xC860180E));
    pub const os_out_of_events: Code = @bitCast(@as(u32, 0xC860180F));
    pub const os_out_of_timers: Code = @bitCast(@as(u32, 0xC8601810));
    pub const os_out_of_address_arbiters: Code = @bitCast(@as(u32, 0xC8601833));
    pub const os_timeout: Code = @bitCast(@as(u32, 0x09401BFE));
    /// 0xc920181a
    pub const os_session_closed_by_remote: Code = .specificResult(.status, .canceled, .os, .session_closed_by_remote);
    pub const os_port_busy: Code = @bitCast(@as(u32, 0xD0401834));
    pub const os_already_exists: Code = @bitCast(@as(u32, 0xD9001BFC));
    /// 0xd8801bfa
    pub const os_not_found: Code = .result(.permanent, .not_found, .os, .not_found);
    /// 0xd900182f
    pub const os_invalid_ipc_header: Code = .specificResult(.permanent, .wrong_arg, .os, .invalid_ipc_header);
    /// 0xd9001830
    pub const os_invalid_ipc_parameters: Code = .specificResult(.permanent, .wrong_arg, .os, .invalid_ipc_parameters);

    pub const out_of_sync_objects: Code = @bitCast(@as(u32, 0xC8601801));
    pub const out_of_sessions: Code = @bitCast(@as(u32, 0xC8601809));
    pub const out_of_memory: Code = @bitCast(@as(u32, 0xC860180A));

    pub const srv_name_out_of_bounds: Code = @bitCast(@as(u32, 0xD9006405));
    /// 0xD8E06406
    pub const srv_access_denied: Code = .specificResult(.permanent, .invalid_arg, .srv, .access_denied);
    pub const srv_name_embedded_null: Code = @bitCast(@as(u32, 0xD9006407));
    pub const srv_out_of_services: Code = @bitCast(@as(u32, 0xD86067F3));
    pub const srv_process_not_registered: Code = @bitCast(@as(u32, 0xD8806404));

    pub const fs_entry_not_found: Code = @bitCast(@as(u32, 0xC8804478));
    pub const fs_unexpected_entry_kind: Code = @bitCast(@as(u32, 0xC92044FA));
    pub const fs_unexpected_open_flags: Code = @bitCast(@as(u32, 0xC92044E6));
    pub const fs_entry_already_exists: Code = @bitCast(@as(u32, 0xC82044BE));

    /// 0xe0e02401
    pub const pdn_invalid_arg: Code = .specificResult(.usage, .invalid_arg, .pdn, .invalid_reset);

    /// 0xe0e03ffd
    pub const spi_out_of_range: Code = .result(.usage, .invalid_arg, .spi, .out_of_range);
    /// 0xc8a03ff8
    pub const spi_not_initialized: Code = .result(.status, .invalid_state, .spi, .not_initialized);
    /// 0x00203fef
    pub const spi_nop: Code = .result(.success, .nop, .spi, .no_data);

    /// 0xe0e033ea
    pub const gpio_permission_denied: Code = .result(.usage, .invalid_arg, .gpio, .permission_denied);
    /// 0xe0e033fa
    pub const gpio_not_found: Code = .result(.usage, .invalid_arg, .gpio, .not_found);
    /// 0xe0e033f0
    pub const gpio_busy: Code = .result(.usage, .invalid_arg, .gpio, .busy);

    /// 0xd8c107f4
    pub const ps_not_implemented: Code = .result(.permanent, .not_supported, .ps, .not_implemented);
    /// 0xc90107fa
    pub const ps_not_found: Code = .result(.status, .wrong_arg, .ps, .not_found);
    /// 0xc90107e8
    pub const ps_invalid_selection: Code = .result(.status, .wrong_arg, .ps, .invalid_selection);
    /// 0xc90107ec
    pub const ps_invalid_size: Code = .result(.status, .wrong_arg, .ps, .invalid_size);

    /// 0xc9403800
    pub const codec_status_changed: Code = .result(.status, .status_changed, .codec, .success);
    /// 0xd8603bef
    pub const codec_no_data: Code = .result(.status, .out_of_resource, .codec, .no_data);
    pub const codec_invalid_size: Code = .result(.status, .invalid_arg, .codec, .invalid_size);

    /// 0xd8208ff9
    pub const mic_already_initialized: Code = .result(.permanent, .nop, .mic, .already_initialized);
    /// 0xd8208ff8
    pub const mic_not_initialized: Code = .result(.permanent, .nop, .pdn, .not_initialized);
    /// 0xe0e08fec
    pub const mic_invalid_size: Code = .result(.usage, .invalid_arg, .mic, .invalid_size);
    /// 0xe0e08ff2
    pub const mic_unaligned_size: Code = .result(.usage, .invalid_arg, .mic, .unaligned_size);
    /// 0xe1008ffd
    pub const mic_out_of_range: Code = .result(.usage, .wrong_arg, .mic, .out_of_range);
    /// 0xc9408c01
    pub const mic_shell_closed: Code = .specificResult(.status, .invalid_arg, .mic, .shell_closed);

    /// 0xc960b7f8
    pub const csnd_not_initialized: Code = .result(.status, .internal, .csnd, .not_initialized);
    /// 0xc940b401
    pub const csnd_direct_sound_sleeping: Code = .specificResult(.status, .status_changed, .csnd, .direct_sound_sleeping);
    /// 0xc940b402
    pub const csnd_direct_sound_priority: Code = .specificResult(.status, .status_changed, .csnd, .direct_sound_priority);

    /// 0xc8a0a401
    pub const dsp_not_active: Code = .specificResult(.status, .invalid_state, .dsp, .not_active);
    // NOTE: `invalid_result_value` for module... wtf
    /// 0xe0e3fff6
    pub const dsp_invalid_pointer: Code = .result(.usage, .invalid_arg, .invalid_result_value, .invalid_pointer);
    // NOTE: `invalid_result_value` for description... wtf pt.2
    /// 0xc860a7ff
    pub const dsp_invalid_interrupt: Code = .result(.status, .out_of_resource, .dsp, .invalid_result_value);

    description: Description = .success,
    module: Module = .common,
    _reserved0: u3 = 0,
    summary: Summary = .success,
    level: Level = .success,

    pub fn result(level: Level, summary: Summary, module: Module, description: Description) Code {
        return .{
            .level = level,
            .summary = summary,
            .module = module,
            .description = description,
        };
    }

    pub fn specificResult(level: Level, summary: Summary, comptime module: Module, description: module.SpecificDescription()) Code {
        return .result(level, summary, module, @enumFromInt(@intFromEnum(description)));
    }

    pub fn isSuccess(code: Code) bool {
        return @as(i32, @bitCast(code)) >= 0;
    }

    pub fn format(code: Code, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const known_description = if (std.enums.tagName(Description, code.description)) |common|
            common
        else switch (code.module) {
            inline else => |mod| std.enums.tagName(mod.SpecificDescription(), @enumFromInt(@intFromEnum(code.description))),
            _ => std.enums.tagName(Description, code.description),
        };

        if (std.enums.tagName(Level, code.level)) |tag| {
            try writer.writeAll(tag);
        } else try writer.print("{d}", .{@intFromEnum(code.level)});
        try writer.writeByte('(');
        if (std.enums.tagName(Module, code.module)) |tag| {
            try writer.writeAll(tag);
        } else try writer.print("{d}", .{@intFromEnum(code.module)});
        try writer.writeByte(')');
        if (!code.isSuccess()) try writer.writeByte('!');
        try writer.writeAll(": ");
        if (known_description) |tag| {
            try writer.writeAll(tag);
        } else try writer.print("{d}", .{@intFromEnum(code.description)});
        try writer.writeAll(" (");
        if (std.enums.tagName(Summary, code.summary)) |tag| {
            try writer.writeAll(tag);
        } else try writer.print("{d}", .{@intFromEnum(code.summary)});
        try writer.writeByte(')');
    }
};

const std = @import("std");
