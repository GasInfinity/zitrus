//! `Horizon` result definitions.
//!
//! A `Code` is composed of a `Level`, `Summary`,
//! `Module` and `Description`.
//!
//! Positive `Code`s are not considered `errors`.

pub const Level = enum(u5) {
    success,
    info,
    status = 25,
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
    application = 254,
    invalid_result_value,
    _,

    pub fn SpecificDescription(comptime module: Module) type {
        return switch (module) {
            .fs => Description.Filesystem,
            else => Description,
        };
    }
};

// TODO: fill this table by testing each error condition.
// NOTE: we will have to split this into multiple (one for each module), it looks like different modules reuse the same description.
pub const Description = enum(u10) {
    pub const Filesystem = enum(u10) {
        file_not_found = 120,
        file_already_exists = 190,
        invalid_open_flags = 230,
        entry_not_of_kind = 250,

        invalid_path = 720,

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
    };

    success,

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

    // common
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
};

pub const Code = packed struct(i32) {
    /// Not a real code, it's used to say that a generic failure occurred.
    pub const failure: Code = .{
        .description = .no_data,
        .module = .common,
        .level = .fatal,
        .summary = .status_changed,
    };

    pub const fs = struct {
        pub const entry_not_found: Code = @bitCast(@as(u32, 0xC8804478));
        pub const unexpected_entry_kind: Code = @bitCast(@as(u32, 0xC92044FA));
        pub const file_already_exists: Code = @bitCast(@as(u32, 0xC82044BE));
    };

    pub const success: Code = @bitCast(@as(u32, 0));
    pub const not_implemented: Code = @bitCast(@as(u32, 0xE0E01BF4));

    // :wilted_rose:
    pub const fnd_out_of_memory: Code = @bitCast(@as(u32, 0xD86093F3));
    pub const kernel_invalid_handle: Code = @bitCast(@as(u32, 0xD8E007F7));
    pub const kernel_out_of_memory: Code = @bitCast(@as(u32, 0xD86007F3));
    pub const kernel_out_of_handles: Code = @bitCast(@as(u32, 0xD8600413));
    pub const kernel_out_of_range: Code = @bitCast(@as(u32, 0xD8E007FD));
    pub const kernel_unaligned_address: Code = @bitCast(@as(u32, 0xD8E007F1));
    pub const kernel_unaligned_size: Code = @bitCast(@as(u32, 0xD8E007F2));
    pub const kernel_permission_denied: Code = @bitCast(@as(u32, 0xD92007EA));
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
    pub const os_unaligned_address: Code = @bitCast(@as(u32, 0xE0E01BF1));
    pub const os_unaligned_size: Code = @bitCast(@as(u32, 0xE0E01BF2));
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
    pub const os_session_closed_by_remote: Code = @bitCast(@as(u32, 0xC920181A));
    pub const os_port_busy: Code = @bitCast(@as(u32, 0xD0401834));
    pub const os_already_exists: Code = @bitCast(@as(u32, 0xD9001BFC));
    pub const os_not_found: Code = @bitCast(@as(u32, 0xD8801BFA));

    pub const out_of_sync_objects: Code = @bitCast(@as(u32, 0xC8601801));
    pub const out_of_sessions: Code = @bitCast(@as(u32, 0xC8601809));
    pub const out_of_memory: Code = @bitCast(@as(u32, 0xC860180A));

    pub const srv_name_out_of_bounds: Code = @bitCast(@as(u32, 0xD9006405));
    pub const srv_access_denied: Code = @bitCast(@as(u32, 0xD8E06406));
    pub const srv_name_embedded_null: Code = @bitCast(@as(u32, 0xD9006407));
    pub const srv_out_of_services: Code = @bitCast(@as(u32, 0xD86067F3));
    pub const srv_process_not_registered: Code = @bitCast(@as(u32, 0xD8806404));

    description: Description = .success,
    module: Module = .common,
    _reserved0: u3 = 0,
    summary: Summary = .success,
    level: Level = .success,

    pub inline fn isSuccess(code: Code) bool {
        return @as(i32, @bitCast(code)) >= 0;
    }

    pub fn format(code: Code, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const known_description = switch (code.module) {
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
        try writer.writeAll("): ");
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
