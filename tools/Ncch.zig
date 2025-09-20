pub const description = "Extract / Make / Show NCCH (CXI/CFA) files";

const Subcommand = enum {
    info,
};

pub const Info = struct {
    pub const description = "Show info about an NCCH";

    @"--": struct {
        pub const descriptions = .{
            .ncch = "The NCCH file",
        };

        ncch: []const u8,
    },
};

@"-": union(Subcommand) {
    info: Info,
},

pub fn main(args: Ncch, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    _ = arena;
    return switch (args.@"-") {
        .info => |i| m: {
            const ncch_path = i.@"--".ncch;
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

const Ncch = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const ncch = zitrus.horizon.fmt.ncch;

const ExeFs = @import("ExeFs.zig");
const RomFs = @import("RomFs.zig");
