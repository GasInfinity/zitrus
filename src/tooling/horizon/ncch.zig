// https://www.3dbrew.org/wiki/NCCH
pub const exefs = @import("ncch/exefs.zig");
pub const romfs = @import("ncch/romfs.zig");

pub const magic = "NCCH";

// TODO: Docs, Docs and Docs
pub const Header = extern struct {
    pub const Version = enum(u16) {
        cfa,
        cxi_proto,
        cxi,
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
            };

            pub const FormType = enum(u2) {
                not_assigned,
                simple_content,
                executable_without_exefs,
                executable,
            };

            type: Type,
            form: FormType,
        };

        pub const Platform = enum(u8) {
            ctr = 1,
            snake,
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
    version: Version,
    hash: [4]u8,
    program_id: u64,
    _reserved0: [0x10]u8 = @splat(0),
    logo_region_hash: [0x20]u8,
    product_code: [0x10]u8,
    extended_header_hash: [0x20]u8,
    extended_header_size: u32,
    _reserved1: [4]u8 = @splat(0),
    flags: Flags,
    plain_region_offset: u32,
    plain_region_size: u32,
    logo_region_offset: u32,
    logo_region_size: u32,
    exefs_offset: u32,
    exefs_size: u32,
    exefs_hash_region_size: u32,
    _reserved2: [4]u8 = @splat(0),
    romfs_offset: u32,
    romfs_size: u32,
    romfs_hash_region_size: u32,
    _reserved3: [4]u8 = @splat(0),
    exefs_superblock_hash: [0x20]u8,
    romfs_superblock_hash: [0x20]u8,
};

pub const ExtendedHeader = extern struct {
    pub const SystemControlInfo = extern struct {
        pub const Flags = packed struct(u8) { _: u8 };
        pub const CodeSetInfo = extern struct {
        };

        application_tile: [8]u8,
        _reserved0: [5]u8 = @splat(0),
        flags: Flags,
        remaster_version: u16,

    };
};
