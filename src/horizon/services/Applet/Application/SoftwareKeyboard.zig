pub const State = extern struct {
    pub const max_button_text_len = 16 + 1;
    pub const max_hint_text_len = 64 + 1;
    pub const max_callback_message_len = 256 + 1;

    pub const Type = enum(u32) {
        normal,
        qwerty,
        numeric_pad,
        western,
    };

    pub const ValidInput = enum(u32) {
        anything,
        not_empty,
        not_empty_not_blank,
        not_blank,
        fixed_length,
    };

    pub const Button = enum(u32) {
        left,
        middle,
        right,
        none,
    };

    pub const ButtonConfig = enum(u32) {
        single,
        dual,
        triple,
        none,
    };

    pub const PasswordMode = enum(u32) {
        none,
        hide,
        hide_delay,
    };

    pub const Filter = packed struct(u32) {
        pub const none: Filter = .{};

        digits: bool = false,
        @"@": bool = false,
        @"%": bool = false,
        @"\\": bool = false,
        profanity: bool = false,
        callback: bool = false,
        _: u26 = 0,
    };

    pub const CallbackReply = enum(i32) {
        ok,
        close,
        @"continue",
    };

    pub const Reply = enum(i32) {
        invalid_input = -2,
        out_of_memory = -3,

        d0_clicked = 0,
        d1_clicked0,
        d1_clicked1,
        d2_clicked0,
        d2_clicked1,
        d2_clicked2,

        home_pressed = 10,
        reset_pressed,
        power_pressed,

        parental_ok = 20,
        parental_fail,

        banned_input = 30,
        _,
    };

    pub const Language = packed struct(u16) {
        pub const system: Language = .{ .raw = 0 };

        raw: u16,

        pub fn lang(language: services.Config.Language) Language {
            return .{ .raw = @intFromEnum(language) + 1 };
        }
    };

    comptime {
        std.debug.assert(@sizeOf(State) == 0x400);
    }

    type: Type,
    buttons: ButtonConfig,
    valid_input: ValidInput,
    password_mode: PasswordMode,
    is_parental: u32,
    darken_top_screen: u32,
    filter: Filter,
    state_flags: u32,
    maximum_text_length: u16,
    dictionary_word_count: u16,
    max_digits: u16,
    button_text: [3][max_button_text_len]u16,
    numpad_keys: [2]u16,
    hint_text: [max_hint_text_len]u16,
    predictive_input: bool,
    multiline: bool,
    fixed_width: bool,
    allow_home: bool,
    allow_reset: bool,
    allow_power: bool,
    _unknown0: bool = false,
    default_qwerty: bool,
    button_submit_texts: [4]bool, // Why 4?
    language: Language,
    initial_text_offset: u32,
    dictionary_offset: u32,
    initial_status_offset: u32,
    initial_learning_offset: u32,
    shared_memory_size: u32,
    version: u32 = 5, // ?
    // NOTE: These are by default undefined as we don't have to initialize them, it's the response from the applet.
    reply: Reply = undefined,
    status_offset: u32 = undefined,
    learning_offset: u32 = undefined,
    text_offset: u32 = undefined,
    text_length: u16 = undefined,
    callback_result: CallbackReply = undefined,
    callback_message: [max_callback_message_len]u16 = undefined,
    skip_at_check: bool = false, // ?
    reserved: [171]u8 = undefined,
};

pub const DictionaryWord = extern struct {
    pub const max_word_len = 40 + 1;

    pub const Language = union(enum) {
        independent,
        dependent: services.Config.Language,
    };

    typed: [max_word_len]u16,
    spelled: [max_word_len]u16,
    language: services.Config.Language,
    all_languages: bool,

    pub fn word(typed: Config.AnyString, spelled: Config.AnyString, language: Language) DictionaryWord {
        return .{
            .typed = typed.arrayEncodeZ(max_word_len),
            .spelled = spelled.arrayEncodeZ(max_word_len),
            .language = switch (language) {
                .independent => .en,
                .dependent => |lang| lang,
            },
            .all_languages = switch (language) {
                .independent => true,
                .dependent => false,
            },
        };
    }
};

pub const StatusData = extern struct { raw: [0x11]u8 };
pub const LearningData = extern struct { raw: [0x201B]u8 };

pub const Result = enum {
    fail,

    left,
    middle,
    right,

    jump_home,
    software_reset,
    jump_home_by_power,
};

state: State,
text: []align(horizon.heap.page_size) u8,
text_block: MemoryBlock,

