pub const description = "Make a NCCH (CXI/CFA)";

pub const descriptions: plz.Descriptions(@This()) = .{
    .romfs = "RomFS to embed",
    
    .elf = "Embed code within an ELF executable to the ExeFS",
    .icon = "Embed an icon (SMDH) to the ExeFS",
    .banner = "Embed a banner (CBMD) to the ExeFS",
    .logo = "Embed a logo to the ExeFS",

    .exefs = "ExeFS to embed, mutually exclusive with --elf",
    .settings = "CXI (Eetended Header) settings as .zon",

    .@"title-id" = "Overrides the unique and variation of the title id from settings, mandatory for CFAs",
    .@"product-code" = "Overrides the product code from settings, mandatory for CFAs",

    .output = "Output filename, if none stdout is used",
};

pub const short: plz.Short(@This()) = .{
    .romfs = 'r',

    .elf = 'e',
    .icon = 'i',
    .banner = 'b',
    .logo = 'l',

    .exefs = 'x',
    .settings = 's',

    .@"title-id" = 't',
    .@"product-code" = 'p',

    .verbose = 'v',
    .output = 'o',
};

romfs: ?[]const u8,

elf: ?[]const u8,
icon: ?[]const u8,
banner: ?[]const u8,
logo: ?[]const u8,

exefs: ?[]const u8,
settings: ?[]const u8,

@"title-id": ?u32,
@"product-code": ?[]const u8,

verbose: ?void,
output: ?[]const u8,

