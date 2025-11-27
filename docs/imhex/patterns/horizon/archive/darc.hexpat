// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description Data Archive
#pragma magic [ 64 61 72 63 ] @ 0x00
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
    type::Magic<"darc"> signature;
    u8 endian[2];
    type::Size16 header_size;
    u32 version;
    type::Size32 file_size;
    
    u32 meta_offset;
    type::Size32 meta_size;
    u32 file_data_offset;
} [[static]];

using MetaEntry;

enum MetaEntryKind : u8 { file, directory };

fn metaEntryRelative(u128 address) {
    return header.meta_offset + address * sizeof(MetaEntry);
};

struct MetaAttributes {
    u24 name_offset;
    MetaEntryKind kind;
} [[static]];

struct MetaDirectoryInfo {
    u32 parent_directory;
    u32 end;
} [[static]];

struct MetaFileInfo {
    // Relative to the start of the file
    u32 offset;
    type::Size32 size;
} [[static]];

union MetaInfo {
    MetaFileInfo file;
    MetaDirectoryInfo directory;
} [[static]];

struct MetaEntry {
    MetaAttributes attributes;
    MetaInfo info;
} [[static]];

Header header @ 0x00;

if(header.meta_size < sizeof(MetaEntry)) {
    std::print("Empty DARC...");
    return;
}

MetaEntry root @ header.meta_offset;
std::mem::Bytes<header.file_size - header.file_data_offset> all_file_data @ header.file_data_offset;

if(root.attributes.kind != MetaEntryKind::directory) {
    std::error("Root is NOT a directory");
}

MetaEntry entries[root.info.directory.end] @ header.meta_offset;
std::string::NullString16 name_table[while($ < header.meta_offset + header.meta_size)] @ header.meta_offset + sizeof(entries);

fn addDirectory(u32 i, str path) {
    MetaEntry top = entries[i];
    i += 1;
    
    while(i < top.info.directory.end) {
        MetaEntry entry = entries[i];
        std::string::NullString16 file_name @ header.meta_offset + sizeof(entries) + entry.attributes.name_offset;
        str heap_file_name = file_name;
        str full_path = path + "/" + heap_file_name;
        
        if(entry.attributes.kind == MetaEntryKind::file) {
            std::mem::Bytes<entry.info.file.size> file_data @ entry.info.file.offset;
            
            hex::core::add_virtual_file(full_path, file_data);
            i += 1;
            continue;
        }
        
        addDirectory(i, full_path);
        i = entry.info.directory.end;
    }
};

addDirectory(0, "");
