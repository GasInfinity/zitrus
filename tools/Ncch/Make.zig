// TODO: Split into ncch make cxi / ncch make cfa
pub const description = "Make a NCCH CXI/CFA";

pub const descriptions = .{
    .exe = "ELF executable to use as code",
    .settings = "NCCH settings as .zon",
    .output = "Output filename, if none stdout is used",
};

pub const switches = .{
    .output = 'o',
    .exe = 'm',
};

exe: ?[]const u8 = null,
settings: ?[]const u8 = null,

output: []const u8,

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    if(true) @panic("TODO");

    const cwd = std.fs.cwd();

    if (args.exe == null or args.settings == null) @panic("TODO");

    const settings_zon = cwd.readFileAllocOptions(arena, args.settings.?, std.math.maxInt(u32), null, .@"4", 0) catch |err| {
        std.debug.print("error: could not open settings '{s}': {s}\n", .{ args.settings.?, @errorName(err) });
        return 1;
    };

    defer arena.free(settings_zon);

    var diag: std.zon.parse.Diagnostics = .{};
    @setEvalBranchQuota(2000);
    const settings = std.zon.parse.fromSlice(Settings, arena, settings_zon, &diag, .{}) catch |err| switch (err) {
        error.ParseZon => {
            std.debug.print("error: Parsing zon:\n {f}", .{diag});
            return 1;
        },
        else => return err,
    };

    _ = settings;

    const elf_file = cwd.openFile(args.exe.?, .{ .mode = .read_only }) catch |err| {
        std.debug.print("could not open input executable '{s}': {s}\n", .{ args.exe.?, @errorName(err) });
        return 1;
    };
    defer elf_file.close();

    var elf_reader_buf: [4096]u8 = undefined;
    var elf_reader = elf_file.reader(&elf_reader_buf);

    var processed = try code.extractStaticElfAlloc(&elf_reader, arena);

    if (processed.segments.get(.text) == null) {
        std.debug.print("error: No .text segment\n", .{});
        return 1;
    }

    if (processed.findNonSequentialSegment()) |first_non_sequential| {
        std.debug.print("error: Segments are not sequential! They must follow *text -> rodata -> data*, reason {}\n", .{first_non_sequential});
        return 1;
    }

    if (processed.findNonDataSegmentWithBss()) |first_bss| {
        std.debug.print("error: Non-data segment {} has bss\n", .{first_bss});
        return 1;
    }

    const text = processed.segments.get(.text).?;

    if (text.address != processed.entrypoint) {
        std.debug.print("error: Entrypoint must be the start of .text\n", .{});
        return 1;
    }

    std.debug.print("Entry: 0x{X}\n", .{processed.entrypoint});

    var it = processed.segments.iterator();

    while (it.next()) |seg| {
        std.debug.print("Segment: {}\n", .{seg});
    }

    return 0;
}

comptime {
    _ = Settings;
}

const elf = std.elf;

const Make = @This();
const Settings = @import("Settings.zig");

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;
const code = zitrus.fmt.code;
