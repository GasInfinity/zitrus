pub const TitleId = struct {
    variation: u8 = 0,
    unique: u24,
    category: u16 = 0,
};

pub const Flags = struct {
    compress: bool,
    allow_sd_usage: bool,
};

pub const AccessControl = struct {
    pub const SystemMode = enum(u4) { prod, dev1 = 2, dev2, dev3, dev4 };
    pub const NewSystemMode = enum(u4) { legacy, prod, dev1, dev2 };
    pub const CpuSpeed = enum(u1) { @"268Mhz", @"804Mhz" };
    pub const ResourceLimitCategory = enum(u8) { application, system_applet, library_applet, other };

    pub const NewSpeedupConfig = struct {
        enable_l2_cache: bool,
        cpu_speed: CpuSpeed,
    };

    pub const NewExecutionConfig = struct {
        mode: NewSystemMode,
    };

    pub const ExecutionConfig = struct {
        ideal_processor: u2,
        affinity_mask: u2,
        mode: SystemMode,
        priority: u8,
    };

    kernel: KernelCapabilities,
    new_speedup: NewSpeedupConfig,
    new_execution: NewExecutionConfig,
    execution: ExecutionConfig,
    storage: Storage,
    service_access: []const []const u8 = &.{},
    category: ResourceLimitCategory,
};

pub const KernelCapabilities = struct {
    pub const Version = struct {
        major: u8,
        minor: u8,
    };

    pub const Flags = struct {
        pub const MemoryType = enum(u3) { application = 1, system, base };

        allow_debug: bool,
        force_debug: bool,
        allow_non_alphanumeric: bool,
        shared_page_writing: bool,
        allow_privileged_priorities: bool,
        allow_main_args: bool,
        shared_device_memory: bool,
        runnable_on_sleep: bool,
        memory_type: MemoryType,
        special_memory: bool,
        allow_cpu2: bool,
    };

    pub const MapAddressRange = struct {
        start: u32,
        end: u32,
        cached: bool,
        read_only: bool,
    };

    pub const MapIoPage = struct {
        address: u32,
        read_only: bool,
    };

    version: ?Version = null,
    flags: ?KernelCapabilities.Flags = null,
    handle_table_size: ?u19 = null,
    // XXX: This could be an EnumFieldStruct or bitset but how would be encode it?
    system_call_access: []const horizon.SystemCall = &.{},
    mapped_ranges: []const MapAddressRange = &.{},
    mapped_io_pages: []const MapIoPage = &.{},
};

pub const Storage = struct {
    pub const Access = struct {
        system_application: bool,
        hardware_check: bool,
        filesystem_tool: bool,
        debug: bool,
        twl_card_backup: bool,
        twl_nand_data: bool,
        boss: bool,
        sdmc: bool,
        core: bool,
        nand_ro: bool,
        nand_rw: bool,
        nand_ro_rw: bool,
        system_settings: bool,
        cardboard: bool,
        export_import_ivs: bool,
        sdmc_wo: bool,
        switch_cleanup: bool,
        save_data_move: bool,
        shop: bool,
        shell: bool,
        home_menu: bool,
        seed_db: bool,
    };

    pub const Attributes = struct {
        enable_extended_save_data: bool = false,
    };

    extended_save_data_id: u64,
    save_data_id: u64,
    storage_uuid: u64,
    access: Access,
    attributes: Attributes = .{},
};

title: []const u8,
product_code: []const u8,
remaster_version: u16,
title_id: TitleId,
flags: Flags,
stack_size: u32,
save_data_size: u64 = 0,
access_control: AccessControl,
dependencies: []const u64 = &.{},

