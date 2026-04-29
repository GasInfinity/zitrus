// Copyright 2026 GasInfinity
// SPDX-License-Identifier: MIT

#pragma magic [ 44 49 46 46 ] @ 0x100
#pragma author GasInfinity
#pragma description DIFF
#pragma endian little

import std.string;
import std.mem;
import std.array;
import hex.core;

struct Header {
    type::Magic<"DIFF"> magic;
    type::Magic<"\x00\x00\x03\x00"> id;
    u64 descriptor_offsets[2];
    type::Size64 descriptor_size;
    u64 partition_offset;
    type::Size64 partition_size;
    u32 active_descriptor;
    std::mem::Bytes<0x20> active_descriptor_hash;
    u64 uid;
    std::mem::Bytes<0xA0> _unused0 [[hidden]];
} [[static]];

std::mem::Bytes<0x100> cmac @ 0x00;
Header hdr @ 0x100;

enum IvfcConsumerId : u32 {
    romfs = 0x10000,
    disa = 0x20000,
};
 
struct IvfcHeader {
    type::Magic<"IVFC"> magic;
    IvfcConsumerId id;
} [[static]];

struct Level {
    u64 offset;
    type::Size64 size;
    u64 block_size;
} [[static]];

        
struct Ivfc {
    u32 hdr_st = $;
    IvfcHeader hdr;
    if (hdr.id != IvfcConsumerId::disa) std::error("Not a DISA/DIFF IVFC");
    u64 l0_size;
    Level levels[4];
    u64 header_size;
    u32 hdr_sz = $ - hdr_st;
    
    if (header_size != hdr_sz) std::error("Invalid IVFC");
};

struct Dpfs {
    type::Magic<"DPFS"> magic;
    type::Magic<"\x00\x00\x01\x00"> id;
    Level levels[3];
} [[static]];

struct Difi {
    type::Magic<"DIFI"> magic;
    type::Magic<"\x00\x00\x01\x00"> id;
    u64 ivfc_offset;
    type::Size64 ivfc_size;
    u64 dpfs_offset;
    type::Size64 dpfs_size;
    u64 partition_hash_offset;
    type::Size64 partition_hash_size;
    bool external_l4;
    u8 dpfs_l1_selector;
    std::mem::AlignTo<4> _pad0 [[hidden]];
    u64 external_l4_offset;
};

Difi difi0 @ hdr.descriptor_offsets[0];
Ivfc ivfc0 @ hdr.descriptor_offsets[0] + difi0.ivfc_offset;
Dpfs dpfs0 @ hdr.descriptor_offsets[0] + difi0.dpfs_offset;
std::ByteSizedArray<std::mem::Bytes<0x20>, hdr.descriptor_size - (sizeof(difi0) + sizeof(ivfc0) + sizeof(dpfs0))> l1_hashes0 @ $;

Difi difi1 @ hdr.descriptor_offsets[1];
Ivfc ivfc1 @ hdr.descriptor_offsets[1] + difi1.ivfc_offset;
Dpfs dpfs1 @ hdr.descriptor_offsets[1] + difi1.dpfs_offset;
std::ByteSizedArray<std::mem::Bytes<0x20>, hdr.descriptor_size - (sizeof(difi1) + sizeof(ivfc1) + sizeof(dpfs1))> l1_hashes1 @ $;

std::mem::Section unwrapped = std::mem::create_section("Unwrapped");

fn unwrap() {
    Difi difi @ hdr.descriptor_offsets[hdr.active_descriptor];
    Ivfc ivfc @ hdr.descriptor_offsets[hdr.active_descriptor] + difi.ivfc_offset;
    Dpfs dpfs @ hdr.descriptor_offsets[hdr.active_descriptor] + difi.dpfs_offset;
    std::mem::Bytes<hdr.partition_size> data @ hdr.partition_offset;
    std::mem::Bytes<ivfc.levels[3].size> unwrapped_data @ 0x00 in unwrapped;
    
    u64 dl2_offset = std::mem::align_to(1 << dpfs.levels[1].block_size, dpfs.levels[0].size);
    std::print("DL2 offset {}", hdr.partition_offset + dl2_offset);
    u64 dl3_offset = std::mem::align_to(1 << dpfs.levels[2].block_size, dl2_offset + dpfs.levels[1].size);
    std::print("DL3 offset {}", hdr.partition_offset + dl3_offset);
    
    u64 ivfc_l1_offset = std::mem::align_to(1 << ivfc.levels[0].block_size, dl3_offset);
    u64 ivfc_l2_offset = std::mem::align_to(1 << ivfc.levels[1].block_size, dl3_offset + ivfc.levels[0].size);
    u64 ivfc_l3_offset = std::mem::align_to(1 << ivfc.levels[2].block_size, dl3_offset + ivfc.levels[1].size);
    u64 ivfc_l4_offset = std::mem::align_to(1 << ivfc.levels[3].block_size, dl3_offset + ivfc.levels[2].size);
    // NOTE: we cannot verify the data as imhex doesn't have sha256 in its std
};

unwrap();