pub fn run(args: Make, io: std.Io, arena: std.mem.Allocator) !u8 {
    const gpa = arena;

    // Sanity checking
    if (args.exefs != null and (args.elf != null or args.icon != null or args.banner != null or args.logo != null)) {
        log.err("ExeFS and ELF/ICN/BMD/LOGO are mutually exclusive", .{});
        return 1;
    }
    
    if ((args.exefs != null or args.elf != null) and args.settings == null) {
        log.err("Building a CXI requires --settings in zon format", .{});
        return 1;
    }

    if (args.@"title-id" == null and args.settings == null) {
        log.err("Title ID is mandatory when building a CFA", .{});
        return 1;
    }

    // XXX: We must first parse the IVFC unless we want to suffer.
    if (args.romfs != null) @panic("TODO");

    const cwd = std.Io.Dir.cwd();
    const settings = if (args.settings) |sett| set: {
        const zon = cwd.readFileAllocOptions(io, sett, arena, .unlimited, .@"4", 0) catch |err| {
            log.err("could not open settings '{s}': {t}", .{ sett, err });
            return 1;
        };

        var diag: std.zon.parse.Diagnostics = .{};
        @setEvalBranchQuota(2000);
        const settings = std.zon.parse.fromSliceAlloc(Settings, arena, zon, &diag, .{}) catch |err| switch (err) {
            error.ParseZon => {
                log.err("could not parse settings:\n {f}", .{diag});
                return 1;
            },
            else => return err,
        };

        break :set settings;
    }else null;
    defer if (settings) |set| std.zon.parse.free(gpa, set);

    const exefs: []u8, const code_sets: Settings.Code = if (args.exefs) |exefs| blk: {
        const code_sets = settings.?.code orelse {
            log.err("Codesets must be set in settings when building an NCCH with a raw ExeFS", .{});
            return 1;
        };

        const loaded = loadEntireFile(exefs, io, gpa) catch |err| {
            log.err("could not load exefs '{s}': {t}", .{exefs, err});
            return 1;
        };
        
        break :blk .{ loaded, code_sets };
    } else if (args.elf != null or args.logo != null or args.banner != null or args.logo != null) blk: {
        if (args.elf == null) {
            log.err("Building a CXI without code is not supported, specify an elf with '--elf'", .{}); 
            return 1;
        }

        var exefs_files_buf: [10]ncch.exefs.File = undefined;
        var exefs_files: std.ArrayList(ncch.exefs.File) = .initBuffer(&exefs_files_buf);
         
        const sets, const code_data = makeCode(args.elf.?, io, gpa) catch |err| {
            log.err("could not make code from elf '{s}': {t}", .{ args.elf.?, err });
            return 1;
        };
        defer gpa.free(code_data);
        exefs_files.appendAssumeCapacity(.init(".code", code_data));

        const smdh_data: []u8 = if (args.icon) |smdh_path| loadEntireFile(smdh_path, io, arena) catch {
            log.err("could not load SMDH", .{});
            return 1;
        } else &.{};
        defer gpa.free(smdh_data);
        if (smdh_data.len > 0) exefs_files.appendAssumeCapacity(.init("icon", smdh_data));

        const cbmd_data: []u8 = if (args.banner) |banner_path| loadEntireFile(banner_path, io, arena) catch {
            log.err("could not load CBMD", .{});
            return 1;
        } else &.{};
        defer gpa.free(cbmd_data);
        if (cbmd_data.len > 0) exefs_files.appendAssumeCapacity(.init("banner", cbmd_data));

        // TODO: Add logo to the NCCH AND/OR ExeFS, when does the logo need to be in the ExeFS or NCCH?
        const logo_data: []u8 = if (args.logo) |logo_path| loadEntireFile(logo_path, io, arena) catch {
            log.err("could not load logo", .{});
            return 1;
        } else &.{};
        defer gpa.free(logo_data);
        if (logo_data.len > 0) exefs_files.appendAssumeCapacity(.init("logo", logo_data));

        const exefs_header = ncch.exefs.header(exefs_files.items);
        const exefs_full_size: u64 = @as(u64, @sizeOf(ncch.exefs.Header)) + exefs_header.files[exefs_files.items.len - 1].offset + exefs_header.files[exefs_files.items.len - 1].size;

        var allocating: std.Io.Writer.Allocating = try .initCapacity(gpa, @intCast(exefs_full_size));
        defer allocating.deinit();

        try ncch.exefs.write(&allocating.writer, exefs_files.items);
        break :blk .{ try allocating.toOwnedSlice(), sets };
    } else .{ &.{}, undefined };
    defer gpa.free(exefs);

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(io, out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdout(), false };
    defer if (output_should_close) output_file.close(io);

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(io, &output_buffer);
    const out = &output_writer.interface;

    const title_id: horizon.fmt.title.Id = .{
        .variation = if (args.@"title-id") |tid| @truncate(tid) else settings.?.title_id.variation,
        .unique = if (args.@"title-id") |tid| @truncate(tid >> 8) else settings.?.title_id.unique,
        .category = @bitCast(settings.?.title_id.category),
        .platform = .@"3ds",
    };

    const has_romfs_included = false;
    const exefs_aligned_size: u64 = std.mem.alignForward(u64, exefs.len, horizon.fmt.media_unit);

    var exefs_header_hash: [0x20]u8 = @splat(0);

    if (exefs.len > 0) std.crypto.hash.sha2.Sha256.hash(@ptrCast(&exefs[0..@sizeOf(ncch.exefs.Header)]), &exefs_header_hash, .{});

    const extended_header: ?ncch.ExtendedHeader = if (settings) |set| .{
        .system_control = .{
            .application_title = zitrus.fmt.fixedArrayFromSlice(u8, 8, set.title),
            .flags = .{
                .compressed_code = false, // TODO: LzRev compression
                .allow_sd_usage = set.flags.allow_sd_usage,
            },
            .remaster_version = 0,
            .text = code_sets.text.toCodeSet(),
            .stack_size = set.stack_size,
            .rodata = code_sets.rodata.toCodeSet(),
            .data = code_sets.data.toCodeSet(),
            .bss = code_sets.bss,
            .dependency_titles = zitrus.fmt.fixedArrayFromSlice(u64, 48, set.dependencies),
            .system_info = .{
                .save_data_size = set.save_data_size,
                .jump_id = title_id,
            },
        },
        .access_control = .{
            .user_capabilities = .{
                .title_id = title_id,
                .core_version = 2,
                .new_speedup = .{
                    .enable_l2_cache = set.access_control.new_speedup.enable_l2_cache,
                    .cpu_speed = @enumFromInt(@intFromEnum(set.access_control.new_speedup.cpu_speed)),
                },
                .new_execution = .{ .mode = @enumFromInt(@intFromEnum(set.access_control.new_execution.mode)) },
                .execution = .{
                    .ideal_processor = set.access_control.execution.ideal_processor,
                    .affinity_mask = set.access_control.execution.affinity_mask,
                    .mode = @enumFromInt(@intFromEnum(set.access_control.execution.mode)),
                },
                .priority = set.access_control.execution.priority,
                // TODO: ResourceLimits, what index is what?
                .resource_limits = @splat(0),
                .storage = .{
                    .extended_save_data_id = set.access_control.storage.extended_save_data_id,
                    .system_save_data_id = set.access_control.storage.save_data_id,
                    .storage_accessible_uuid = set.access_control.storage.save_data_id,
                    .access = .{
                        .system_application = set.access_control.storage.access.system_application,
                        .hardware_check = set.access_control.storage.access.hardware_check,
                        .filesystem_tool = set.access_control.storage.access.filesystem_tool,
                        .debug = set.access_control.storage.access.debug,
                        .twl_card_backup = set.access_control.storage.access.twl_card_backup,
                        .twl_nand_data = set.access_control.storage.access.twl_nand_data,
                        .boss = set.access_control.storage.access.boss,
                        .sdmc = set.access_control.storage.access.sdmc,
                        .core = set.access_control.storage.access.core,
                        .nand_ro = set.access_control.storage.access.nand_ro,
                        .nand_rw = set.access_control.storage.access.nand_rw,
                        .nand_ro_rw = set.access_control.storage.access.nand_ro_rw,
                        .system_settings = set.access_control.storage.access.system_settings,
                        .cardboard = set.access_control.storage.access.cardboard,
                        .export_import_ivs = set.access_control.storage.access.export_import_ivs,
                        .sdmc_wo = set.access_control.storage.access.sdmc_wo,
                        .switch_cleanup = set.access_control.storage.access.switch_cleanup,
                        .save_data_move = set.access_control.storage.access.save_data_move,
                        .shop = set.access_control.storage.access.shop,
                        .shell = set.access_control.storage.access.shell,
                        .home_menu = set.access_control.storage.access.home_menu,
                        .seed_db = set.access_control.storage.access.seed_db,
                    },
                    .attributes = .{
                        .no_romfs = !has_romfs_included,
                        .enable_extended_save_data = false,
                    },
                },
                .service_access_control = blk: {
                    var buf: [34][8]u8 = undefined;

                    var i: usize = 0;
                    for (set.access_control.service_access) |service| {
                        buf[i] = zitrus.fmt.fixedArrayFromSlice(u8, 8, service);
                        i += 1;
                    }
                    @memset(buf[i..], @splat(0));
                    break :blk buf;
                },
                .resource_limit_category = @enumFromInt(@intFromEnum(set.access_control.category)),
            },
            .kernel_capabilities = .{
                .descriptors = blk: {
                    const kernel = set.access_control.kernel;

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
                    .mount_nand = set.access_control.storage.access.nand_rw,
                    .mount_nand_ro = set.access_control.storage.access.nand_ro or set.access_control.storage.access.nand_ro_rw,
                    .mount_twln = set.access_control.storage.access.twl_nand_data,
                    // TODO: Should we add options for these?
                    .mount_wnand = false,
                    .mount_card_spi = false,
                    .use_sdif3 = false,
                    .create_seed = false,
                    .use_card_spi = false,
                    .sd_application = set.flags.allow_sd_usage,
                    .mount_sdmc_write = set.access_control.storage.access.sdmc or set.access_control.storage.access.sdmc_wo,
                },
            },
        },
    } else null;

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
        .product_code = zitrus.fmt.fixedArrayFromSlice(u8, 16, args.@"product-code" orelse if (settings) |s| s.product_code else "ZTR-BREW"),
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
        // NOTE: ExeFS implies ExHeader (at least for us, and currently)
        .exefs_offset = if (exefs.len > 0) comptime @divExact(@sizeOf(ncch.Header.WithSignature) + @sizeOf(ncch.ExtendedHeader) + @sizeOf(ncch.AccessDescriptor), horizon.fmt.media_unit) else 0,
        .exefs_size = @intCast(@divExact(exefs_aligned_size, horizon.fmt.media_unit)),
        .exefs_hash_region_size = comptime @divExact(@sizeOf(ncch.exefs.Header), horizon.fmt.media_unit), // The header already contains hashes
        // TODO: Set RomFS
        .romfs_offset = 0,
        .romfs_size = 0,
        .romfs_hash_region_size = 0,
        .exefs_superblock_hash = exefs_header_hash,
        .romfs_superblock_hash = @splat(0),
    }, .little);

    if (extended_header) |exheader| {
        try out.writeStruct(exheader, .little);

        // NOTE: Diffing in ImHEX the ACI and AccessDesc, it seems its literally 1:1 but with the Ideal Processor (bitmask) and ¿Priority, wtf? changed.
        const access_descriptor_control = blk: {
            var access = exheader.access_control;

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
    }

    try out.writeAll(exefs);
    try out.splatByteAll(0x00, @intCast(exefs_aligned_size - exefs.len));
    try out.flush();
    return 0;
}

