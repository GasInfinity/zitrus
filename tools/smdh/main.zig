// TODO: better file error handling (too much duplicated code)
const Self = @This();
const Subcommand = enum { make, dump };

pub const description = "make / dump smdh files with its settings and icon files.";

pub const Arguments = struct {
    pub const description = Self.description;

    command: union(Subcommand) {
        pub const descriptions = .{ .make = "make a smdh file from its settings and icons", .dump = "dump a smdh file to its settings and icons" };

        make: struct {
            positional: struct {
                pub const descriptions = .{
                    .@"out.smdh" = "output smdh",
                    .@"settings.ziggy" = "application settings",
                    .@"48x48" = "large icon (image decode support depends on zigimg)",
                    .@"24x24" = "small icon (optional)",
                };

                @"out.smdh": []const u8,
                @"settings.ziggy": []const u8,
                @"48x48": []const u8,
                @"24x24": ?[]const u8,
            },
        },
        dump: struct {
            pub const descriptions = .{
                .settings = "application settings output filename",
                .@"48x48" = "large icon file output filename",
                .@"24x24" = "small icon file output filename",
            };

            pub const switches = .{
                .settings = 'a',
                .@"48x48" = 'l',
                .@"24x24" = 's',
            };

            settings: ?[]const u8,
            @"48x48": ?[]const u8,
            @"24x24": ?[]const u8,

            positional: struct {
                pub const descriptions = .{
                    .@"in.smdh" = "input smdh",
                };

                @"in.smdh": []const u8,
            },
        },
    },
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    const cwd = std.fs.cwd();
    return switch (arguments.command) {
        .make => |make| m: {
            const settings_path = make.positional.@"settings.ziggy";
            const settings_file = cwd.openFile(settings_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open settings file '{s}': {s}\n", .{ settings_path, @errorName(err) });
                break :m 1;
            };
            defer settings_file.close();

            const settings_code = try settings_file.readToEndAllocOptions(arena, std.math.maxInt(usize), null, @alignOf(u8), 0);
            defer arena.free(settings_code);

            var diagnostic: ziggy.Diagnostic = .{
                .path = settings_path,
                .errors = .{},
            };
            defer diagnostic.deinit(arena);

            const app_settings: ApplicationSettings = ziggy.parseLeaky(ApplicationSettings, arena, settings_code, .{
                .diagnostic = &diagnostic,
            }) catch |err| switch (err) {
                error.Syntax => {
                    std.debug.print("error parsing {s}\n", .{settings_path});
                    try diagnostic.fmt(settings_code).format("", .{}, std.io.getStdErr().writer());
                    break :m 1;
                },
                else => break :m err,
            };

            const large_icon_path = make.positional.@"48x48";
            const possibly_small_icon_path = make.positional.@"24x24";
            const icons = loadIcons(arena, large_icon_path, possibly_small_icon_path) catch |err| {
                std.debug.print("could not convert icon files due to '{s}', halting.\n", .{@errorName(err)});
                break :m 1;
            };
            const final_smdh = app_settings.toSmdh(icons) catch |err| {
                std.debug.print("could not make final smdh: {s}\n", .{@errorName(err)});
                break :m err;
            };

            const out_path = make.positional.@"out.smdh";
            const out = cwd.createFile(out_path, .{}) catch |err| {
                std.debug.print("could not create output file '{s}': {s}\n", .{ out_path, @errorName(err) });
                break :m 1;
            };
            defer out.close();

            try out.writer().writeStructEndian(final_smdh, .little);
            break :m 0;
        },
        .dump => |dump| d: {
            if (dump.settings == null and dump.@"48x48" == null and dump.@"24x24" == null) {
                break :d 0;
            }

            const smdh_path = dump.positional.@"in.smdh";
            const smdh_file = cwd.openFile(smdh_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open smdh file '{s}': {s}\n", .{ smdh_path, @errorName(err) });
                break :d 1;
            };
            defer smdh_file.close();

            const input_smdh = try smdh_file.reader().readStructEndian(smdh.Smdh, .little);

            if (dump.settings) |settings_path| {
                const app_settings = try ApplicationSettings.initSmdh(input_smdh, arena);

                const out = cwd.createFile(settings_path, .{}) catch |err| {
                    std.debug.print("could not create output settings file '{s}': {s}\n", .{ settings_path, @errorName(err) });
                    break :d 1;
                };
                defer out.close();

                var out_buffered_writer = std.io.bufferedWriter(out.writer());

                try ziggy.stringify(app_settings, .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                }, out_buffered_writer.writer());

                try out_buffered_writer.flush();
            }

            inline for(&.{ dump.@"24x24", dump.@"48x48" }, &.{ &input_smdh.icons.small, &input_smdh.icons.large }, &.{ smdh.Icons.small_size,smdh.Icons.large_size }) |out_icon_path, icon, icon_size| if(out_icon_path) |path| {
                var out = try zigimg.ImageUnmanaged.create(arena, icon_size, icon_size, .rgb565);
                defer out.deinit(arena);

                // XXX: we allocate too much, shouldn't we able to convert in-place also here?
                processImage(.untile, icon_size, @ptrCast(out.pixels.rgb565), std.mem.bytesAsSlice(Bgr565, icon));

                try out.convert(arena, .rgb24);
                try out.writeToFilePath(arena, path, .{ .png = .{} }); 
            };

            break :d 0;
        },
    };
}

const Bgr565 = packed struct(u16) { b: u5, g: u6, r: u5 };

