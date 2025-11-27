// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description CTR Executable Filesystem
#pragma endian little

import std.string;
import std.mem;
import std.array;
import type.size;
import hex.core;

struct File {
    char name[8];
    u32 offset;
    type::Size32 size;    
} [[static]];

struct Header {
    File files[10];
    u8 reserved[0x20];
    std::Array<std::mem::Bytes<0x20>, 10> file_hashes;
} [[static]];

Header header @ 0x00;
std::mem::Bytes<std::mem::size() - sizeof(header)> file_data @ sizeof(header);

fn addFile(ref File entry) {
    std::mem::Bytes<entry.size> file_data @ sizeof(header) + entry.offset;
    hex::core::add_virtual_file(std::string::replace(entry.name, "\x00", ""), file_data);
};

fn addFiles() {
    for(u16 i = 0, i < 10, i += 1) {
        if(header.files[i].name[0] == 0 || header.files[i].size == 0) continue;
        addFile(header.files[i]);
    }
};

addFiles();