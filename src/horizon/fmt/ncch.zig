//! NCCHs are used to store executables (ExeFS) and files alike (RomFS) when
//! encrypted in the console they're known as `.APP`
//!
//! * `exefs` - Embedded filesystem where the executable and some metadata is stored.
//! * `romfs` - Embedded filesystem used primarily for *assets*.
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/NCCH

pub const exefs = @import("ncch/exefs.zig");
pub const romfs = @import("ncch/romfs.zig");

pub const media_unit = 0x200;
pub const magic = "NCCH";

// TODO: Docs, Docs and Docs
pub const Header = extern struct {
    pub const Version = enum(u16) {
        cfa,
        cxi_proto,
        cxi,
        _,
    };

    pub const Flags = extern struct {
        pub const ContentFlags = packed struct(u8) {
            pub const Type = enum(u6) {
                unspecified,
                system_update,
                instruction_manual,
                download_play_child,
                trial,
                extended_system_update,
                _,
            };

            pub const FormType = enum(u2) {
                not_assigned,
                simple_content,
                executable_without_exefs,
                executable,
            };

            form: FormType,
            type: Type,
        };

        pub const Platform = enum(u8) {
            ctr = 1,
            snake,
            _,
        };

        pub const Extra = packed struct(u8) {
            fixed_crypto_key: bool,
            dont_mount_romfs: bool,
            no_crypto: bool,
            _unused0: u2 = 0,
            new_key_y_generator: bool,
            _unused1: u2 = 0,
        };

        _reserved0: [3]u8 = @splat(0),
        crypto_method: u8,
        platform: Platform,
        content: ContentFlags,
        exp_unit_size: u8,
        extra: Extra,
    };

    signature: [0x100]u8,
    magic: [4]u8 = magic.*,
    content_size: u32,
    partition_id: u64,
    maker_code: u16,
    version: Header.Version,
    hash: [4]u8,
    title_id: horizon.fmt.title.Id,
    _reserved0: [0x10]u8 = @splat(0),
    logo_region_hash: [0x20]u8,
    product_code: [15:0]u8,
    /// SHA-256 of the `ExtendedHeader`
    extended_header_hash: [0x20]u8,
    /// Size of the `ExtendedHeader` in bytes.
    extended_header_size: u32,
    _reserved1: [4]u8 = @splat(0),
    flags: Flags,
    /// In media units
    plain_region_offset: u32,
    /// In media units
    plain_region_size: u32,
    /// In media units
    logo_region_offset: u32,
    /// In media units
    logo_region_size: u32,
    /// In media units
    exefs_offset: u32,
    /// In media units
    exefs_size: u32,
    /// Size of hashed content in `exefs_superblock_hash`. In media units
    exefs_hash_region_size: u32,
    _reserved2: [4]u8 = @splat(0),
    /// In media units
    romfs_offset: u32,
    /// In media units
    romfs_size: u32,
    /// Size of hashed content in `romfs_superblock_hash`. In media units
    romfs_hash_region_size: u32,
    _reserved3: [4]u8 = @splat(0),
    /// ExeFS superblock SHA-256 hash spanning from the start of the ExeFS to `exefs_hash_region_size`.
    exefs_superblock_hash: [0x20]u8,
    /// RomFS superblock SHA-256 hash spanning from the start of the RomFS to `romfs_hash_region_size`.
    romfs_superblock_hash: [0x20]u8,

    /// Checks whether the Header is valid by
    pub fn check(hdr: Header) bool {
        return std.mem.eql(u8, &hdr.magic, magic);
    }

    comptime {
        std.debug.assert(@sizeOf(Header) == 0x200);
    }
};

