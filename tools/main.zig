const AppletSubCommand = t: {
    const applets_info = @typeInfo(applets).@"struct";
    var applet_fields: [applets_info.decls.len]std.builtin.Type.EnumField = undefined;

    var i = 0;
    for (applets_info.decls) |applet| {
        applet_fields[i] = .{
            .name = applet.name,
            .value = i,
        };

        i += 1;
    }

    break :t @Type(std.builtin.Type{ .@"enum" = std.builtin.Type.Enum{
        .tag_type = u32,
        .fields = &applet_fields,
        .decls = &.{},
        .is_exhaustive = true,
    }});
};

const comma_separated_names = c: {
    const all_applets = std.enums.values(AppletSubCommand);
    var total_len = 0;
    var i = 0;
    for (all_applets) |applet| {
        total_len += @tagName(applet).len;
        i += 1;

        if (i < all_applets.len) {
            total_len += ", ".len;
        }
    }

    var names: [total_len]u8 = undefined;

    i = 0;
    for (all_applets) |applet| {
        const name = @tagName(applet);
        @memcpy(names[i..][0..name.len], name);

        i += name.len;
        if (i < names.len) {
            @memcpy(names[i..][0..2], ", ");

            i += 2;
        }
    }

    break :c names;
};

const main_parsers = .{ .applet = clap.parsers.enumeration(AppletSubCommand) };
const main_params = clap.parseParamsComptime(std.fmt.comptimePrint(
    \\-h, --help  Display this help and exit.
    \\<applet>    The applet/subcommand to run [available applets: {s}]
    \\
, .{comma_separated_names}));

const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

fn showHelp(stderr: anytype) !void {
    try std.fmt.format(stderr,
        \\ zitrus - tools
        \\
    , .{});
    try clap.help(stderr, clap.Help, &main_params, .{});
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(arena);
    defer iter.deinit();

    // Skip program name
    _ = iter.next();

    const stderr = std.io.getStdErr().writer();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = arena,
        .terminating_positional = 0,
    }) catch |err| {
        try showHelp(stderr);
        diag.report(stderr, err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) {
        try showHelp(stderr);
        return;
    }

    const applet = res.positionals[0].?;

    return switch (applet) {
        inline else => |a| @call(.auto, @field(applets, @tagName(a)).main, .{ arena, &iter }),
    };
}

test {
    std.testing.refAllDeclsRecursive(applets);
}

const applets = @import("applets.zig");

const std = @import("std");
const clap = @import("clap");
