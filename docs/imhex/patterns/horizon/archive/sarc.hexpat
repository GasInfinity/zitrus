// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description Sorted Archive
#pragma magic [ 53 41 51 43 ] @ 0x00
#pragma endian little

import std.io;
import std.mem;
import std.math;
import std.string;
import std.array;
import type.magic;
import type.size;
import hex.core;

struct Header {
    type::Magic<"SARC"> signature;
    type::Size16 header_size;
    std::mem::Bytes<2> endian;
    type::Size32 file_size;
    u32 data_offset;
    u16 version;
} [[static]];

Header header @ 0x00;

struct FileEntry {
    u32 hash;
    u16 name_offset; // In `u32`s
    u16 attributes;
    u32 data_start;
    u32 data_end;
} [[static]];

struct FileAllocationTable {
    type::Magic<"SFAT"> signature;
    u16 header_size;
    u16 entries_len;
    u32 hash_multiplier;
    std::Array<FileEntry, entries_len> entries;
};

FileAllocationTable file_table @ header.header_size;

struct FilenameTable {
    type::Magic<"SFNT"> signature;
    u16 header_size;
    std::mem::Bytes<2> _pad0;
    std::string::NullString names[while($ < header.data_offset)];
};

FilenameTable name_table @ header.header_size + sizeof(file_table);

std::mem::Bytes<header.file_size - header.data_offset> file_data @ header.data_offset;

fn addFile(ref FileEntry entry) {
    std::string::NullString file_path @ header.header_size + sizeof(file_table) + name_table.header_size + entry.name_offset * 4;
    std::mem::Bytes<entry.data_end - entry.data_start> file_data @ header.data_offset + entry.data_start;
    
    if(std::string::length(file_path) == 0) {
        hex::core::add_virtual_file(std::format("unnamed_{:08X}", entry.hash), file_data);
        return;
    }
    
    hex::core::add_virtual_file(file_path, file_data);
};

fn addFiles() {
    for(u16 i = 0, i < file_table.entries_len, i += 1) {
        addFile(file_table.entries.data[i]);
    }
};

addFiles();
