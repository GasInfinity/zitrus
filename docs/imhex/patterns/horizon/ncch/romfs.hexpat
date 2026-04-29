// Copyright 2026 GasInfinity
// SPDX-License-Identifier: MIT

// NOTE: RomFS doesn't technically have a magic but we could use header_size as such.
#pragma magic [ 28 00 00 00 ] @ 0x00
#pragma author GasInfinity
#pragma description CTR Read-Only Filesystem
#pragma endian little

import std.string;
import std.mem;
import std.array;
import type.size;
import type.magic;
import hex.core;

struct HashMetaInfo {
    u32 hash_table_offset;
    type::Size32 hash_table_size;
    u32 meta_offset;
    type::Size32 meta_size;
} [[static]];

struct Header {
    type::Magic<"\x28\x00\x00\x00"> header_size;
    HashMetaInfo directory_info;
    HashMetaInfo file_info;
    u32 file_data_offset;
} [[static]];

enum DirectoryOffset : u32 {
    none = 0xFFFFFFFF,
    root = 0,
    entry = 1 ... 0xFFFFFFFE,
};

enum FileOffset : u32 {
    none = 0xFFFFFFFF,
    entry = 0 ... 0xFFFFFFFE,
};

struct DirectoryEntry {
    DirectoryOffset parent_directory;
    DirectoryOffset next_sibling;
    DirectoryOffset first_directory;
    FileOffset first_file;
    DirectoryOffset next_hash_collision;
    u32 name_byte_len;
    char16 name[name_byte_len / 2];
    std::mem::AlignTo<4> _pad [[hidden]];
};

struct FileEntry {
    DirectoryOffset parent_directory;
    FileOffset next_sibling;
    u64 data_offset;
    type::Size64 data_size;
    FileOffset next_hash_collision;
    u32 name_byte_len;
    char16 name[name_byte_len / 2];
    std::mem::AlignTo<4> _pad [[hidden]];
};

Header hdr @ 0x00;

if (hdr.directory_info.meta_size < 24) {
    std::print("RomFS is empty");
    return;
}

std::Array<u32, hdr.directory_info.hash_table_size / 4> directory_hashes @ hdr.directory_info.hash_table_offset;
std::Array<u32, hdr.file_info.hash_table_size / 4> file_hashes @ hdr.file_info.hash_table_offset;
DirectoryEntry directory_entries[while($ < hdr.directory_info.meta_offset + hdr.directory_info.meta_size)] @ hdr.directory_info.meta_offset;
FileEntry file_entries[while($ < hdr.file_info.meta_offset + hdr.file_info.meta_size)] @ hdr.file_info.meta_offset;

fn addDirectory(DirectoryOffset off, str path) {
    DirectoryEntry parent_entry @ hdr.directory_info.meta_offset + u32(off);
    
    FileOffset current_file = parent_entry.first_file;
    while (current_file != FileOffset::none) {
        FileEntry file @ hdr.file_info.meta_offset + u32(current_file);
        std::mem::Bytes<file.data_size> file_data @ hdr.file_data_offset + file.data_offset;
        
        str heap_file_name = file.name;
        str full_path = path + "/" + heap_file_name;
        
        hex::core::add_virtual_file(full_path, file_data);
        current_file = file.next_sibling;
    }
    
    DirectoryOffset current_directory = parent_entry.first_directory;
    while (current_directory != DirectoryOffset::none) {
        DirectoryEntry dir @ hdr.directory_info.meta_offset + u32(current_directory);
        
        str heap_file_name = dir.name;
        str full_path = path + "/" + heap_file_name;
        
        addDirectory(current_directory, full_path);
        current_directory = dir.next_sibling;
    }
};

addDirectory(DirectoryOffset::root, "");