pub const ParentalFeatures = packed struct(u8) {
    darken_top: bool = false,
    allow_home: bool = false,
    allow_reset: bool = false,
    allow_power: bool = false,
    _: u4 = 0,
};

pub const Config = struct {
    pub const Kind = enum {
        normal,
        western_only,
    };

    pub const Features = packed struct(u8) {
        pub const none: Features = .{};

        darken_top: bool = false,
        fixed_width: bool = false,
        multiline: bool = false,
        predictive_input: bool = false,
        default_qwerty: bool = false,
        allow_home: bool = false,
        allow_reset: bool = false,
        allow_power: bool = false,
    };

    pub const AnyString = union(enum) {
        default,
        utf16_encoded: []const u16,
        utf8_encoded: []const u8,

        pub fn utf8(value: []const u8) AnyString {
            return .{ .utf8_encoded = value };
        }

        pub fn utf16(value: []const u16) AnyString {
            return .{ .utf16_encoded = value };
        }

        pub fn bufEncodeZ(any: AnyString, buffer: []u16) void {
            switch (any) {
                .default => buffer[0] = 0,
                .utf8_encoded => |utf8_encoded| {
                    const written = std.unicode.utf8ToUtf16Le(buffer[0..(buffer.len - 1)], utf8_encoded) catch unreachable;
                    buffer[written] = 0;
                },
                .utf16_encoded => |utf16_encoded| {
                    @memcpy(buffer[0..utf16_encoded.len], utf16_encoded);
                    buffer[utf16_encoded.len] = 0;
                },
            }
        }

        pub fn arrayEncodeZ(any: AnyString, comptime max_len: usize) [max_len]u16 {
            var target: [max_len]u16 = undefined;
            any.bufEncodeZ(&target);
            return target;
        }
    };

    pub const Button = struct {
        pub const Submits = enum(u1) { none, submits };

        pub const default: Button = .button(.default, false);
        pub const default_submit: Button = .button(.default, true);

        label: AnyString,
        submits_text: bool,

        pub fn button(label: AnyString, submits_text: Submits) Button {
            return .{ .label = label, .submits_text = submits_text == .submits };
        }

        pub fn labels(buttons: []const Button) [3][State.max_button_text_len]u16 {
            std.debug.assert(buttons.len <= 3);

            return switch (buttons.len) {
                1 => .{ .{0} ++ @as([State.max_button_text_len - 1]u16, undefined), .{0} ++ @as([State.max_button_text_len - 1]u16, undefined), buttons[0].label.arrayEncodeZ(State.max_button_text_len) },
                2 => .{ buttons[0].label.arrayEncodeZ(State.max_button_text_len), .{0} ++ @as([State.max_button_text_len - 1]u16, undefined), buttons[1].label.arrayEncodeZ(State.max_button_text_len) },
                3 => .{ buttons[0].label.arrayEncodeZ(State.max_button_text_len), buttons[1].label.arrayEncodeZ(State.max_button_text_len), buttons[2].label.arrayEncodeZ(State.max_button_text_len) },
                else => unreachable,
            };
        }

        pub fn submits(buttons: []const Button) [4]bool {
            return switch (buttons.len) {
                1 => .{ false, false, buttons[0].submits_text, false },
                2 => .{ buttons[0].submits_text, false, buttons[1].submits_text, false },
                3 => .{ buttons[0].submits_text, buttons[1].submits_text, buttons[2].submits_text, false },
                else => unreachable,
            };
        }
    };

    max_length: u16,
    buttons: []const Config.Button,
    kind: Kind = .normal,
    filter: State.Filter = .none,
    max_digits: u16 = 0,
    initial_text: AnyString = .default,
    hint: AnyString = .default,
    features: Features = .none,
    valid_input: State.ValidInput = .anything,
    password_mode: State.PasswordMode = .none,
    dictionary: []const DictionaryWord,
};

pub const NumpadConfig = struct {
    pub const Features = packed struct(u8) {
        pub const none: Features = .{};

        darken_top: bool = false,
        fixed_width: bool = false,
        allow_home: bool = false,
        allow_reset: bool = false,
        allow_power: bool = false,
        _: u3 = 0,
    };

    pub const SideButtons = struct {
        pub const none: SideButtons = .{ .left = 0, .right = 0 };

        left: u16,
        right: u16,
    };

    max_length: u16,
    buttons: []const Config.Button,
    filter: State.Filter = .none,
    max_digits: u16 = 0,
    initial_text: Config.AnyString = .default,
    hint: Config.AnyString = .default,
    features: Features = .none,
    side_buttons: SideButtons = .none,
    valid_input: State.ValidInput = .anything,
    password_mode: State.PasswordMode = .none,
};