pub const ExtendedHeader = extern struct {
    pub const SystemControlInfo = extern struct {
        pub const Flags = packed struct(u8) {
            compressed_code: bool,
            allow_sd_usage: bool,
            _: u6,
        };

        pub const CodeSetInfo = extern struct {
            address: u32,
            physical_region_size: u32,
            size: u32,
        };

        pub const SystemInfo = extern struct {
            save_data_size: u64,
            // XXX: Is this where home menu will jump after opening the app?
            // It's the same as program_id always.
            jump_id: u64,
            _reserved0: [0x30]u8 = @splat(0),
        };

        application_title: [7:0]u8,
        _reserved0: [5]u8 = @splat(0),
        flags: Flags,
        remaster_version: u16,
        text: CodeSetInfo,
        stack_size: u32,
        rodata: CodeSetInfo,
        _reserved1: [4]u8 = @splat(0),
        data: CodeSetInfo,
        bss: u32,
        dependency_titles: [48]u64,
        system_info: SystemInfo,

        comptime {
            std.debug.assert(@sizeOf(SystemControlInfo) == 0x200);
        }
    };

    pub const AccessControlInfo = extern struct {
        pub const UserCapabilities = extern struct {
            pub const SystemMode = enum(u4) {
                prod,
                dev1 = 2,
                dev2,
                dev3,
                dev4,
                _,
            };

            pub const NewSystemMode = enum(u4) {
                legacy,
                prod,
                dev1,
                dev2,
                _,
            };

            pub const ResourceLimitCategory = enum(u8) {
                application,
                system_applet,
                library_applet,
                other,
                _,
            };

            pub const ExecutionConfig = packed struct(u8) {
                ideal_processor: u2,
                affinity_mask: u2,
                mode: SystemMode,
            };

            pub const NewExecutionConfig = packed struct(u8) {
                mode: NewSystemMode,
                _unused0: u4 = 0,
            };

            pub const NewSpeedupConfig = packed struct(u8) {
                pub const CpuSpeed = enum(u1) { @"268Mhz", @"804Mhz" };

                enable_l2_cache: bool,
                cpu_speed: CpuSpeed,
                _: u6 = 0,
            };

            pub const Storage = extern struct {
                pub const Access = packed struct(u32) {
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
                    nand_wo: bool,
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
                    _unused0: u10 = 0,
                };

                pub const Attributes = packed struct(u8) {
                    no_romfs: bool,
                    enable_extended_save_data: bool,
                    _unused0: u6 = 0,
                };

                extended_save_data_id: u64,
                system_save_data_id: u64,
                storage_accessible_uuid: u64,
                access: Access,
                _unused0: [3]u8 = @splat(0),
                attributes: Attributes,
            };

            program_id: u64,
            core_version: u32,
            new_speedup: NewSpeedupConfig,
            new_execution: NewExecutionConfig,
            execution: ExecutionConfig,
            priority: u8,
            resource_limits: [16]u16,
            storage: Storage,
            service_access_control: [34][8]u8,
            _reserved0: [15]u8,
            resource_limit_category: ResourceLimitCategory,

            comptime {
                std.debug.assert(@sizeOf(UserCapabilities) == 0x170);
            }
        };

        pub const KernelCapabilities = extern struct {
            descriptors: [28]horizon.Process.CapabilityDescriptor,
            _reserved0: [0x10]u8 = @splat(0),

            comptime {
                std.debug.assert(@sizeOf(KernelCapabilities) == 0x80);
            }
        };

        pub const Arm9AccessControl = extern struct {
            pub const Descriptor = enum(u8) {
                mount_nand,
                mount_nand_ro,
                mount_twln,
                mount_wnand,
                mount_card_spi,
                use_sdif3,
                create_seed,
                use_card_spi,
                sd_application,
                mount_sdmc_write,
                end = 0xFF,
                _,
            };

            descriptors: [15]Descriptor,
            version: u8 = 2,

            comptime {
                std.debug.assert(@sizeOf(Arm9AccessControl) == 0x10);
            }
        };

        user_capabilities: UserCapabilities,
        kernel_capabilities: KernelCapabilities,
        arm9_access: Arm9AccessControl,

        comptime {
            std.debug.assert(@sizeOf(AccessControlInfo) == 0x200);
        }
    };

    system_control: SystemControlInfo,
    access_control: AccessControlInfo,

    comptime {
        std.debug.assert(@sizeOf(ExtendedHeader) == 0x400);
    }
};

pub const AccessDescriptor = extern struct {
    signature: [0x100]u8,
    header_rsa_modulus: [0x100]u8,
    limit_access_control: ExtendedHeader.AccessControlInfo,

    comptime {
        std.debug.assert(@sizeOf(AccessDescriptor) == 0x400);
    }
};

comptime {
    _ = Header;
    _ = ExtendedHeader;
    _ = AccessDescriptor;
    _ = exefs;
    _ = romfs;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
