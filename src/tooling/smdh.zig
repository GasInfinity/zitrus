// Extra metadata stored in ExeFS and CIA files. Contains the icon, region info, ratings, etc...
// For more info: https://www.3dbrew.org/wiki/SMDH
pub const magic = "SMDH";

pub const Title = extern struct {
    short_description: [0x40]u16,
    long_description: [0x80]u16,
    publisher: [0x40]u16,
};

pub const Language = enum(u4) {
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
};

pub const Rating = packed struct(u8) {
    pub const inactive = Rating{};
    pub const pending = Rating{ .active = true, .rating_pending = true };
    pub const unrestricted = Rating{ .active = true, .no_age_restriction = true };

    age: u5 = 0,
    no_age_restriction: bool = false,
    rating_pending: bool = false,
    active: bool = false,

    pub fn restricted(age: u5) Rating {
        return Rating{ .active = true, .age = age };
    }
};

pub const Ratings = extern struct {
    pub const none = Ratings{};

    cero: Rating = .inactive,
    esrb: Rating = .inactive,
    _reserved0: u8 = 0,
    usk: Rating = .inactive,
    pegi_gen: Rating = .inactive,
    _reserved1: u8 = 0,
    pegi_prt: Rating = .inactive,
    pegi_bbfc: Rating = .inactive,
    cob: Rating = .inactive,
    grb: Rating = .inactive,
    cgsrr: Rating = .inactive,
    _reserved2: [5]u8 = @splat(0),
};

pub const RegionLock = packed struct(u32) {
    pub const free: RegionLock = @bitCast(@as(u32, 0x7fffffff));

    japan: bool = false,
    north_america: bool = false,
    europe: bool = false,
    australia: bool = false,
    china: bool = false,
    korea: bool = false,
    taiwan: bool = false,
    _reserved0: u25 = 0,
};

pub const Flags = packed struct(u32) {
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
    _reserved0: u21 = 0,
};

pub const EulaVersion = extern struct {
    major: u8 = 0,
    minor: u8 = 0,
};

pub const Settings = extern struct {
    region_ratings: Ratings = .none,
    region_lockout: RegionLock = .free,
    matchmaking_id: u32 = 0,
    matchmaking_bit_id: u64 = 0,
    flags: Flags = Flags{},
    eula_version: EulaVersion = EulaVersion{},
    _reserved0: u16 = 0,
    optimal_animation_default_frame: f32 = 0,
    cec_id: u32 = 0,
};

pub const Icons = extern struct {
    small: [0x480]u8,
    large: [0x1200]u8,
};

pub const Smdh = extern struct {
    magic: [magic.len]u8 = magic.*,
    version: u16,
    _reserved0: u16 = 0,
    titles: [(1 << @bitSizeOf(Language))]Title,
    settings: Settings,
    _reserved1: u64 = 0,
    icons: Icons,
};

const std = @import("std");

comptime {
    std.debug.assert(@sizeOf(Title) == 0x200);
    std.debug.assert(@sizeOf(Icons) == 0x1680);
    std.debug.assert(@sizeOf(Smdh) == 0x36C0);
}
