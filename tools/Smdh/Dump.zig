pub const description = "Dump a SMDH file to its settings and icons";

pub const descriptions: plz.Descriptions(@This()) = .{
    .settings = "Application settings output filename",
    .large = "Large icon output filename",
    .small = "Small icon output filename",
};

pub const short: plz.Short(@This()) = .{
    .settings = 'a',
    .large = 'l',
    .small = 's',
};

settings: ?[]const u8,
large: ?[]const u8,
small: ?[]const u8,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Dump, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |input|
        .{ cwd.openFile(io, input, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ input, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    var smdh_buf: [@sizeOf(smdh.Smdh)]u8 = undefined;
    var input_reader = input_file.readerStreaming(io, &smdh_buf);

    if (args.settings == null and args.large == null and args.small == null) {
        _ = try input_reader.interface.discardRemaining();
        return 0;
    }

    const info = try input_reader.interface.takeStruct(smdh.Smdh, .little);

    if (args.settings) |path| {
        const app_settings = try Settings.initSmdh(info, arena);

        const out = cwd.createFile(io, path, .{}) catch |err| {
            log.err("could not create output settings file '{s}': {t}", .{ path, err });
            return 1;
        };
        defer out.close(io);

        var buf: [2048]u8 = undefined;
        var out_writer = out.writer(io, &buf);
        const writer = &out_writer.interface;

        try std.zon.stringify.serialize(app_settings, .{
            .whitespace = true,
            .emit_default_optional_fields = false,
        }, writer);

        try writer.flush();
    }

    // var write_buffer: [4096]u8 = undefined;
    inline for (&.{ args.small, args.large }, &.{ &info.icons.small, &info.icons.large }, &.{ smdh.Icons.small_size, smdh.Icons.large_size }) |out_icon_path, icon, icon_size| if (out_icon_path) |path| {
        _ = icon_size;
        _ = icon;
        _ = path;
        if (true) @panic("Regressed until zigimg updates"); // XXX: Wait until zigimg updates
        // var out = try zigimg.Image.create(arena, icon_size, icon_size, .rgb565);
        // defer out.deinit(arena);
        //
        // // XXX: we allocate too much, shouldn't we able to convert in-place also here?
        // pica.morton.convert(.untile, 8,  icon_size, @sizeOf(Rgb565), @ptrCast(out.pixels.rgb565), @ptrCast(icon));
        //
        // try out.convert(arena, .rgb24);
        // try out.writeToFilePath(arena, path, &write_buffer, .{ .png = .{} });
    };

    return 0;
}

const Rgb565 = pica.ColorFormat.Rgb565;

const Dump = @This();
const log = std.log.scoped(.smdh);

const Settings = @import("Settings.zig");

const std = @import("std");
const plz = @import("plz");
// const zigimg = @import("zigimg");
const zitrus = @import("zitrus");
const smdh = zitrus.horizon.fmt.ncch.smdh;
const pica = zitrus.hardware.pica;
