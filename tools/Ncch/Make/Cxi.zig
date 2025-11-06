pub const description = "Make an executable NCCH (.CXI)";

// TODO: Instead of an argument for each, look for a way to create the ExeFS out of band (How would we set each CodeSet?)
// If we do that, we could unify both CXI make and (TODO?) CFA make.
pub const descriptions = .{
    .romfs = "RomFS to embed in the CXI",
    .elf = "Embed code with an ELF executable to the ExeFS",
    .icon = "Embed an icon (SMDH) to the ExeFS",
    .banner = "Embed a banner (CBMD) to the ExeFS",
    .logo = "Embed a logo to the ExeFS",
    .settings = "CXI (Extended Header) settings as .zon",
    .output = "Output filename, if none stdout is used",
};

pub const switches = .{
    .romfs = 'r',
    .elf = 'e',
    .icon = 'i',
    .banner = 'b',
    .logo = 'l',
    .settings = 's',
    .verbose = 'v',
    .output = 'o',
};

settings: []const u8,
romfs: ?[]const u8,
elf: []const u8,
icon: ?[]const u8,
banner: ?[]const u8,
logo: ?[]const u8,

verbose: bool,

output: ?[]const u8,

// TODO: The refactor will be brutal :wilted_rose:
pub fn main(args: Cxi, arena: std.mem.Allocator) !u8 {
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
            log.err("could not parse settings:\n {f}", .{diag});
            return 1;
        },
        else => return err,
    };
    defer settings.deinit(arena);

    var exefs_files_buf: [10]ncch.exefs.File = undefined;
    var exefs_files: std.ArrayList(ncch.exefs.File) = .initBuffer(&exefs_files_buf);

    var code_result = makeCode(args.elf, arena) catch |err| {
        log.err("could not make code from elf '{s}': {t}", .{ args.elf, err });
        return 1;
    };
    defer code_result.deinit(arena);
    exefs_files.appendAssumeCapacity(.init(".code", code_result.code));

    const smdh_data: []u8 = if (args.icon) |smdh_path| loadEntireFile(smdh_path, arena) catch {
        log.err("could not load SMDH", .{});
        return 1;
    } else &.{};
    defer arena.free(smdh_data);
    if (smdh_data.len > 0) exefs_files.appendAssumeCapacity(.init("icon", smdh_data));

    const cbmd_data: []u8 = if (args.banner) |banner_path| loadEntireFile(banner_path, arena) catch {
        log.err("could not load CBMD", .{});
        return 1;
    } else &.{};
    defer arena.free(cbmd_data);
    if (cbmd_data.len > 0) exefs_files.appendAssumeCapacity(.init("banner", cbmd_data));

    // TODO: Add logo to the NCCH AND/OR ExeFS, when does the logo need to be in the ExeFS or NCCH?
    const logo_data: []u8 = if (args.logo) |logo_path| loadEntireFile(logo_path, arena) catch {
        log.err("could not load logo", .{});
        return 1;
    } else &.{};
    defer arena.free(logo_data);
    if (logo_data.len > 0) exefs_files.appendAssumeCapacity(.init("logo", logo_data));

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

    const exefs_header = ncch.exefs.header(exefs_files.items);
    const exefs_full_size: u64 = @as(u64, @sizeOf(ncch.exefs.Header)) + exefs_header.files[exefs_files.items.len - 1].offset + exefs_header.files[exefs_files.items.len - 1].size;
    const exefs_aligned_size: u64 = std.mem.alignForward(u64, exefs_full_size, horizon.fmt.media_unit);

    var exefs_header_hash: [0x20]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(@ptrCast(&exefs_header), &exefs_header_hash, .{});

    const extended_header: ncch.ExtendedHeader = .{
        .system_control = .{
            .application_title = zitrus.fmt.fixedArrayFromSlice(u8, 8, settings.title),
            .flags = .{
                .compressed_code = false, // TODO: LzRev compression
                .allow_sd_usage = settings.flags.allow_sd_usage,
            },
            .remaster_version = 0,
            .text = code_result.text,
            .stack_size = settings.stack_size,
            .rodata = code_result.rodata,
            .data = code_result.data,
            .bss = code_result.bss,
            .dependency_titles = zitrus.fmt.fixedArrayFromSlice(u64, 48, settings.dependencies),
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
                    .mode = @enumFromInt(@intFromEnum(settings.access_control.execution.mode)),
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
                        .nand_ro_rw = settings.access_control.storage.access.nand_ro_rw,
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
            .kernel_capabilities = .{
                .descriptors = blk: {
                    const kernel = settings.access_control.kernel;

                    var capabilities: [28]horizon.Process.Capability = @splat(.none);
                    var i: u8 = 0;

                    if (kernel.version) |version| {
                        capabilities[i] = .kernelVersion(version.major, version.minor);
                        i += 1;
                    }

                    if (kernel.flags) |flags| {
                        capabilities[i] = .kernelFlags(.{
                            .allow_debug = flags.allow_debug,
                            .force_debug = flags.force_debug,
                            .allow_non_alphanumeric = flags.allow_non_alphanumeric,
                            .shared_page_writing = flags.shared_page_writing,
                            .allow_privileged_priorities = flags.allow_privileged_priorities,
                            .allow_main_args = flags.allow_main_args,
                            .shared_device_memory = flags.shared_device_memory,
                            .runnable_on_sleep = flags.runnable_on_sleep,
                            .memory_type = @enumFromInt(@intFromEnum(flags.memory_type)),
                            .special_memory = flags.special_memory,
                            .allow_cpu2 = flags.allow_cpu2,
                        });
                        i += 1;
                    }

                    if (kernel.handle_table_size) |size| {
                        capabilities[i] = .handleTableSize(size);
                        i += 1;
                    }

                    var syscall_masks: [8]u24 = @splat(0);
                    for (kernel.system_call_access) |call| {
                        const int: u8 = @intFromEnum(call);

                        const index: u3 = @intCast(int / 24);
                        const offset: u5 = @intCast(int % 24);

                        syscall_masks[index] |= (@as(u24, 1) << offset);
                    }

                    for (syscall_masks, 0..) |mask, mask_index| {
                        if (mask == 0x00) continue;

                        capabilities[i] = .syscallMask(@intCast(mask_index), mask);
                        i += 1;
                    }

                    break :blk capabilities;
                },
            },
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

    var extended_header_hash: [0x20]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(@ptrCast(&extended_header), &extended_header_hash, .{});

    try out.splatByteAll(0x0, 0x100); // XXX: What do we do about the signature?
    try out.writeStruct(ncch.Header{
        .content_size = 0,
        .partition_id = title_id, // XXX: Does this always match the title id?
        .maker_code = 0x3030, // XXX: What is this?
        .version = .cxi,
        .hash = undefined,
        .title_id = title_id,
        .logo_region_hash = undefined,
        .product_code = zitrus.fmt.fixedArrayFromSlice(u8, 16, settings.product_code),
        .extended_header_hash = extended_header_hash,
        .extended_header_size = @sizeOf(ncch.ExtendedHeader),
        .flags = .{
            .platform = .ctr,
            .crypto_method = 0,
            .content = .{
                .form = .executable,
                .type = .unspecified,
            },
            .extra_unit_exponent = 0,
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
        .exefs_offset = comptime @divExact(@sizeOf(ncch.Header.WithSignature) + @sizeOf(ncch.ExtendedHeader) + @sizeOf(ncch.AccessDescriptor), horizon.fmt.media_unit),
        .exefs_size = @intCast(@divExact(exefs_aligned_size, horizon.fmt.media_unit)),
        .exefs_hash_region_size = comptime @divExact(@sizeOf(ncch.exefs.Header), horizon.fmt.media_unit), // The header already contains hashes
        // TODO: Set RomFS
        .romfs_offset = 0,
        .romfs_size = 0,
        .romfs_hash_region_size = 0,
        .exefs_superblock_hash = exefs_header_hash,
        .romfs_superblock_hash = @splat(0),
    }, .little);
    try out.writeStruct(extended_header, .little);

    // NOTE: Diffing in ImHEX the ACI and AccessDesc, it seems its literally 1:1 but with the Ideal Processor (bitmask) and ¿Priority, wtf? changed.
    const access_descriptor_control = blk: {
        var access = extended_header.access_control;

        // TODO: Check that ideal_processor is less than 2 as it isn't allowed for apps.
        access.user_capabilities.execution.ideal_processor = (@as(u2, 1) << @intCast(access.user_capabilities.execution.ideal_processor));
        break :blk access;
    };

    const access_descriptor_signature: [0x100]u8 = @splat(0);
    const header_modulus: [0x100]u8 = @splat(0);

    try out.writeStruct(ncch.AccessDescriptor{
        .signature = access_descriptor_signature,
        .header_rsa_modulus = header_modulus,
        .access_control = access_descriptor_control,
    }, .little);

    // Write the ExeFS, we do this instead of `ncch.exefs.write` because we need to calculate
    // the hash of the header.
    try out.writeStruct(exefs_header, .little);
    for (exefs_files.items) |file| {
        try out.writeAll(file.data);

        const aligned_size = std.mem.alignForward(usize, file.data.len, ncch.exefs.min_alignment);
        try out.splatByteAll(0, aligned_size - file.data.len);
    }
    try out.splatByteAll(0x00, @intCast(exefs_aligned_size - exefs_full_size));

    try out.flush();
    return 0;
}

fn loadEntireFile(path: []const u8, gpa: std.mem.Allocator) ![]u8 {
    const cwd = std.fs.cwd();

    const file = cwd.openFile(path, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input file '{s}': {t}", .{ path, err });
        return error.NotLoaded;
    };
    defer file.close();

    var reader = file.reader(&.{});
    const size = try reader.getSize();

    if (size > std.math.maxInt(usize)) {
        log.err("could not read input file '{s}': too big", .{path});
        return error.NotLoaded;
    }

    const safe_size: usize = @intCast(size);
    return reader.interface.readAlloc(gpa, safe_size) catch |err| {
        log.err("could not read input file '{s}': {t}", .{ path, err });
        return error.NotLoaded;
    };
}

const CodeResult = struct {
    text: ncch.ExtendedHeader.SystemControlInfo.CodeSetInfo,
    rodata: ncch.ExtendedHeader.SystemControlInfo.CodeSetInfo,
    data: ncch.ExtendedHeader.SystemControlInfo.CodeSetInfo,
    bss: u32,

    code: []u8,

    pub fn deinit(r: CodeResult, gpa: std.mem.Allocator) void {
        gpa.free(r.code);
    }
};

fn makeCode(path: []const u8, gpa: std.mem.Allocator) !CodeResult {
    const cwd = std.fs.cwd();
    const elf_file = cwd.openFile(path, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input elf '{s}': {t}", .{ path, err });
        return error.InvalidCode;
    };
    defer elf_file.close();

    var elf_reader_buf: [4096]u8 = undefined;
    var elf_reader = elf_file.reader(&elf_reader_buf);

    var processed = try code.Info.extractStaticElfAlloc(&elf_reader, gpa);
    defer processed.deinit(gpa);

    // NOTE: We currently follow what we do for 3dsx's but we could be more lenient, we need to investigate more.
    const segments = processed.segments;

    if (processed.segments.len == 0 or processed.segments[0].kind != .text) {
        log.err(".text must be the first segment", .{});
        return error.InvalidCode;
    }

    if (processed.segments.len > 3) {
        log.err("too many segments, at most 3 [text->rodata->data] are supported.", .{});
        return error.InvalidCode;
    }

    if (processed.findNonSequentialPhysicalSegment(.fromByteUnits(zitrus.horizon.heap.page_size))) |first_non_sequential| {
        log.err("segment {} is not sequential [text->rodata->data] in memory!", .{first_non_sequential});
        return error.InvalidCode;
    }

    for (processed.segments[1..], 1..) |s, i| switch (i) {
        1 => switch (s.kind) {
            .rodata => {},
            .data => if (processed.segments.len == 3) {
                log.err("segments must follow [text->rodata->data], found .data segment instead of .rodata at position 1", .{});
                return error.InvalidCode;
            },
            else => {
                log.err("segments must follow [text->rodata->data], found {t} segment at position {}", .{ s.kind, i });
                return error.InvalidCode;
            },
        },
        2 => if (s.kind != .data) {
            log.err("segments must follow [text->rodata->data], found {t} segment at position {}", .{ s.kind, i });
            return error.InvalidCode;
        },
        else => unreachable,
    };

    if (processed.findSegmentWithBss()) |first_bss| if (segments[first_bss].kind != .data) {
        log.err("non-data segment {} has bss", .{first_bss});
        return error.InvalidCode;
    };

    const text = segments[0];

    if (text.virtual_address != processed.entrypoint) {
        log.err("entrypoint 0x{X:0>8} is not the base of the executable 0x{X:0>8}", .{ processed.entrypoint, text.virtual_address });
        return error.InvalidCode;
    }

    const text_address = segments[0].virtual_address;
    const text_size = segments[0].memory_size;
    const text_aligned_size = std.mem.alignForward(u32, text_size, zitrus.horizon.heap.page_size);
    const rodata_size, const data_size, const bss_size = switch (segments.len) {
        1 => .{ 0, 0, 0 },
        2 => switch (segments[1].kind) {
            .rodata => .{ segments[1].file_size, 0, 0 },
            .data => .{ 0, segments[1].file_size, segments[1].memory_size - segments[1].file_size },
            else => unreachable,
        },
        3 => .{ segments[1].file_size, segments[2].file_size, segments[2].memory_size - segments[2].file_size },
        else => unreachable, // NOTE: Cannot happen
    };
    const rodata_aligned_size = std.mem.alignForward(u32, rodata_size, zitrus.horizon.heap.page_size);
    const data_aligned_size = std.mem.alignForward(u32, data_size, zitrus.horizon.heap.page_size);

    const uncompressed_code = try gpa.alloc(u8, text_aligned_size + rodata_aligned_size + data_aligned_size);
    errdefer gpa.free(uncompressed_code);

    var uncompressed_code_writer: std.Io.Writer = .fixed(uncompressed_code);
    try processed.alignedStream(&uncompressed_code_writer, &elf_reader, .fromByteUnits(horizon.heap.page_size));

    return .{
        .text = .{
            .address = text_address,
            .pages = @divExact(text_aligned_size, horizon.heap.page_size),
            .size = text_aligned_size,
        },
        .rodata = .{
            .address = text_address + text_aligned_size,
            .pages = @divExact(rodata_aligned_size, horizon.heap.page_size),
            .size = rodata_aligned_size,
        },
        .data = .{
            .address = text_address + text_aligned_size + rodata_aligned_size,
            .pages = @divExact(data_aligned_size, horizon.heap.page_size),
            .size = data_aligned_size,
        },
        .bss = bss_size,
        .code = uncompressed_code,
    };
}

const Cxi = @This();

const Settings = @import("../Settings.zig");

const log = std.log.scoped(.ncch);

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ncch = zitrus.horizon.fmt.ncch;

const code = zitrus.fmt.code;
