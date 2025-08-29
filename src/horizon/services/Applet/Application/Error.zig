pub const State = extern struct {
    pub const Type = enum(u32) {
        code,
        text,
        eula,
        eula_first_boot,
        eula_draw_only,
        agree_update,
        code_language = 0x100,
        text_language,
        eula_language,
        text_word_wrap = 0x200,
        text_language_word_wrap = 0x300,
    };

    pub const Language = packed struct(u16) {
        pub const system: Language = .{ .raw = 0 };

        raw: u16,

        pub fn lang(language: services.Config.Language) Language {
            return .{ .raw = @intFromEnum(language) + 1 };
        }
    };

    pub const Flags = extern struct {
        pub const none: Flags = .{};

        /// Allow using the home button (is able to return jump to home)
        allow_home: bool = true,
        /// Allow using software reset to exit (L + R + START + SELECT)
        allow_reset: bool = false,
        allow_settings: bool = true,
        _unknown1: u8 = 0,
    };

    pub const Reply = enum(u32) {
        none = 0,
        action_performed,

        jump_home = 10,
        software_reset,
        jump_home_by_power,
        _,
    };

    // Azahar logs show that the LLE applet always uses this size.
    comptime {
        std.debug.assert(@sizeOf(State) == 0xF80);
    }

    type: Type,
    code: horizon.result.Code,
    _unknown0: u16 = undefined,
    language: Language,
    message: [1900]u16,
    flags: Flags = .{},
    _unknown1: [34]u32 = undefined,
    reply: Reply = undefined,
    eula_minor: u8 = undefined,
    eula_major: u8 = undefined,
    _unknown2: [2]u8 = undefined,
    _unknown3: [2]u32 = undefined,

    pub fn result(code: horizon.result.Code, flags: Flags) State {
        return .{
            .type = .code,
            .code = code,
            .language = undefined,
            .message = undefined,
            .flags = flags,
        };
    }

    pub fn resultLanguage(code: horizon.result.Code, language: Language, flags: Flags) State {
        return .{
            .type = .code_language,
            .code = code,
            .language = language,
            .message = undefined,
            .flags = flags,
        };
    }

    pub fn textUtf8(code: horizon.result.Code, message: []const u8, flags: Flags) State {
        var cfg: State = .{
            .type = .text,
            .code = code,
            .language = undefined,
            .message = undefined,
            .flags = flags,
        };

        const written = std.unicode.utf8ToUtf16Le(&cfg.message, message) catch unreachable;
        cfg.message[written] = 0;
        return cfg;
    }

    pub fn text(code: horizon.result.Code, message: []const u16, flags: Flags) State {
        var cfg: State = .{
            .type = .text,
            .code = code,
            .language = undefined,
            .message = undefined,
            .flags = flags,
        };

        @memcpy(cfg.message[0..message.len], message);
        cfg.message[message.len] = 0;
        return cfg;
    }

    pub fn textUtf8Language(code: horizon.result.Code, message: []const u8, language: Language, flags: Flags) State {
        var cfg: State = .{
            .type = .text_language,
            .code = code,
            .language = language,
            .message = undefined,
            .flags = flags,
        };

        const written = std.unicode.utf8ToUtf16Le(&cfg.message, message) catch unreachable;
        cfg.message[written] = 0;
        return cfg;
    }

    pub fn textLanguage(code: horizon.result.Code, message: []const u16, language: Language, flags: Flags) State {
        var cfg: State = .{
            .type = .text_language,
            .code = code,
            .language = language,
            .message = undefined,
            .flags = flags,
        };

        @memcpy(cfg.message[0..message.len], message);
        cfg.message[message.len] = 0;
        return cfg;
    }

    pub fn eula(flags: Flags) State {
        return .{
            .type = .eula,
            .code = undefined,
            .language = undefined,
            .message = undefined,
            .flags = flags,
        };
    }

    pub fn eulaLanguage(language: Language, flags: Flags) State {
        return .{
            .type = .eula_language,
            .code = undefined,
            .language = language,
            .message = undefined,
            .flags = flags,
        };
    }

    pub fn agreeUpdate(flags: Flags) State {
        return .{
            .type = .agree_update,
            .code = undefined,
            .language = undefined,
            .message = undefined,
            .flags = flags,
        };
    }
};

pub const Result = enum {
    none,
    action_performed,
    jump_home,
    jump_home_by_power,
    software_reset,
};

state: State,

pub fn result(code: horizon.result.Code, flags: State.Flags) Error {
    return .{ .state = .result(code, flags) };
}

pub fn resultLanguage(code: horizon.result.Code, language: State.Language, flags: State.Flags) Error {
    return .{ .state = .resultLanguage(code, language, flags) };
}

pub fn textUtf8(code: horizon.result.Code, message: []const u8, flags: State.Flags) Error {
    return .{ .state = .textUtf8(code, message, flags) };
}

pub fn text(code: horizon.result.Code, message: []const u16, flags: State.Flags) Error {
    return .{ .state = .text(code, message, flags) };
}

pub fn textUtf8Language(code: horizon.result.Code, message: []const u8, language: State.Language, flags: State.Flags) Error {
    return .{ .state = .textUtf8Language(code, message, language, flags) };
}

pub fn textLanguage(code: horizon.result.Code, message: []const u16, language: State.Language, flags: State.Flags) Error {
    return .{ .state = .textLanguage(code, message, language, flags) };
}

pub fn eula(flags: State.Flags) Error {
    return .{ .state = .eula(flags) };
}

pub fn eulaLanguage(language: State.Language, flags: State.Flags) Error {
    return .{ .state = .eulaLanguage(language, flags) };
}

pub fn agreeUpdate(flags: State.Flags) Error {
    return .{ .state = .agreeUpdate(flags) };
}

pub fn start(err: *Error, app: *Application, apt: Applet, srv: ServiceManager, gsp: *GspGpu) !Result {
    try app.startLibraryApplet(apt, srv, gsp, .application_error_display, .null, std.mem.asBytes(&err.state));

    return switch (try app.waitAppletResult(apt, srv, gsp, std.mem.asBytes(&err.state))) {
        .execution => |e| switch (e) {
            .resumed => switch (err.state.reply) {
                .none => .none,
                .action_performed => .action_performed,
                .software_reset => .software_reset,
                .jump_home_by_power => .jump_home_by_power,
                // jump_home is handled below
                .jump_home, _ => unreachable,
            },
            .jump_home => .jump_home,
            .must_close => unreachable,
        },
        // Error display doesn't message us!
        .message => unreachable,
    };
}

const Error = @This();
const Applet = horizon.services.Applet;
const Application = Applet.Application;

const GspGpu = horizon.services.GspGpu;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const services = horizon.services;

const ServiceManager = zitrus.horizon.ServiceManager;
