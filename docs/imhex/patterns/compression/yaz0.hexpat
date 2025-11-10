// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description Yaz0 compressed data
#pragma magic [ 59 61 7A 30 ]
#pragma endian big
#pragma loop_limit 1073741824

import std.mem;
import type.magic;
import hex.core;
import hex.provider;
import type.size;

struct Header {
    type::Magic<"Yaz0"> signature;    
    type::Size32 decompressed_size;
    u32 reserved[2];
} [[static]];

Header header @ 0x00;
std::mem::Bytes<std::mem::size() - sizeof(header)> compressed_data @ sizeof(header);

std::mem::Section decompressed = std::mem::create_section("Decompressed " + hex::prv::get_information("file_name", ""));
std::mem::Bytes<header.decompressed_size> decompressed_data @ 0x00 in decompressed;

fn decompress() {
    u32 src = 0;
    u32 dst = 0;
    u8 remaining_blocks = 0;
    u8 blocks = 0;

    while(dst < header.decompressed_size) {
        if(remaining_blocks == 0) {
            blocks = compressed_data.bytes[src];
            src += 1;
            remaining_blocks = 7;
        } else remaining_blocks -= 1;

        bool is_literal = (blocks & 0x80) != 0;
        blocks <<= 1;
        
        if(!is_literal) {
            u8 off_hi_len = compressed_data.bytes[src];
            u8 off_lo = compressed_data.bytes[src + 1];
            src += 2;
            
            u16 offset = (((off_hi_len & 0xF) << 8) | off_lo) + 1;
            u16 len;
            
            if((off_hi_len >> 4) == 0) {
                len = compressed_data.bytes[src] + 18;
                src += 1;
            } else len = (off_hi_len >> 4) + 2;
            
            if(offset > dst || len > (header.decompressed_size - dst)) {
                std::print("Out of bounds. Src: {:X} | Dst: {:X} | Offset: {} | Len: {} | Remaining: {}", src, dst, offset, len, header.decompressed_size - dst);
                std::error("Invalid match");
            }
            
            while(len > 0) {
                decompressed_data.bytes[dst] = decompressed_data.bytes[dst-offset];
                dst += 1;
                len -= 1;
            }
            
            continue;
        }
        
        decompressed_data.bytes[dst] = compressed_data.bytes[src];
        src += 1;
        dst += 1;
    }
};

decompress();

hex::core::add_virtual_file("Decompressed " + hex::prv::get_information("file_name", ""), decompressed_data);
std::print("Decompressed Yaz, look at the `Decompressed` section or virtual file");
