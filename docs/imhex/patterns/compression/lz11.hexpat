// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description LZ11 compressed data
#pragma magic [ 11 ]
#pragma endian little
#pragma loop_limit 1073741824

import std.mem;
import type.magic;
import hex.core;
import hex.provider;
import type.size;

type::Magic<"\x11"> signature @ 0x00;
type::Size<u24> decompressed_size @ 0x01;

std::mem::Bytes<std::mem::size() - 4> compressed_data @ 4;

std::mem::Section decompressed = std::mem::create_section("Decompressed " + hex::prv::get_information("file_name", ""));
std::mem::Bytes<decompressed_size> decompressed_data @ 0x00 in decompressed;

fn decompress() {
    u32 src = 0;
    u32 dst = 0;
    u8 remaining_blocks = 0;
    u8 blocks = 0;

    while(dst < decompressed_size) {
        if(remaining_blocks == 0) {
            blocks = compressed_data.bytes[src];
            src += 1;
            remaining_blocks = 7;
        } else remaining_blocks -= 1;

        bool is_match = (blocks & 0x80) != 0;
        blocks <<= 1;
        
        if(is_match) {
            u8 extra_len = compressed_data.bytes[src];
            src += 1;
            
            u16 offset;
            u16 len;
            
            if((extra_len >> 4) == 0) {
                len = (((extra_len & 0xF) << 4) | (compressed_data.bytes[src] >> 4)) + 17;
                offset = (((compressed_data.bytes[src] & 0xF) << 8) | compressed_data.bytes[src+1]) + 1;
                src += 2;
            } else if((extra_len >> 4) == 1) {
                len = (((extra_len & 0xF) << 12) | (compressed_data.bytes[src] << 4) | (compressed_data.bytes[src+1] >> 4)) + 273;
                offset = (((compressed_data.bytes[src+1] & 0xF) << 8) | compressed_data.bytes[src+2]) + 1;
                src += 3;
            } else {
                offset = (extra_len & 0xF) << 8 | compressed_data.bytes[src] + 1;
                src += 1;

                len = (extra_len >> 4) + 1;
            }
            
            if(offset > dst || len > (decompressed_size - dst)) {
                std::print("Out of bounds. Src: {:X} | Dst: {:X} | Offset: {} | Len: {} | Remaining: {}", src, dst, offset, len, decompressed_size - dst);
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
std::print("Decompressed LZ11, look at the `Decompressed` section or virtual file");
