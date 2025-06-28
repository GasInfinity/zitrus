const ApplicationSettings = @This();

const Title = struct {
    title: []const u8,
    description: []const u8,
    publisher: []const u8,

    pub fn initSmdh(title: smdh.Title, arena: std.mem.Allocator) !Title {
        var converted: Title = .{
            .title = &.{},
            .description = &.{},
            .publisher = &.{},
        };

        const short = title.short_description[0..(std.mem.indexOfScalar(u16, &title.short_description, 0) orelse title.short_description.len)];
        const long = title.long_description[0..(std.mem.indexOfScalar(u16, &title.long_description, 0) orelse title.long_description.len)];
        const publisher = title.publisher[0..(std.mem.indexOfScalar(u16, &title.publisher, 0) orelse title.publisher.len)];

        if (short.len > 0) converted.title = try std.unicode.utf16LeToUtf8Alloc(arena, short);
        if (long.len > 0) converted.description = try std.unicode.utf16LeToUtf8Alloc(arena, long);
        if (publisher.len > 0) converted.publisher = try std.unicode.utf16LeToUtf8Alloc(arena, publisher);
        return converted;
    }

    pub fn toSmdh(title: Title) !smdh.Title {
        var converted: smdh.Title = std.mem.zeroes(smdh.Title);

        if (try std.unicode.checkUtf8ToUtf16LeOverflow(title.title, &converted.short_description)) {
            return error.TitleOverflow;
        }

        if (try std.unicode.checkUtf8ToUtf16LeOverflow(title.description, &converted.long_description)) {
            return error.DescriptionOverflow;
        }

        if (try std.unicode.checkUtf8ToUtf16LeOverflow(title.publisher, &converted.publisher)) {
            return error.PublisherOverflow;
        }

        _ = try std.unicode.utf8ToUtf16Le(&converted.short_description, title.title);
        _ = try std.unicode.utf8ToUtf16Le(&converted.long_description, title.description);
        _ = try std.unicode.utf8ToUtf16Le(&converted.publisher, title.publisher);
        return converted;
    }
};

const Titles = struct {
    japanese: ?Title = null,
    english: Title,
    french: ?Title = null,
    german: ?Title = null,
    italian: ?Title = null,
    spanish: ?Title = null,
    simplified_chinese: ?Title = null,
    korean: ?Title = null,
    dutch: ?Title = null,
    portuguese: ?Title = null,
    russian: ?Title = null,
    traditional_chinese: ?Title = null,
};

const Rating = union(enum) {
    pub const inactive: Rating = .{ .unrestricted = .{ .kind = .inactive } };
    pub const pending: Rating = .{ .unrestricted = .{ .kind = .pending } };
    pub const no_restriction: Rating = .{ .unrestricted = .{ .kind = .unrestricted } };

    pub const Unrestricted = struct {
        pub const Kind = enum { inactive, pending, unrestricted };

        kind: Kind,
    };

    pub const Restricted = struct {
        age: u5,
    };

    unrestricted: Unrestricted,
    restricted: Restricted,

    pub fn initSmdh(rating: smdh.Rating) Rating {
        return if (rating.no_age_restriction)
            .no_restriction
        else if (rating.rating_pending)
            .pending
        else if (!rating.active)
            .inactive
        else
            .{ .restricted = .{ .age = rating.age } };
    }

    pub fn toSmdh(rating: Rating) smdh.Rating {
        return switch (rating) {
            .unrestricted => |unrestricted| switch (unrestricted.kind) {
                .inactive => smdh.Rating.inactive,
                .pending => smdh.Rating.pending,
                .unrestricted => smdh.Rating.unrestricted,
            },
            .restricted => |restricted| smdh.Rating.restricted(restricted.age),
        };
    }
};

const Ratings = struct {
    cero: Rating = .inactive,
    esrb: Rating = .inactive,
    usk: Rating = .inactive,
    pegi_gen: Rating = .inactive,
    pegi_prt: Rating = .inactive,
    pegi_bbfc: Rating = .inactive,
    cob: Rating = .inactive,
    grb: Rating = .inactive,
    cgsrr: Rating = .inactive,

    pub fn initSmdh(ratings: smdh.Ratings) Ratings {
        return .{
            .cero = Rating.initSmdh(ratings.cero),
            .esrb = Rating.initSmdh(ratings.esrb),
            .usk = Rating.initSmdh(ratings.usk),
            .pegi_gen = Rating.initSmdh(ratings.pegi_gen),
            .pegi_prt = Rating.initSmdh(ratings.pegi_prt),
            .pegi_bbfc = Rating.initSmdh(ratings.pegi_bbfc),
            .cob = Rating.initSmdh(ratings.cob),
            .grb = Rating.initSmdh(ratings.grb),
            .cgsrr = Rating.initSmdh(ratings.cgsrr),
        };
    }

    pub fn toSmdh(ratings: Ratings) smdh.Ratings {
        return .{
            .cero = ratings.cero.toSmdh(),
            .esrb = ratings.esrb.toSmdh(),
            .usk = ratings.usk.toSmdh(),
            .pegi_gen = ratings.pegi_gen.toSmdh(),
            .pegi_prt = ratings.pegi_prt.toSmdh(),
            .pegi_bbfc = ratings.pegi_bbfc.toSmdh(),
            .cob = ratings.cob.toSmdh(),
            .grb = ratings.grb.toSmdh(),
            .cgsrr = ratings.cgsrr.toSmdh(),
        };
    }
};

