pub const description = "Make an executable NCCH (.CXI)";

pub const descriptions = .{
    .elf = "ELF executable to use as code",
    .settings = "NCCH settings as .zon",
    .output = "Output filename, if none stdout is used",
};

pub const switches = .{
    .elf = 'e',
    .settings = 's',
    .output = 'o',
};

elf: []const u8,
settings: []const u8,
romfs: ?[]const u8,

output: ?[]const u8,

pub fn main(args: Cxi, arena: std.mem.Allocator) !u8 {
    if (true) @panic("TODO");
    // XXX: We must first parse the IVFC unless we want to suffer.
    if (args.romfs != null) @panic("TODO");

    const cwd = std.fs.cwd();
    const settings_zon = cwd.readFileAllocOptions(arena, args.settings, std.math.maxInt(u32), null, .@"4", 0) catch |err| {
        log.err("could not open settings '{s}': {t}", .{ args.settings, err });
        return 1;
    };
    defer arena.free(settings_zon);

    var diag: std.zon.parse.Diagnostics = .{};
    @setEvalBranchQuota(2000);
    const settings = std.zon.parse.fromSlice(Settings, arena, settings_zon, &diag, .{}) catch |err| switch (err) {
        error.ParseZon => {
            log.err("could not parse zon:\n {f}", .{diag});
            return 1;
        },
        else => return err,
    };
    defer settings.deinit(arena);

    const elf_file = cwd.openFile(args.elf, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input elf '{s}': {t}", .{ args.elf, err });
        return 1;
    };
    defer elf_file.close();

    var elf_reader_buf: [4096]u8 = undefined;
    var elf_reader = elf_file.reader(&elf_reader_buf);

    var processed = try code.Info.extractStaticElfAlloc(&elf_reader, arena);

    if (processed.segments.get(.text) == null) {
        log.err("no .text segment\n", .{});
        return 1;
    }

    if (processed.findNonSequentialSegment()) |first_non_sequential| {
        log.err("segments are not sequential! They must follow *text -> rodata -> data*, reason {}", .{first_non_sequential});
        return 1;
    }

    if (processed.findNonDataSegmentWithBss()) |first_bss| {
        log.err("non-data segment {} has bss", .{first_bss});
        return 1;
    }

    const text = processed.segments.get(.text).?;

    if (text.address != processed.entrypoint) {
        log.err("entrypoint must be the start of .text", .{});
        return 1;
    }

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&output_buffer);
    const out = &output_writer.interface;

    const title_id: horizon.fmt.title.Id = .{
        .variation = settings.title_id.variation,
        .unique = settings.title_id.unique,
        .category = @bitCast(settings.title_id.category),
        .platform = .@"3ds",
    };

    const has_romfs_included = false;

    var uncompressed_code: std.Io.Writer.Allocating = .init(arena);
    defer uncompressed_code.deinit();

    try processed.alignedStream(&uncompressed_code.writer, &elf_reader, .fromByteUnits(horizon.heap.page_size));

    const text_address = processed.segments.get(.text).?.address;
    const text_size = processed.segments.get(.text).?.memory_size;
    const text_aligned_size = std.mem.alignForward(u32, text_size, zitrus.horizon.heap.page_size);
    const rodata_size = if (processed.segments.get(.rodata)) |rodata| rodata.memory_size else 0;
    const rodata_aligned_size = std.mem.alignForward(u32, rodata_size, zitrus.horizon.heap.page_size);
    const data_size, const bss_size = if (processed.segments.get(.data)) |data| .{ data.file_size, data.memory_size - data.file_size } else .{ 0, 0 };
    const data_aligned_size = std.mem.alignForward(u32, data_size, zitrus.horizon.heap.page_size);

    // NOTE: Diffing in ImHEX the ACI and AccessDesc, it seems its literally 1:1 but with the Ideal Processor (bitmask) and ¿Priority, wtf? changed.
    const extended_header: ncch.ExtendedHeader = .{
        .system_control = .{
            .application_title = zitrus.fmt.fixedArrayFromSlice(u8, 8, settings.title),
            .flags = .{
                .compressed_code = false, // TODO: LzRev compression
                .allow_sd_usage = settings.flags.allow_sd_usage,
            },
            .remaster_version = 0,
            .text = .{
                .address = text_address,
                .physical_region_size = text_aligned_size,
                .size = text_size,
            },
            .stack_size = settings.stack_size,
            .rodata = .{
                .address = text_address + text_aligned_size,
                .physical_region_size = rodata_aligned_size,
                .size = rodata_size,
            },
            .data = .{
                .address = text_address + text_aligned_size + rodata_aligned_size,
                .physical_region_size = data_aligned_size,
                .size = data_size,
            },
            .bss = bss_size,
            .dependency_titles = zitrus.fmt.fixedArrayFromSlice(u64, 64, settings.dependencies),
            .system_info = .{
                .save_data_size = settings.save_data_size,
                .jump_id = title_id,
            },
        },
        .access_control = .{
            .user_capabilities = .{
                .title_id = title_id,
                .core_version = 2,
                .new_speedup = .{
                    .enable_l2_cache = settings.access_control.new_speedup.enable_l2_cache,
                    .cpu_speed = @enumFromInt(@intFromEnum(settings.access_control.new_speedup.cpu_speed)),
                },
                .new_execution = .{ .mode = @enumFromInt(@intFromEnum(settings.access_control.new_execution.mode)) },
                .execution = .{
                    .ideal_processor = settings.access_control.execution.ideal_processor,
                    .affinity_mask = settings.access_control.execution.affinity_mask,
                    .mode = settings.access_control.execution.mode,
                },
                .priority = settings.access_control.execution.priority,
                // TODO: ResourceLimits, what index is what?
                .resource_limits = @splat(0),
                .storage = .{
                    .extended_save_data_id = settings.access_control.storage.extended_save_data_id,
                    .system_save_data_id = settings.access_control.storage.save_data_id,
                    .storage_accessible_uuid = settings.access_control.storage.save_data_id,
                    .access = .{
                        .system_application = settings.access_control.storage.access.system_application,
                        .hardware_check = settings.access_control.storage.access.hardware_check,
                        .filesystem_tool = settings.access_control.storage.access.filesystem_tool,
                        .debug = settings.access_control.storage.access.debug,
                        .twl_card_backup = settings.access_control.storage.access.twl_card_backup,
                        .twl_nand_data = settings.access_control.storage.access.twl_nand_data,
                        .boss = settings.access_control.storage.access.boss,
                        .sdmc = settings.access_control.storage.access.sdmc,
                        .core = settings.access_control.storage.access.core,
                        .nand_ro = settings.access_control.storage.access.nand_ro,
                        .nand_rw = settings.access_control.storage.access.nand_rw,
                        .nand_wo = settings.access_control.storage.access.nand_wo,
                        .system_settings = settings.access_control.storage.access.system_settings,
                        .cardboard = settings.access_control.storage.access.cardboard,
                        .export_import_ivs = settings.access_control.storage.access.export_import_ivs,
                        .sdmc_wo = settings.access_control.storage.access.sdmc_wo,
                        .switch_cleanup = settings.access_control.storage.access.switch_cleanup,
                        .save_data_move = settings.access_control.storage.access.save_data_move,
                        .shop = settings.access_control.storage.access.shop,
                        .shell = settings.access_control.storage.access.shell,
                        .home_menu = settings.access_control.storage.access.home_menu,
                        .seed_db = settings.access_control.storage.access.seed_db,
                    },
                    .attributes = .{
                        .no_romfs = !has_romfs_included,
                        .enable_extended_save_data = false,
                    },
                },
                .service_access_control = blk: {
                    var buf: [34][8]u8 = undefined;

                    var i: usize = 0;
                    for (settings.access_control.service_access) |service| {
                        buf[i] = zitrus.fmt.fixedArrayFromSlice(u8, 8, service);
                        i += 1;
                    }
                    @memset(buf[i..], @splat(0));
                    break :blk buf;
                },
                .resource_limit_category = @enumFromInt(@intFromEnum(settings.access_control.category)),
            },
            .kernel_capabilities = .{},
            .arm9_access = .{
                .storage_access = .{
                    .mount_nand = settings.access_control.storage.access.nand_rw,
                    .mount_nand_ro = settings.access_control.storage.access.nand_ro or settings.access_control.storage.access.nand_ro_rw,
                    .mount_twln = settings.access_control.storage.access.twl_nand_data,
                    // TODO: Should we add options for these?
                    .mount_wnand = false,
                    .mount_card_spi = false,
                    .use_sdif3 = false,
                    .create_seed = false,
                    .use_card_spi = false,
                    .sd_application = settings.flags.allow_sd_usage,
                    .mount_sdmc_write = settings.access_control.storage.access.sdmc or settings.access_control.storage.access.sdmc_wo,
                },
            },
        },
    };
    _ = extended_header;

    try out.writeStruct(ncch.Header{
        .signature = @splat(0), // XXX: We can't never get a valid signature, why bother or can we?
        .content_size = 0,
        .partition_id = title_id,
        .maker_code = 0x3030,
        .version = .cxi,
        .hash = undefined,
        .title_id = title_id,
        .logo_region_hash = undefined,
        .product_code = zitrus.fmt.fixedArrayFromSlice(u8, 16, settings.product_code),
        .extended_header_hash = undefined,
        .extended_header_size = @sizeOf(ncch.ExtendedHeader),
        .flags = .{
            .platform = .ctr,
            .crypto_method = 0,
            .content = .{
                .form = .executable,
                .type = .unspecified,
            },
            .exp_unit_size = 0,
            .extra = .{
                .fixed_crypto_key = false,
                .dont_mount_romfs = !has_romfs_included,
                .no_crypto = true,
                .new_key_y_generator = false,
            },
        },
        .plain_region_offset = 0,
        .plain_region_size = 0,
        .logo_region_offset = 0,
        .logo_region_size = 0,
        // TODO: Set ExeFS
        .exefs_offset = 0,
        .exefs_size = 0,
        .exefs_hash_region_size = 0,
        // TODO: Set RomFS
        .romfs_offset = 0,
        .romfs_size = 0,
        .romfs_hash_region_size = 0,
        .exefs_superblock_hash = undefined,
        .romfs_superblock_hash = undefined,
    }, .little);
    try out.writeStruct(ncch.ExtendedHeader{}, .little);
    try out.flush();
    return 0;
}

const Cxi = @This();

const Settings = @import("../Settings.zig");

const log = std.log.scoped(.ncch);

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ncch = zitrus.horizon.fmt.ncch;
const code = zitrus.fmt.code;