pub const CallbackResult = union(State.CallbackReply) {
    ok,
    close: Config.AnyString,
    @"continue": Config.AnyString,
};

pub fn normal(config: Config, allocator: std.mem.Allocator) !SoftwareKeyboard {
    std.debug.assert(config.buttons.len > 0 and config.buttons.len <= 3);

    // TODO: status and learning data for predictive input
    const needed_shared_memory = std.mem.alignForward(usize, config.max_length + (config.dictionary.len * @sizeOf(DictionaryWord)), horizon.heap.page_size);
    const shared = try allocator.alignedAlloc(u8, .fromByteUnits(horizon.heap.page_size), needed_shared_memory);
    const shared_block: MemoryBlock = try .create(shared.ptr, needed_shared_memory, .rw, .rw);

    config.initial_text.bufEncodeZ(std.mem.bytesAsSlice(u16, shared[0..])[0..config.max_length]);
    @memcpy(shared[(config.max_length * @sizeOf(u16))..][0..(config.dictionary.len * @sizeOf(DictionaryWord))], std.mem.sliceAsBytes(config.dictionary));

    return .{
        .state = .{
            .type = switch (config.kind) {
                .normal => .normal,
                .western_only => .western,
            },
            .buttons = @enumFromInt(config.buttons.len - 1),
            .valid_input = config.valid_input,
            .password_mode = config.password_mode,
            .is_parental = 0,
            .darken_top_screen = @intFromBool(config.features.darken_top),
            .filter = config.filter,
            .state_flags = 0,
            .maximum_text_length = config.max_length,
            .dictionary_word_count = @intCast(config.dictionary.len),
            .max_digits = config.max_digits,
            .button_text = Config.Button.labels(config.buttons),
            .numpad_keys = undefined,
            .hint_text = config.hint.arrayEncodeZ(State.max_hint_text_len),
            .predictive_input = config.features.predictive_input,
            .multiline = config.features.multiline,
            .fixed_width = config.features.fixed_width,
            .allow_home = config.features.allow_home,
            .allow_reset = config.features.allow_reset,
            .allow_power = config.features.allow_power,
            .default_qwerty = config.features.default_qwerty,
            .button_submit_texts = Config.Button.submits(config.buttons),
            .language = .system,
            .initial_text_offset = 0,
            .dictionary_offset = config.max_length * @sizeOf(u16),
            .initial_status_offset = std.math.maxInt(u32),
            .initial_learning_offset = std.math.maxInt(u32),
            .shared_memory_size = needed_shared_memory,
        },
        .text = shared,
        .text_block = shared_block,
    };
}
pub fn numpad(config: NumpadConfig, allocator: std.mem.Allocator) !SoftwareKeyboard {
    std.debug.assert(config.buttons.len > 0 and config.buttons.len <= 3);

    const needed_shared_memory = std.mem.alignForward(usize, config.max_length, horizon.heap.page_size);
    const text = try allocator.alignedAlloc(u8, .fromByteUnits(horizon.heap.page_size), needed_shared_memory);
    const text_block: MemoryBlock = try .create(text.ptr, needed_shared_memory, .rw, .rw);

    config.initial_text.bufEncodeZ(std.mem.bytesAsSlice(u16, text[0..])[0..config.max_length]);

    return .{
        .state = .{
            .type = .numeric_pad,
            .buttons = @enumFromInt(config.buttons.len - 1),
            .valid_input = config.valid_input,
            .password_mode = config.password_mode,
            .is_parental = 0,
            .darken_top_screen = @intFromBool(config.features.darken_top),
            .filter = config.filter,
            .state_flags = 0,
            .maximum_text_length = config.max_length,
            .dictionary_word_count = 0,
            .max_digits = config.max_digits,
            .button_text = Config.Button.labels(config.buttons),
            .numpad_keys = .{ config.side_buttons.left, config.side_buttons.right },
            .hint_text = config.hint.arrayEncodeZ(State.max_hint_text_len),
            .predictive_input = undefined,
            .multiline = undefined,
            .fixed_width = config.features.fixed_width,
            .allow_home = config.features.allow_home,
            .allow_reset = config.features.allow_reset,
            .allow_power = config.features.allow_power,
            .default_qwerty = undefined,
            .button_submit_texts = Config.Button.submits(config.buttons),
            .language = .system,
            .initial_text_offset = std.math.maxInt(u32),
            .dictionary_offset = std.math.maxInt(u32),
            .initial_status_offset = std.math.maxInt(u32),
            .initial_learning_offset = std.math.maxInt(u32),
            .shared_memory_size = needed_shared_memory,
        },
        .text = text,
        .text_block = text_block,
    };
}