pub fn initNcch(hdr: *const ncch.Header, ex_hdr: *const ncch.ExtendedHeader, gpa: std.mem.Allocator) !Settings {
    return .{
        .title = ex_hdr.system_control.application_title[0 .. std.mem.indexOfScalar(u8, &ex_hdr.system_control.application_title, 0) orelse ex_hdr.system_control.application_title.len],
        .product_code = hdr.product_code[0 .. std.mem.indexOfScalar(u8, &hdr.product_code, 0) orelse hdr.product_code.len],
        .remaster_version = ex_hdr.system_control.remaster_version,
        .title_id = .{
            .variation = hdr.title_id.variation,
            .unique = hdr.title_id.unique,
            .category = @bitCast(hdr.title_id.category),
        },
        .flags = .{
            .compress = ex_hdr.system_control.flags.compressed_code,
            .allow_sd_usage = ex_hdr.system_control.flags.allow_sd_usage,
        },
        .stack_size = ex_hdr.system_control.stack_size,
        .save_data_size = ex_hdr.system_control.system_info.save_data_size,
        .access_control = .{
            .kernel = blk: {
                const Descriptor = horizon.Process.Capability;

                var capabilities: KernelCapabilities = .{};
                var i: usize = 0;

                var used_syscalls: std.ArrayListUnmanaged(horizon.SystemCall) = .empty;

                while (i < ex_hdr.access_control.kernel_capabilities.descriptors.len) {
                    const descriptor = ex_hdr.access_control.kernel_capabilities.descriptors[i];

                    // NOTE: We cannot use a switch as the header is not fixed-size.
                    // XXX: ^ This is ugly as hell still.
                    if (descriptor.kernel_version.header == Descriptor.KernelVersion.magic_value) capabilities.version = .{
                        .major = descriptor.kernel_version.major,
                        .minor = descriptor.kernel_version.minor,
                    } else if (descriptor.kernel_flags.header == Descriptor.KernelFlags.magic_value) capabilities.flags = .{
                        .allow_debug = descriptor.kernel_flags.allow_debug,
                        .force_debug = descriptor.kernel_flags.force_debug,
                        .allow_non_alphanumeric = descriptor.kernel_flags.allow_non_alphanumeric,
                        .shared_page_writing = descriptor.kernel_flags.shared_page_writing,
                        .allow_privileged_priorities = descriptor.kernel_flags.allow_privileged_priorities,
                        .allow_main_args = descriptor.kernel_flags.allow_main_args,
                        .shared_device_memory = descriptor.kernel_flags.shared_device_memory,
                        .runnable_on_sleep = descriptor.kernel_flags.runnable_on_sleep,
                        .memory_type = switch (descriptor.kernel_flags.memory_type) {
                            .application, .system, .base => @enumFromInt(@intFromEnum(descriptor.kernel_flags.memory_type)),
                            _ => return error.InvalidKernelMemoryType,
                        },
                        .special_memory = descriptor.kernel_flags.special_memory,
                        .allow_cpu2 = descriptor.kernel_flags.allow_cpu2,
                    } else if (descriptor.handle_table_size.header == Descriptor.HandleTableSize.magic_value) {
                        capabilities.handle_table_size = descriptor.handle_table_size.size;
                    } else if (descriptor.interrupt_info.header == Descriptor.InterruptInfo.magic_value) {
                        // TODO:
                    } else if (descriptor.system_call_mask.header == Descriptor.SystemCallMask.magic_value) {
                        const mask = descriptor.system_call_mask.mask;
                        const start = descriptor.system_call_mask.index * @as(u8, @bitSizeOf(u24));

                        for (0..@bitSizeOf(u24)) |bit| {
                            if (((mask >> @intCast(bit)) & 0b1) != 0) try used_syscalls.append(gpa, @enumFromInt(start + bit));
                        }
                    } else if (descriptor.map_range_start.header == Descriptor.MapAddressRangeStart.magic_value) {
                        // TODO:
                    } else if (descriptor.map_range_start.header == Descriptor.MapAddressRangeStart.magic_value) {
                        // TODO:
                    } else if (descriptor.map_io_page.header == Descriptor.MapIoPage.magic_value) {
                        // TODO:
                    } else {
                        // XXX: Skip?
                    }

                    i += 1;
                }

                capabilities.system_call_access = try used_syscalls.toOwnedSlice(gpa);
                break :blk capabilities;
            },
            .new_speedup = .{
                .enable_l2_cache = ex_hdr.access_control.user_capabilities.new_speedup.enable_l2_cache,
                .cpu_speed = @enumFromInt(@intFromEnum(ex_hdr.access_control.user_capabilities.new_speedup.cpu_speed)),
            },
            .new_execution = .{
                .mode = @enumFromInt(@intFromEnum(ex_hdr.access_control.user_capabilities.new_execution.mode)),
            },
            .execution = .{
                .ideal_processor = ex_hdr.access_control.user_capabilities.execution.ideal_processor,
                .affinity_mask = ex_hdr.access_control.user_capabilities.execution.affinity_mask,
                .mode = @enumFromInt(@intFromEnum(ex_hdr.access_control.user_capabilities.execution.mode)),
                .priority = ex_hdr.access_control.user_capabilities.priority,
            },
            .storage = .{
                .extended_save_data_id = ex_hdr.access_control.user_capabilities.storage.extended_save_data_id,
                .save_data_id = ex_hdr.access_control.user_capabilities.storage.system_save_data_id,
                .storage_uuid = ex_hdr.access_control.user_capabilities.storage.storage_accessible_uuid,
                .access = .{
                    .system_application = ex_hdr.access_control.user_capabilities.storage.access.system_application,
                    .hardware_check = ex_hdr.access_control.user_capabilities.storage.access.hardware_check,
                    .filesystem_tool = ex_hdr.access_control.user_capabilities.storage.access.filesystem_tool,
                    .debug = ex_hdr.access_control.user_capabilities.storage.access.debug,
                    .twl_card_backup = ex_hdr.access_control.user_capabilities.storage.access.twl_card_backup,
                    .twl_nand_data = ex_hdr.access_control.user_capabilities.storage.access.twl_nand_data,
                    .boss = ex_hdr.access_control.user_capabilities.storage.access.boss,
                    .sdmc = ex_hdr.access_control.user_capabilities.storage.access.sdmc,
                    .core = ex_hdr.access_control.user_capabilities.storage.access.core,
                    .nand_ro = ex_hdr.access_control.user_capabilities.storage.access.nand_ro,
                    .nand_rw = ex_hdr.access_control.user_capabilities.storage.access.nand_rw,
                    .nand_ro_rw = ex_hdr.access_control.user_capabilities.storage.access.nand_ro_rw,
                    .system_settings = ex_hdr.access_control.user_capabilities.storage.access.system_settings,
                    .cardboard = ex_hdr.access_control.user_capabilities.storage.access.cardboard,
                    .export_import_ivs = ex_hdr.access_control.user_capabilities.storage.access.export_import_ivs,
                    .sdmc_wo = ex_hdr.access_control.user_capabilities.storage.access.sdmc_wo,
                    .switch_cleanup = ex_hdr.access_control.user_capabilities.storage.access.switch_cleanup,
                    .save_data_move = ex_hdr.access_control.user_capabilities.storage.access.save_data_move,
                    .shop = ex_hdr.access_control.user_capabilities.storage.access.shop,
                    .shell = ex_hdr.access_control.user_capabilities.storage.access.shell,
                    .home_menu = ex_hdr.access_control.user_capabilities.storage.access.home_menu,
                    .seed_db = ex_hdr.access_control.user_capabilities.storage.access.seed_db,
                },
                .attributes = .{ .enable_extended_save_data = ex_hdr.access_control.user_capabilities.storage.attributes.enable_extended_save_data },
            },
            .service_access = blk: {
                var accessed_service_count: usize = 0;

                for (ex_hdr.access_control.user_capabilities.service_access_control) |service| {
                    const len = std.mem.indexOfScalar(u8, &service, 0) orelse service.len;
                    if (len == 0) break;
                    accessed_service_count += 1;
                }

                const accessed_services = try gpa.alloc([]const u8, accessed_service_count);
                for (accessed_services, 0..) |*accessed, i| {
                    const service = &ex_hdr.access_control.user_capabilities.service_access_control[i];
                    const len = std.mem.indexOfScalar(u8, service, 0) orelse service.len;

                    accessed.* = service[0..len];
                }

                break :blk accessed_services;
            },
            .category = @enumFromInt(@intFromEnum(ex_hdr.access_control.user_capabilities.resource_limit_category)),
        },
        .dependencies = blk: {
            var last: usize = 0;

            for (ex_hdr.system_control.dependency_titles) |title| {
                if (title == 0) {
                    break;
                }

                last += 1;
            }

            break :blk ex_hdr.system_control.dependency_titles[0..last];
        },
    };
}

pub fn deinit(settings: Settings, gpa: std.mem.Allocator) void {
    gpa.free(settings.access_control.service_access);
    gpa.free(settings.access_control.kernel.system_call_access);
}

const Settings = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ncch = horizon.fmt.ncch;
