const named_parsers = .{
    .@"out.smdh" = clap.parsers.string,
    .@"settings.ziggy" = clap.parsers.string,
    .@"24x24" = clap.parsers.string,
    .@"48x48" = clap.parsers.string,
};

const cli_params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\<out.smdh>             The output filename
    \\<settings.ziggy>       Application name and settings
    \\<48x48>                Large icon used everywhere else
    \\<24x24>                Small icon shown on top when pausing the app (Optional)
);

const Title = struct {
    title: []const u8,
    description: []const u8,
    publisher: []const u8,
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

    pub const Unrestricted = struct {
        pub const Kind = enum { inactive, pending, unrestricted };

        kind: Kind,
    };

    pub const Restricted = struct {
        age: u5,
    };

    unrestricted: Unrestricted,
    restricted: Restricted,

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
};

const RegionLock = struct {
    japan: bool = false,
    north_america: bool = false,
    europe: bool = false,
    australia: bool = false,
    china: bool = false,
    korea: bool = false,
    taiwan: bool = false,
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
};

const EulaVersion = smdh.EulaVersion;
const ApplicationSettings = struct {
    version: u16 = 0,
    titles: Titles,
    ratings: Ratings = .{},
    region_lockout: ?RegionLock = null,
    flags: Flags = .{},
    eula_version: EulaVersion = .{},
    matchmaking_id: u32 = 0,
    matchmaking_bit_id: u64 = 0,
    optimal_animation_frame: f32 = 0,
    streetpass_id: u32 = 0,
};

fn showHelp(stderr: anytype) !void {
    try std.fmt.format(stderr,
        \\ zitrus - make-smdh
        \\ constructs an smdh from its applications settings and icon files
        \\
        \\
    , .{});
    try clap.help(stderr, clap.Help, &cli_params, .{});
}

pub fn main(arena: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const stderr = std.io.getStdErr().writer();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &cli_params, named_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = arena,
    }) catch |err| {
        try showHelp(stderr);
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null or res.positionals[1] == null) {
        try showHelp(stderr);
        return;
    }

    const output_path = res.positionals[0] orelse unreachable;
    const settings_path = res.positionals[1] orelse unreachable;

    const cwd = std.fs.cwd();
    const output_file = cwd.createFile(output_path, .{}) catch |err| {
        std.debug.print("Could not create output file '{s}': {s}", .{ output_path, @errorName(err) });
        return err;
    };
    defer output_file.close();

    var output_buffered = std.io.bufferedWriter(output_file.writer());

    const settings_file = cwd.openFile(settings_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Settings file '{s}' not found\n", .{settings_path});
            return;
        },
        else => {
            std.debug.print("Could not open input file '{s}': {s}", .{ settings_path, @errorName(err) });
            return err;
        },
    };

    defer settings_file.close();

    const settings_code = try settings_file.readToEndAllocOptions(arena, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer arena.free(settings_code);

    var diagnostic: ziggy.Diagnostic = .{
        .path = settings_path,
        .errors = .{},
    };
    defer diagnostic.deinit(arena);

    const parsed: ApplicationSettings = ziggy.parseLeaky(ApplicationSettings, arena, settings_code, .{
        .diagnostic = &diagnostic,
    }) catch |err| switch (err) {
        error.Syntax => {
            std.debug.print("error parsing {s}\n", .{settings_path});
            try diagnostic.fmt(settings_code).format("", .{}, std.io.getStdErr().writer());
            return;
        },
        else => return err,
    };

    const english = try convertTitle(parsed.titles.english);
    const japanese = if (parsed.titles.japanese) |t| try convertTitle(t) else english;
    const french = if (parsed.titles.french) |t| try convertTitle(t) else english;
    const german = if (parsed.titles.german) |t| try convertTitle(t) else english;
    const italian = if (parsed.titles.italian) |t| try convertTitle(t) else english;
    const spanish = if (parsed.titles.spanish) |t| try convertTitle(t) else english;
    const simplified_chinese = if (parsed.titles.simplified_chinese) |t| try convertTitle(t) else english;
    const korean = if (parsed.titles.korean) |t| try convertTitle(t) else english;
    const dutch = if (parsed.titles.dutch) |t| try convertTitle(t) else english;
    const portuguese = if (parsed.titles.portuguese) |t| try convertTitle(t) else english;
    const russian = if (parsed.titles.russian) |t| try convertTitle(t) else english;
    const traditional_chinese = if (parsed.titles.traditional_chinese) |t| try convertTitle(t) else english;

    // TODO: Icon image conversion
    const icons = try loadIcons(arena, res.positionals[2] orelse "", res.positionals[3]);

    const converted: smdh.Smdh = smdh.Smdh{
        .version = parsed.version,
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
            .region_ratings = .{
                .cero = parsed.ratings.cero.toSmdh(),
                .esrb = parsed.ratings.esrb.toSmdh(),
                .usk = parsed.ratings.usk.toSmdh(),
                .pegi_gen = parsed.ratings.pegi_gen.toSmdh(),
                .pegi_prt = parsed.ratings.pegi_prt.toSmdh(),
                .pegi_bbfc = parsed.ratings.pegi_bbfc.toSmdh(),
                .cob = parsed.ratings.cob.toSmdh(),
                .grb = parsed.ratings.grb.toSmdh(),
                .cgsrr = parsed.ratings.cgsrr.toSmdh(),
            },
            .region_lockout = if (parsed.region_lockout) |lockout| .{
                .japan = lockout.japan,
                .north_america = lockout.north_america,
                .europe = lockout.europe,
                .australia = lockout.australia,
                .china = lockout.china,
                .korea = lockout.korea,
                .taiwan = lockout.taiwan,
            } else .free,
            .matchmaking_id = parsed.matchmaking_id,
            .matchmaking_bit_id = parsed.matchmaking_bit_id,
            .flags = .{
                .visible = parsed.flags.visible,
                .allow_3d = parsed.flags.allow_3d,
                .autoboot = parsed.flags.autoboot,
                .require_eula = parsed.flags.require_eula,
                .autosave = parsed.flags.autosave,
                .extended_banner = parsed.flags.extended_banner,
                .required_game_rating = parsed.flags.required_game_rating,
                .uses_save_data = parsed.flags.uses_save_data,
                .record_app_usage = parsed.flags.record_app_usage,
                .disable_sd_backups = parsed.flags.disable_sd_backups,
                .new_3ds_exclusive = parsed.flags.new_3ds_exclusive,
            },
            .eula_version = parsed.eula_version,
            .optimal_animation_default_frame = parsed.optimal_animation_frame,
            .cec_id = parsed.streetpass_id,
        },
        .icons = icons,
    };

    try output_buffered.writer().writeStructEndian(converted, .little);
    try output_buffered.flush();
}