fn loadEntireFile(path: []const u8, io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    const cwd = std.Io.Dir.cwd();

    const file = cwd.openFile(io, path, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input file '{s}': {t}", .{ path, err });
        return error.NotLoaded;
    };
    defer file.close(io);

    var reader = file.reader(io, &.{});
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

fn makeCode(path: []const u8, io: std.Io, gpa: std.mem.Allocator) !struct { Settings.Code, []u8 } {
    const cwd = std.Io.Dir.cwd();
    const elf_file = cwd.openFile(io, path, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input elf '{s}': {t}", .{ path, err });
        return error.InvalidCode;
    };
    defer elf_file.close(io);

    var elf_reader_buf: [4096]u8 = undefined;
    var elf_reader = elf_file.reader(io, &elf_reader_buf);

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
        .{
            .text = .{
                .address = text_address,
                .size = text_aligned_size,
            },
            .rodata = .{
                .address = text_address + text_aligned_size,
                .size = rodata_aligned_size,
            },
            .data = .{
                .address = text_address + text_aligned_size + rodata_aligned_size,
                .size = data_aligned_size,
            },
            .bss = bss_size,
        }, 
        uncompressed_code,
    };
}

const Make = @This();
const Settings = @import("Settings.zig");

const log = std.log.scoped(.ncch);

const builtin = @import("builtin");
const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ncch = zitrus.horizon.fmt.ncch;

const code = zitrus.fmt.code;
