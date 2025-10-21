pub const description = "Make a SMDH file from its settings and icons";

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
};

pub const switches = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .settings = "Application settings, in zon",
        .large = "48x48 icon",
        .small = "24x24 icon, if none a downscaled version of the 48x48 icon is used",
    };

    settings: []const u8,
    large: []const u8,
    small: ?[]const u8,
},

pub fn main(args: Make, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();
    const settings_code = code: {
        const file = cwd.openFile(args.@"--".settings, .{ .mode = .read_only }) catch |err| {
            log.err("could not open settings file '{s}': {s}\n", .{ args.@"--".settings, @errorName(err) });
            return 1;
        };
        defer file.close();

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&buffer);
        const file_size = try file_reader.getSize();
        const code = try arena.allocWithOptions(u8, file_size, null, 0);
        try file_reader.interface.readSliceAll(code);

        break :code code;
    };
    defer arena.free(settings_code);

    var diagnostic: std.zon.parse.Diagnostics = .{};
    defer diagnostic.deinit(arena);

    const app_settings = std.zon.parse.fromSlice(Settings, arena, settings_code, &diagnostic, .{}) catch |err| switch (err) {
        error.ParseZon => {
            log.err("error parsing '{s}':\n{f}", .{ args.@"--".settings, diagnostic });
            return 1;
        },
        else => return err,
    };

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    const large_icon_path = args.@"--".large;
    const possibly_small_icon_path = args.@"--".small;

    const icons = loadIcons(arena, large_icon_path, possibly_small_icon_path) catch |err| {
        log.err("could not convert icon files due to: {t}", .{err});
        return 1;
    };

    const final_smdh = app_settings.toSmdh(icons) catch |err| {
        log.err("could not make final smdh: {t}", .{err});
        return err;
    };

    var out_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&out_buffer);
    const out = &output_writer.interface;

    try out.writeStruct(final_smdh, .little);
    try out.flush();
    return 0;
}

fn loadIconWithSize(size: usize, arena: std.mem.Allocator, path: []const u8) !zigimg.Image {
    var read_buffer: [4096]u8 = undefined;
    var img = zigimg.Image.fromFilePath(arena, path, &read_buffer) catch |err| {
        log.err("could not open icon file '{s}': {t}", .{ path, err });
        return err;
    };
    errdefer img.deinit(arena);

    if (img.width != img.height or img.width != size) return error.InvalidIconDimensions;

    try img.convert(arena, .rgb565);
    return img;
}

fn loadIcons(arena: std.mem.Allocator, large_path: []const u8, small_path: ?[]const u8) !smdh.Icons {
    var icons: smdh.Icons = std.mem.zeroes(smdh.Icons);

    var large_image = try loadIconWithSize(smdh.Icons.large_size, arena, large_path);
    defer large_image.deinit(arena);

    common.tileImage(.tile, smdh.Icons.large_size, @alignCast(std.mem.bytesAsSlice(Rgb565, &icons.large)), @ptrCast(large_image.pixels.rgb565));

    if (small_path) |path| {
        var small_image = try loadIconWithSize(smdh.Icons.small_size, arena, path);
        defer small_image.deinit(arena);

        common.tileImage(.tile, smdh.Icons.small_size, @alignCast(std.mem.bytesAsSlice(Rgb565, &icons.small)), @ptrCast(small_image.pixels.rgb565));
    } else {
        var downsampled = try zigimg.Image.create(arena, smdh.Icons.small_size, smdh.Icons.small_size, .rgb565);
        defer downsampled.deinit(arena);

        // XXX: I think zigimg should have a resize function, I'll cook something when I have time if nothing is done
        const image_pixels: []Rgb565 = @ptrCast(large_image.pixels.rgb565);
        const downsampled_pixels: []Rgb565 = @ptrCast(downsampled.pixels.rgb565);
        for (0..smdh.Icons.small_size) |y| {
            for (0..smdh.Icons.small_size) |x| {
                const px1 = image_pixels[(2 * y) * smdh.Icons.large_size + (2 * x)];
                const px2 = image_pixels[(2 * y) * smdh.Icons.large_size + (2 * x) + 1];
                const px3 = image_pixels[((2 * y) + 1) * smdh.Icons.large_size + (2 * x)];
                const px4 = image_pixels[((2 * y) + 1) * smdh.Icons.large_size + (2 * x) + 1];

                const downsampled_pixel = Rgb565{
                    .r = @intCast((@as(usize, px1.r) + px2.r + px3.r + px4.r) / 4),
                    .g = @intCast((@as(usize, px1.g) + px2.g + px3.g + px4.g) / 4),
                    .b = @intCast((@as(usize, px1.b) + px2.b + px3.b + px4.b) / 4),
                };

                downsampled_pixels[y * smdh.Icons.small_size + x] = downsampled_pixel;
            }
        }

        common.tileImage(.tile, smdh.Icons.small_size, @alignCast(std.mem.bytesAsSlice(Rgb565, &icons.small)), downsampled_pixels);
    }

    return icons;
}

const Rgb565 = pica.ColorFormat.Rgb565;

const Make = @This();
const log = std.log.scoped(.smdh);

const common = @import("common.zig");
const Settings = @import("Settings.zig");

const std = @import("std");
const zigimg = @import("zigimg");
const zitrus = @import("zitrus");
const smdh = zitrus.horizon.fmt.smdh;
const pica = zitrus.hardware.pica;