fn convertTitle(title: Title) !smdh.Title {
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

// TODO
const Bgr565 = packed struct(u16) { b: u5, g: u6, r: u5 };

fn loadIcons(arena: std.mem.Allocator, large_path: []const u8, small_path: ?[]const u8) !smdh.Icons {
    _ = arena;
    _ = large_path;
    _ = small_path;
    return std.mem.zeroes(smdh.Icons);
    // if(small_path == null) {
    //     @panic("TODO: Resize large if small is missing");
    // }
    // _ = small_path; 
    // var icons: smdh.Icons = std.mem.zeroes(smdh.Icons);
    //
    // var large_image = zigimg.ImageUnmanaged.fromFilePath(arena, large_path) catch |err| switch (err) {
    //     error.FileNotFound => {
    //         std.debug.print("Icon file '{s}' not found\n", .{large_path});
    //         return err;
    //     },
    //     else => {
    //         std.debug.print("Could not open icon file '{s}': {s}", .{ large_path, @errorName(err) });
    //         return err;
    //     },
    // };
    // defer large_image.deinit(arena);
    //
    // if(large_image.width != large_image.height or large_image.width != 48) {
    //     return error.InvalidIconDimensions;
    // }
    //
    // try large_image.convert(arena, zigimg.PixelFormat.rgb24);
    // convertIcon(std.mem.bytesAsSlice(Bgr565, &icons.large), large_image.width, large_image.pixels.rgb24);
    // return icons;
}

// https://3dbrew.org/wiki/SMDH#Icon_graphics
// const icon_tile_size = 8;
// fn convertIcon(target: []align(1) Bgr565, size: usize, pixels: []zigimg.color.Rgb24) void {
// }
//

test ApplicationSettings {
    try ziggy.schema.checkType(ApplicationSettings, @embedFile("settings.ziggy-schema"));
}

const std = @import("std");
const clap = @import("clap");
const ziggy = @import("ziggy");
const zigimg = @import("zigimg");
const zitrus_tooling = @import("zitrus-tooling");
const smdh = zitrus_tooling.smdh;