pub fn parental(language: State.Language, features: ParentalFeatures) SoftwareKeyboard {
    return .{
        .state = .{
            .type = undefined,
            .buttons = undefined,
            .valid_input = undefined,
            .password_mode = undefined,
            .is_parental = 1,
            .darken_top_screen = @intFromBool(features.darken_top),
            .filter = undefined,
            .state_flags = undefined,
            .maximum_text_length = undefined,
            .dictionary_word_count = undefined,
            .max_digits = undefined,
            .button_text = undefined,
            .numpad_keys = undefined,
            .hint_text = undefined,
            .predictive_input = undefined,
            .multiline = undefined,
            .fixed_width = undefined,
            .allow_home = features.allow_home,
            .allow_reset = features.allow_reset,
            .allow_power = features.allow_power,
            .default_qwerty = undefined,
            .button_submit_texts = @splat(false),
            .language = language,
            .initial_text_offset = undefined,
            .dictionary_offset = undefined,
            .initial_status_offset = undefined,
            .initial_learning_offset = undefined,
            .shared_memory_size = 0,
            .version = 5,
        },
        .text = &.{},
        .text_block = .{ .obj = .null },
    };
}

pub fn deinit(swkbd: *SoftwareKeyboard, allocator: std.mem.Allocator) void {
    if (swkbd.text_block.obj != .null) {
        swkbd.text_block.close();
        allocator.free(swkbd.text);
    }

    swkbd.* = undefined;
}

pub fn writtenText(swkbd: *SoftwareKeyboard) [:0]const u16 {
    return std.mem.bytesAsSlice(u16, swkbd.text)[swkbd.state.text_offset..swkbd.state.text_length :0];
}

pub fn startContext(swkbd: *SoftwareKeyboard, app: *Application, apt: Applet, srv: ServiceManager, gsp: GspGpu, context: anytype) !Result {
    std.debug.assert(if (swkbd.state.filter.callback) @TypeOf(context) != void else true);
    try app.startLibraryApplet(apt, srv, gsp, .application_software_keyboard, swkbd.text_block.obj, std.mem.asBytes(&swkbd.state));

    return swkbd_loop: switch (try app.waitAppletResult(apt, srv, gsp, std.mem.asBytes(&swkbd.state))) {
        .execution => |e| switch (e) {
            .resumed => switch (swkbd.state.reply) {
                _, .invalid_input => unreachable,
                .out_of_memory => return error.OutOfMemory,

                .d0_clicked => .right,
                .d1_clicked0 => .left,
                .d1_clicked1 => .right,
                .d2_clicked0 => .left,
                .d2_clicked1 => .middle,
                .d2_clicked2 => .right,

                .home_pressed => .jump_home,
                .reset_pressed => .software_reset,
                .power_pressed => .jump_home_by_power,

                .parental_ok => .right,
                .parental_fail => .fail,

                .banned_input => .fail,
            },
            .jump_home => .jump_home,
            .must_close => unreachable,
        },
        .message => |params| if (@TypeOf(context) != void) {
            std.debug.assert(params.handle == .null);

            const result = context.filter(swkbd.writtenText());
            swkbd.state.callback_result = std.meta.activeTag(result);

            switch (result) {
                .ok => swkbd.state.callback_message[0] = 0,
                .close, .@"continue" => |message| message.bufEncodeZ(&swkbd.state.callback_message),
            }

            try apt.sendSendParameter(srv, horizon.environment.program_meta.app_id, .application_software_keyboard, .message, swkbd.text_block.obj, std.mem.asBytes(&swkbd.state));
            continue :swkbd_loop try app.waitAppletResult(apt, srv, gsp, std.mem.asBytes(&swkbd.state));
        } else unreachable,
    };
}

pub fn start(swkbd: *SoftwareKeyboard, app: *Application, apt: Applet, srv: ServiceManager, gsp: GspGpu) !Result {
    return swkbd.startContext(app, apt, srv, gsp, {});
}

const SoftwareKeyboard = @This();
const Applet = horizon.services.Applet;
const Application = Applet.Application;

const GspGpu = horizon.services.GspGpu;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const services = horizon.services;

const ResultCode = horizon.result.Code;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = zitrus.horizon.ServiceManager;
