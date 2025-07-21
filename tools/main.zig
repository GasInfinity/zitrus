const AppletSubCommand = t: {
    const applets_decls = @typeInfo(applets).@"struct".decls;
    var applet_fields: [applets_decls.len]std.builtin.Type.EnumField = undefined;

    var i = 0;
    for (applets_decls) |applet| {
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
    } });
};

// NOTE: I initially did it at comptime, however zig does not support adding decls at comptime and I cannot set the descriptions struct :(
// At least we get comptime checking when adding a new applet...
const AppletSubcommandArguments = union(AppletSubCommand) {
    pub const descriptions = (d: {
        const defined_applets = std.enums.values(AppletSubCommand);
        var applet_descriptions: [defined_applets.len]std.builtin.Type.StructField = undefined;

        for (defined_applets, 0..) |applet, i| {
            const applet_name = @tagName(applet);
            const applet_namespace = @field(applets, applet_name);

            if (!@hasDecl(applet_namespace, "description")) {
                @compileError("applet " ++ applet_name ++ " does not have a description!");
            }

            applet_descriptions[i] = .{
                .name = applet_name,
                .type = []const u8,
                .default_value_ptr = @ptrCast(&@as([]const u8, @field(applet_namespace, "description"))),
                .is_comptime = false,
                .alignment = @alignOf([]const u8),
            };
        }

        break :d @Type(std.builtin.Type{ .@"struct" = .{
            .layout = .auto,
            .fields = &applet_descriptions,
            .decls = &.{},
            .is_tuple = false,
        } });
    }){};

    @"3dsx": applets.@"3dsx".Arguments,
    smdh: applets.smdh.Arguments,
    pica: applets.pica.Arguments,
    explain: applets.explain.Arguments,
    ncch: applets.ncch.Arguments,
};

const Arguments = struct {
    pub const description =
        \\tools to dump / make different 3ds related files.
    ;

    command: AppletSubcommandArguments,
};

pub fn main() !u8 {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);

    var diagnostics: flags.Diagnostics = undefined;
    const arguments = flags.parse(args, "zitrus-tools", Arguments, .{
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.PrintedHelp => return 0,
        error.EmptyArgument, error.MissingArgument, error.MissingCommand, error.MissingFlag, error.MissingValue, error.UnexpectedPositional, error.UnrecognizedArgument, error.UnrecognizedFlag, error.UnrecognizedOption, error.UnrecognizedSwitch => {
            try diagnostics.printUsage(&flags.ColorScheme.default);
            return 1;
        },
        else => {
            std.debug.print("Encountered unknown error while parsing for command '{s}': {s}", .{ diagnostics.command_name, @errorName(err) });
            return 1;
        },
    };

    const applet = std.meta.activeTag(arguments.command);

    return switch (applet) {
        inline else => |a| @call(.auto, @field(applets, @tagName(a)).main, .{ arena, @field(arguments.command, @tagName(a)) }),
    };
}

test {
    std.testing.refAllDeclsRecursive(applets);
}

const applets = @import("applets.zig");

const std = @import("std");
const flags = @import("flags");
