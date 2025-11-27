// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description CTR Layout Image
#pragma magic [ 43 4C 49 4D ]
#pragma endian little

import std.io;
import std.mem;
import std.math;
import std.string;
import std.array;
import type.size;
import hex.core;
import ctr.lyt;

enum Format : u8 {
    i8,
    a8,
    ia44,
    ia88,
    hilo88,
    rgb565,
    bgr888,
    rgba5551,
    rgba4444,
    abgr8888,
    etc1,
    etc1a4,
    i4,
    a4,
};

struct Image {
    u16 width;
    u16 height;
    Format format;
    std::mem::Bytes<3> _pad0;
} [[static]];

struct Block {
    ctr::lyt::BlockHeader hdr;
    
    match (hdr.kind) {
        ("imag"): Image image;
        (_): std::mem::Bytes<hdr.size - sizeof(ctr::lyt::BlockHeader)> unknown;
    }
};

u32 header_offset @ std::mem::size() - 4;
ctr::lyt::Header<"CLIM"> header @ header_offset;
std::Array<Block, header.blocks> blocks @ header_offset + header.header_size;
