const Subcommand = enum {
    exefs,
    info,
};

const Self = @This();

pub const description = "Extract / Make / Show NCCH (CXI/CFA) files";

pub const Arguments = struct {
    pub const description = Self.description;

    command: union(Subcommand) {
        pub const descriptions = .{
            .exefs = exefs_main.Arguments.description,
            .info = "Show info about an NCCH",
        };

        exefs: exefs_main.Arguments,
        info: struct {
            positional: struct {
                pub const descriptions = .{
                    .ncch = "The NCCH file",
                };

                ncch: []const u8,
            },
        },
    },
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    const cwd = std.fs.cwd();

    return switch (arguments.command) {
        .exefs => |args| exefs_main.main(arena, args),
        .info => |i| m: {
            const ncch_path = i.positional.ncch;
            const ncch_file = cwd.openFile(ncch_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open ncch '{s}': {s}\n", .{ ncch_path, @errorName(err) });
                break :m 1;
            };
            defer ncch_file.close();

            var buf: [4096]u8 = undefined;
            var ncch_reader = ncch_file.reader(&buf);
            const reader = &ncch_reader.interface;

            const header = try reader.peekStruct(ncch.Header, .little);

            if (!std.mem.eql(u8, &header.magic, ncch.magic)) {
                std.debug.print("invalid/corrupted ncch '{s}', header magic check failed\n", .{ncch_path});
                break :m 1;
            }

            // XXX: Use zon stringify
            std.debug.print(
                \\.{{
                \\    .signature = .{X},
                \\    .partition_id = 0x{X:0>16},
                \\    .version = .{s},
                \\    .program_id = 0x{X:0>16},
                \\    .product_code = {s},
                \\    .extended_header_hash = .{X},
                \\    .extended_header_size = 0x{X},
                \\    .plain_region_offset = 0x{X},
                \\    .plain_region_size = 0x{X},
                \\    .exefs_offset = 0x{X},
                \\    .exefs_size = 0x{X},
                \\    .exefs_hash_region_size = 0x{X},
                \\    .romfs_offset = 0x{X},
                \\    .romfs_size = 0x{X},
                \\    .romfs_hash_region_size = 0x{X},
                \\    .exefs_superblock_hash = .{X},
                \\    .romfs_superblock_hash = .{X},
                \\}}
                \\
            , .{
                header.signature,
                header.partition_id,
                @tagName(header.version),
                header.program_id,
                header.product_code,
                header.extended_header_hash,
                header.extended_header_size,
                header.plain_region_offset,
                header.plain_region_size,
                header.exefs_offset,
                header.exefs_size,
                header.exefs_hash_region_size,
                header.romfs_offset,
                header.romfs_size,
                header.romfs_hash_region_size,
                header.exefs_superblock_hash,
                header.romfs_superblock_hash,
            });

            break :m 0;
        },
    };
}

const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;

const exefs_main = @import("exefs-main.zig");
