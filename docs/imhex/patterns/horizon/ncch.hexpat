// Copyright 2026 GasInfinity
// SPDX-License-Identifier: MIT

#pragma magic [ 4E 43 43 48 ] @ 0x100
#pragma author GasInfinity
#pragma description CTR Executable/File Container
#pragma endian little

import std.string;
import std.mem;
import std.array;
import type.size;
import type.magic;
import hex.core;

enum Version : u16 {
    cfa,
    cxi_proto,
    cxi,
};

enum Platform : u8 {
    ctr = 1,
    snake,
};

enum ContentType : u8 {
    unspecified,
    system_update,
    instruction_manual,
    download_play_child,
    trial,
    extended_system_update,
};

enum ContentForm : u8 {
    not_assigned,
    simple_content,
    executable_without_exefs,
    executable,
};

bitfield HeaderFlagsContent {
    ContentForm form : 2;
    ContentType type : 6;
};

bitfield HeaderFlagsExtra {
    bool fixed_crypto_key : 1;
    bool dont_mount_romfs : 1;
    bool no_crypto : 1;
    unsigned _unused0 : 2 [[hidden]];
    bool new_key_y_generator : 1;
    unsigned _unused1 : 2 [[hidden]];
};

struct HeaderFlags {
    std::mem::Bytes<3> _reserved0 [[hidden]];
    u8 crypto_method;
    Platform platform;
    HeaderFlagsContent content;
    u8 extra_unit_exponent;
    HeaderFlagsExtra extra;
} [[static]];

struct Header {
    type::Magic<"NCCH"> magic;
    u32 content_size;
    u64 partition_id;
    u16 maker_code;
    Version version;
    std::mem::Bytes<4> hash;
    u64 title_id;
    std::mem::Bytes<0x10> _reserved0 [[hidden]];
    std::mem::Bytes<0x20> logo_region_hash;
    char product_code[0x10];
    std::mem::Bytes<0x20> extended_header_hash;
    type::Size32 extended_header_size;
    std::mem::Bytes<4> _reserved1 [[hidden]];
    HeaderFlags flags;
    u32 plain_region_offset;
    type::Size32 plain_region_size;
    u32 logo_region_offset;
    type::Size32 logo_region_size;
    u32 exefs_region_offset;
    type::Size32 exefs_region_size;
    type::Size32 exefs_hash_region_size;
    std::mem::Bytes<4> _reserved2 [[hidden]];
    u32 romfs_region_offset;
    type::Size32 romfs_region_size;
    type::Size32 romfs_hash_region_size;
    std::mem::Bytes<4> _reserved3 [[hidden]];
    std::mem::Bytes<0x20> exefs_superblock_hash;
    std::mem::Bytes<0x20> romfs_superblock_hash;
} [[static]];

std::mem::Bytes<0x100> signature @ 0x00;
Header hdr @ 0x100;

if (hdr.extended_header_size > 0) {
    // TODO: place exheader if present
    std::print("Exheader present: TODO");
}

if (!hdr.flags.extra.no_crypto) {
    std::print("NCCH is encrypted, cannot continue");
    return;
}

// TODO: handle the extra_unit_exponent

if (hdr.plain_region_size > 0) {
    std::mem::Bytes<hdr.plain_region_size * 0x200> plain_region_data @ hdr.plain_region_offset * 0x200;
    hex::core::add_virtual_file("Plain", plain_region_data);
}

if (hdr.logo_region_size > 0) {
    std::mem::Bytes<hdr.logo_region_size * 0x200> logo_region_data @ hdr.logo_region_offset * 0x200;
    hex::core::add_virtual_file("Logo", logo_region_data);
}

if (hdr.exefs_region_size > 0) {
    std::mem::Bytes<hdr.exefs_region_size * 0x200> exefs_region_data @ hdr.exefs_region_offset * 0x200;
    hex::core::add_virtual_file("ExeFS", exefs_region_data);
}

if (hdr.romfs_region_size > 0) {
    std::mem::Bytes<hdr.romfs_region_size * 0x200> romfs_region_data @ hdr.romfs_region_offset * 0x200;
    hex::core::add_virtual_file("RomFS (IVFC)", romfs_region_data);
}