const RegionLock = struct {
    japan: bool = false,
    north_america: bool = false,
    europe: bool = false,
    australia: bool = false,
    china: bool = false,
    korea: bool = false,
    taiwan: bool = false,

    pub fn initSmdh(lockout: smdh.RegionLock) RegionLock {
        return .{
            .japan = lockout.japan,
            .north_america = lockout.north_america,
            .europe = lockout.europe,
            .australia = lockout.australia,
            .china = lockout.china,
            .korea = lockout.korea,
            .taiwan = lockout.taiwan,
        };
    }

    pub fn toSmdh(lockout: RegionLock) smdh.RegionLock {
        return .{
            .japan = lockout.japan,
            .north_america = lockout.north_america,
            .europe = lockout.europe,
            .australia = lockout.australia,
            .china = lockout.china,
            .korea = lockout.korea,
            .taiwan = lockout.taiwan,
        };
    }
};

const Flags = struct {
    visible: bool = true,
    autoboot: bool = false,
    allow_3d: bool = false,
    require_eula: bool = false,
    autosave: bool = false,
    extended_banner: bool = false,
    required_game_rating: bool = false,
    uses_save_data: bool = false,
    record_app_usage: bool = false,
    disable_sd_backups: bool = false,
    new_3ds_exclusive: bool = false,

    pub fn initSmdh(flags: smdh.Flags) Flags {
        return .{
            .visible = flags.visible,
            .allow_3d = flags.allow_3d,
            .autoboot = flags.autoboot,
            .require_eula = flags.require_eula,
            .autosave = flags.autosave,
            .extended_banner = flags.extended_banner,
            .required_game_rating = flags.required_game_rating,
            .uses_save_data = flags.uses_save_data,
            .record_app_usage = flags.record_app_usage,
            .disable_sd_backups = flags.disable_sd_backups,
            .new_3ds_exclusive = flags.new_3ds_exclusive,
        };
    }

    pub fn toSmdh(flags: Flags) smdh.Flags {
        return .{
            .visible = flags.visible,
            .allow_3d = flags.allow_3d,
            .autoboot = flags.autoboot,
            .require_eula = flags.require_eula,
            .autosave = flags.autosave,
            .extended_banner = flags.extended_banner,
            .required_game_rating = flags.required_game_rating,
            .uses_save_data = flags.uses_save_data,
            .record_app_usage = flags.record_app_usage,
            .disable_sd_backups = flags.disable_sd_backups,
            .new_3ds_exclusive = flags.new_3ds_exclusive,
        };
    }
};

const EulaVersion = smdh.EulaVersion;

titles: Titles,
ratings: Ratings = .{},
region_lockout: ?RegionLock = null,
flags: Flags = .{},
eula_version: EulaVersion = .{},
matchmaking_id: u32 = 0,
matchmaking_bit_id: u64 = 0,
optimal_animation_frame: f32 = 0,
streetpass_id: u32 = 0,

