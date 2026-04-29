// Copyright 2026 GasInfinity
// SPDX-License-Identifier: MIT

#pragma magic [ 46 49 52 4D ] @ 0x0
#pragma author GasInfinity
#pragma description CTR Firmware File
#pragma endian little

import std.string;
import std.mem;
import std.array;
import type.size;
import type.magic;
import hex.core;

struct Header {
    type::Magic<"FIRM"> magic;
    u32 boot_priority;
    u32 arm11_entry;
    u32 arm9_entry;
    std::mem::Bytes<0x30> _reserved0 [[hidden]];    
};

enum CopyMethod : u32 {
    ndma,
    xdma,
    memcpy,
};

struct Section {
    u32 offset;
    u32 address;
    type::Size32 size;
    CopyMethod copy_method;
    std::mem::Bytes<0x20> hash;
};

Header hdr @ 0x00;
Section sections[4] @ $;
std::mem::Bytes<0x100> signature @ $;

fn addSections() {
    for (u8 i = 0, i < 4, i+=1) {
        if (sections[i].size == 0x00) break;
        
        std::mem::Bytes<sections[i].size> section_data @ sections[i].offset;
        str name = std::format("Section[{}]", i);
        hex::core::add_virtual_file(name, section_data);
    }
};

addSections();