// XXX: this allocates too much when we could just convert it once...
fn loadIconWithSize(size: usize, arena: std.mem.Allocator, path: []const u8) !zigimg.ImageUnmanaged {
    var img = zigimg.ImageUnmanaged.fromFilePath(arena, path) catch |err| {
        std.debug.print("could not open icon file '{s}': {s}\n", .{ path, @errorName(err) });
        return err;
    };
    errdefer img.deinit(arena);

    if (img.width != img.height or img.width != size) {
        return error.InvalidIconDimensions;
    }

    try img.convert(arena, .rgb565);
    return img;
}

fn loadIcons(arena: std.mem.Allocator, large_path: []const u8, small_path: ?[]const u8) !smdh.Icons {
    var icons: smdh.Icons = std.mem.zeroes(smdh.Icons);

    var large_image = try loadIconWithSize(smdh.Icons.large_size, arena, large_path);
    defer large_image.deinit(arena);

    processImage(.tile, smdh.Icons.large_size, @alignCast(std.mem.bytesAsSlice(Bgr565, &icons.large)), @ptrCast(large_image.pixels.rgb565));

    if (small_path) |path| {
        var small_image = try loadIconWithSize(smdh.Icons.small_size, arena, path);
        defer small_image.deinit(arena);

        processImage(.tile, smdh.Icons.small_size, @alignCast(std.mem.bytesAsSlice(Bgr565, &icons.small)), @ptrCast(small_image.pixels.rgb565));
    } else {
        var downsampled = try zigimg.ImageUnmanaged.create(arena, smdh.Icons.small_size, smdh.Icons.small_size, .rgb565);
        defer downsampled.deinit(arena);

        // XXX: I think zigimg should have a resize function, I'll cook something when I have time if nothing is done
        const image_pixels: []Bgr565 = @ptrCast(large_image.pixels.rgb565);
        const downsampled_pixels: []Bgr565 = @ptrCast(downsampled.pixels.rgb565);
        for (0..smdh.Icons.small_size) |y| {
            for (0..smdh.Icons.small_size) |x| {
                const px1 = image_pixels[(2 * y) * smdh.Icons.large_size + (2 * x)];
                const px2 = image_pixels[(2 * y) * smdh.Icons.large_size + (2 * x) + 1];
                const px3 = image_pixels[((2 * y) + 1) * smdh.Icons.large_size + (2 * x)];
                const px4 = image_pixels[((2 * y) + 1) * smdh.Icons.large_size + (2 * x) + 1];

                const downsampled_pixel = Bgr565{
                    .r = @intCast((@as(usize, px1.r) + px2.r + px3.r + px4.r) / 4),
                    .g = @intCast((@as(usize, px1.g) + px2.g + px3.g + px4.g) / 4),
                    .b = @intCast((@as(usize, px1.b) + px2.b + px3.b + px4.b) / 4),
                };

                downsampled_pixels[y * smdh.Icons.small_size + x] = downsampled_pixel;
            }
        }

        processImage(.tile, smdh.Icons.small_size, @alignCast(std.mem.bytesAsSlice(Bgr565, &icons.small)), downsampled_pixels);
    }

    return icons;
}

// https://3dbrew.org/wiki/SMDH#Icon_graphics
const tile_size = 8;

const TilingStrategy = enum { tile, untile };

fn processImage(comptime strategy: TilingStrategy, size: usize, dst_pixels: []Bgr565, src_pixels: []const Bgr565) void {
    const tiles = @divExact(size, tile_size);

    var i: u16 = 0;
    for (0..tiles) |y_tile| {
        for (0..tiles) |x_tile| {
            const y_start = y_tile * tile_size;
            const x_start = x_tile * tile_size;

            for (0..(tile_size * tile_size)) |tile| {
                // NOTE: We know the max size is 63 so we can squeeze it into 6 bits
                const x, const y = morton.toDimensions(u6, 2, @intCast(tile));
                const src_pixel, const dst_pixel = switch(strategy) {
                    .tile => .{ &src_pixels[(y_start + y) * size + x_start + x], &dst_pixels[i] },
                    .untile => .{ &src_pixels[i], &dst_pixels[(y_start + y) * size + x_start + x] },
                };

                dst_pixel.* = src_pixel.*;
                i += 1;
            }
        }
    }
}

// https://en.wikipedia.org/wiki/Z-order_curve
// TODO: This can be its own lib...
const morton = struct {
    // Basically bits are interleaved
    // 2-dimensional 8-bits example: yxyxyxyx
    fn toDimensions(comptime T: type, comptime dimensions: usize, morton_index: T) [dimensions]std.meta.Int(.unsigned, @divExact(@bitSizeOf(T), dimensions)) {
        std.debug.assert(@typeInfo(T) == .int);
        const DecomposedInt = std.meta.Int(.unsigned, @divExact(@bitSizeOf(T), dimensions));

        var values: [dimensions]DecomposedInt = @splat(0);
        var current_index = morton_index;
        inline for (0..@bitSizeOf(T)) |i| {
            const shift = i / dimensions;
            const set = &values[i % dimensions];

            set.* |= @intCast((current_index & 0b1) << shift);
            current_index >>= 1;
        }

        return values;
    }
};

comptime {
    _ = ApplicationSettings;
}

const ApplicationSettings = @import("ApplicationSettings.zig");

const std = @import("std");
const ziggy = @import("ziggy");
const zigimg = @import("zigimg");
const zitrus_tooling = @import("zitrus-tooling");
const smdh = zitrus_tooling.horizon.smdh;