pub fn initSmdh(in_smdh: smdh.Smdh, arena: std.mem.Allocator) !ApplicationSettings {
    const settings = in_smdh.settings;

    const english = in_smdh.titles[@intFromEnum(smdh.Language.english)];
    const japanese = in_smdh.titles[@intFromEnum(smdh.Language.japanese)];
    const french = in_smdh.titles[@intFromEnum(smdh.Language.french)];
    const german = in_smdh.titles[@intFromEnum(smdh.Language.german)];
    const italian = in_smdh.titles[@intFromEnum(smdh.Language.italian)];
    const spanish = in_smdh.titles[@intFromEnum(smdh.Language.spanish)];
    const simplified_chinese = in_smdh.titles[@intFromEnum(smdh.Language.simplified_chinese)];
    const korean = in_smdh.titles[@intFromEnum(smdh.Language.korean)];
    const dutch = in_smdh.titles[@intFromEnum(smdh.Language.dutch)];
    const portuguese = in_smdh.titles[@intFromEnum(smdh.Language.portuguese)];
    const russian = in_smdh.titles[@intFromEnum(smdh.Language.russian)];
    const traditional_chinese = in_smdh.titles[@intFromEnum(smdh.Language.traditional_chinese)];

    return .{
        .ratings = Ratings.initSmdh(settings.region_ratings),
        .titles = .{
            .english = try Title.initSmdh(english, arena),
            .japanese = if (std.meta.eql(english, japanese)) null else try Title.initSmdh(japanese, arena),
            .french = if (std.meta.eql(english, french)) null else try Title.initSmdh(french, arena),
            .german = if (std.meta.eql(english, german)) null else try Title.initSmdh(german, arena),
            .italian = if (std.meta.eql(english, italian)) null else try Title.initSmdh(italian, arena),
            .spanish = if (std.meta.eql(english, spanish)) null else try Title.initSmdh(spanish, arena),
            .simplified_chinese = if (std.meta.eql(english, simplified_chinese)) null else try Title.initSmdh(simplified_chinese, arena),
            .korean = if (std.meta.eql(english, korean)) null else try Title.initSmdh(korean, arena),
            .dutch = if (std.meta.eql(english, dutch)) null else try Title.initSmdh(dutch, arena),
            .portuguese = if (std.meta.eql(english, portuguese)) null else try Title.initSmdh(portuguese, arena),
            .russian = if (std.meta.eql(english, russian)) null else try Title.initSmdh(russian, arena),
            .traditional_chinese = if (std.meta.eql(english, traditional_chinese)) null else try Title.initSmdh(traditional_chinese, arena),
        },
        .region_lockout = RegionLock.initSmdh(settings.region_lockout),
        .flags = Flags.initSmdh(settings.flags),
        .eula_version = settings.eula_version,
        .matchmaking_id = settings.matchmaking_id,
        .matchmaking_bit_id = settings.matchmaking_bit_id,
        .optimal_animation_frame = settings.optimal_animation_default_frame,
        .streetpass_id = settings.cec_id,
    };
}

pub fn toSmdh(app_settings: ApplicationSettings, icons: smdh.Icons) !smdh.Smdh {
    const english = try app_settings.titles.english.toSmdh();
    const japanese = if (app_settings.titles.japanese) |t| try t.toSmdh() else english;
    const french = if (app_settings.titles.french) |t| try t.toSmdh() else english;
    const german = if (app_settings.titles.german) |t| try t.toSmdh() else english;
    const italian = if (app_settings.titles.italian) |t| try t.toSmdh() else english;
    const spanish = if (app_settings.titles.spanish) |t| try t.toSmdh() else english;
    const simplified_chinese = if (app_settings.titles.simplified_chinese) |t| try t.toSmdh() else english;
    const korean = if (app_settings.titles.korean) |t| try t.toSmdh() else english;
    const dutch = if (app_settings.titles.dutch) |t| try t.toSmdh() else english;
    const portuguese = if (app_settings.titles.portuguese) |t| try t.toSmdh() else english;
    const russian = if (app_settings.titles.russian) |t| try t.toSmdh() else english;
    const traditional_chinese = if (app_settings.titles.traditional_chinese) |t| try t.toSmdh() else english;

    return smdh.Smdh{
        .titles = [_]smdh.Title{
            japanese,
            english,
            french,
            german,
            italian,
            spanish,
            simplified_chinese,
            korean,
            dutch,
            portuguese,
            russian,
            traditional_chinese,
        } ++ (.{std.mem.zeroes(smdh.Title)} ** 4),
        .settings = smdh.Settings{
            .region_ratings = app_settings.ratings.toSmdh(),
            .region_lockout = if (app_settings.region_lockout) |lockout| lockout.toSmdh() else .free,
            .matchmaking_id = app_settings.matchmaking_id,
            .matchmaking_bit_id = app_settings.matchmaking_bit_id,
            .flags = app_settings.flags.toSmdh(),
            .eula_version = app_settings.eula_version,
            .optimal_animation_default_frame = app_settings.optimal_animation_frame,
            .cec_id = app_settings.streetpass_id,
        },
        .icons = icons,
    };
}

test ApplicationSettings {
    try ziggy.schema.checkType(ApplicationSettings, @embedFile("settings.ziggy-schema"));
}

const std = @import("std");
const ziggy = @import("ziggy");
const zitrus_tooling = @import("zitrus-tooling");
const smdh = zitrus_tooling.smdh;
