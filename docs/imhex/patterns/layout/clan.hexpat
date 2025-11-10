// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description CTR Layout Animation
#pragma magic [ 43 4C 41 4E ] @ 0x00
#pragma endian little

// WARNING: WIP

import std.io;
import std.mem;
import std.math;
import std.string;
import std.array;
import type.size;
import hex.core;
import ctr.lyt;

struct Pattern {
    u16 maybe_index;
    u16 unknown;
    u32 _unknown0[4];
    char name[12];
    char data[8];
    // name is not a name obviously, its split in 2, what? dont ask me
    u32 _unknown2[3];
};

struct Vector2 {
    float x; float y;
};

struct Vector3 {
    float x; float y; float z;
};

struct Translation {
};

struct TranslationAnimation {
    Vector3 something;
};

struct TextureAnimation {
    Vector3 something;
};

struct VisibilityAnimation {
};

struct VertexColorAnimation {
    Vector3 color_but_what;
};

struct MaterialColorAnimation {
};

struct TexturePatternAnimation {
};

struct Animation<Kind> {
    u32 flags;
    u32 entries_len;
    u32 entries_offset;
    std::Array<Kind, entries_len> entries;
};

struct PatternAnimation {
    char kind[4];
    u32 entries_len;
    std::Array<u32, entries_len> entries_offsets;
    
    match (kind) {
        ("CLPA"): std::Array<Animation<TranslationAnimation>, entries_len> translation;
        ("CLVC"): std::Array<Animation<VertexColorAnimation>, entries_len> vertex_color;
        ("CLTS"): std::Array<Animation<TextureAnimation>, entries_len> texturemaybe;
    }
};

struct PatternTarget {
    char name[20];
    u8 animations_len;
    u8 flags;
    u8 pad0[2];
    
    // From the start of this struct
    std::Array<u32, animations_len> animations_offsets;
    std::Array<PatternAnimation, animations_len> animations;
};

struct PatternInfo {
    u32 start = $;
    
    u16 countdown_maybe;
    u16 unknown0;
    u16 unknown1;
    u16 entries_len;
    u32 entries_offsets_offset;
    std::Array<u32, entries_len> entries_offsets;
    
    std::Array<PatternTarget, entries_len> entries;
};

struct Block {
    ctr::lyt::BlockHeader hdr;
    
    match (hdr.kind) {
        ("pat1"): Pattern pattern;
        ("pai1"): PatternInfo pattern_info;
        (_): std::mem::Bytes<hdr.size - sizeof(ctr::lyt::BlockHeader)> unknown;
    }
};

ctr::lyt::Header<"CLAN"> header @ 0x00;
std::Array<Block, header.blocks> blocks @ header.header_size;