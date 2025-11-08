const Applets = union(enum) {
    explain: @import("Explain.zig"),
    smdh: @import("Smdh.zig"),
    exefs: @import("ExeFs.zig"),
    romfs: @import("RomFs.zig"),
    ncch: @import("Ncch.zig"),
    @"3dsx": @import("3dsx.zig"),
    firm: @import("Firm.zig"),
    pica: @import("Pica.zig"),
    compress: @import("Compress.zig"),
    archive: @import("Archive.zig"),
    layout: @import("Layout.zig"),
};

const Arguments = struct {
    pub const description =
        \\Tool suite for working with different 3DS-related things.
    ;

    pub const descriptions = .{
        .version = "Print version number and exit",
    };

    pub const switches = .{
        .version = 'v',
    };

    version: bool,
    @"-": ?Applets,
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

    const arguments = zdap.Parser.parse(Arguments, "zitrus", args, .{});

    if (arguments.version) {
        var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
        try stdout_writer.interface.writeAll(config.version ++ "\n");
        return 0;
    }

    if (arguments.@"-" == null) {
        std.log.info("access the help menu with 'zitrus -h'\n", .{});
        return 0;
    }

    return switch (arguments.@"-".?) {
        inline else => |a| a.main(arena),
    };
}

comptime {
    _ = Applets;
}

const std = @import("std");
const zdap = @import("zdap");

const zitrus = @import("zitrus");
const config = @import("zitrus-config");
