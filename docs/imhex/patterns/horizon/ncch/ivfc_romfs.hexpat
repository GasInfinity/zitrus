// Copyright 2026 GasInfinity
// SPDX-License-Identifier: MIT

#pragma magic [ 49 56 46 43 00 00 01 00 ] @ 0x0
#pragma author GasInfinity
#pragma description Integrity VeriFication Container (RomFS)
#pragma endian little

import std.string;
import std.mem;
import std.array;
import type.magic;
import type.size;
import hex.core;

enum ConsumerId : u32 {
    romfs = 0x10000,
    disa = 0x20000,
};
 
struct Header {
    type::Magic<"IVFC"> magic;
    ConsumerId id;
} [[static]];

struct Level {
    u64 logical_offset;
    type::Size64 hash_data_size;
    // in log2
    u64 block_size;
} [[static]];

Header hdr @ 0x00;
if (hdr.id != ConsumerId::romfs) std::error("Not a RomFS IVFC");
u32 l0_size @ $;
Level levels[3] @ $;
u64 header_size @ $;
if (header_size != $) std::error("Corrupted IVFC");

std::Array<std::mem::Bytes<0x20>, (l0_size / 0x20)> l0 @ std::mem::align_to(0x20, header_size);

u64 current_offset = std::mem::align_to(1 << levels[2].block_size, header_size + l0_size);
std::mem::Bytes<levels[2].hash_data_size> l3 @ current_offset;
hex::core::add_virtual_file("RomFS", l3);

current_offset = std::mem::align_to(1 << levels[0].block_size, current_offset + levels[2].hash_data_size);
std::Array<std::mem::Bytes<0x20>, (levels[0].hash_data_size / 0x20)> l1 @ current_offset;
current_offset = std::mem::align_to(1 << levels[1].block_size, current_offset + levels[0].hash_data_size);
std::Array<std::mem::Bytes<0x20>, (levels[1].hash_data_size / 0x20)> l2 @ current_offset;

// NOTE: we cannot verify the data as imhex doesn't have sha256 in its std
