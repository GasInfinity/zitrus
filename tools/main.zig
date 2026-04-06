pub const description =
    \\Tool suite for working with different 3DS-related things.
;

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

pub const descriptions: plz.Descriptions(Main) = .{
    .version = "Print version number and exit",
};

pub const short: plz.Short(Main) = .{
    .version = 'v',
};

version: ?void,
@"-": ?Applets,

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    var diagnostic: plz.Diagnostic = undefined;
    @setEvalBranchQuota(2000);
    const arguments = plz.parseSlice(Main, "zitrus", &diagnostic, args[1..]) catch {
        const stderr = try io.lockStderr(&.{}, null);
        defer io.unlockStderr();

        try diagnostic.render(stderr.terminal(), .default);
        try stderr.file_writer.interface.flush();
        return if (diagnostic.kind == .help) 0 else 1;
    };

    if (arguments.version) |_| {
        var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
        try stdout_writer.interface.writeAll(config.version ++ "\n");
        return 0;
    }

    if (arguments.@"-" == null) {
        const stderr = try io.lockStderr(&.{}, null);
        defer io.unlockStderr();

        const help: plz.Help = .of(Main, "zitrus");
        try help.render(stderr.terminal(), .default);
        return 0;
    }

    return switch (arguments.@"-".?) {
        inline else => |a| a.run(io, arena),
    };
}

comptime {
    _ = Applets;
}

const Main = @This();

const std = @import("std");
const plz = @import("plz");

const Io = std.Io;

const zitrus = @import("zitrus");
const config = @import("zitrus-config");
