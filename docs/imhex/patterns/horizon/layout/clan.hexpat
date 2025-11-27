
// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description CTR Layout Animation
#pragma magic [ 43 4C 41 4E ] @ 0x00
#pragma endian little

import std.io;
import std.mem;
import std.math;
import std.string;
import std.array;
import type.size;
import hex.core;
import ctr.lyt;

struct GroupName { char name[20]; };

struct Pattern {
    u16 index;
    u16 groups_len;
    u32 name_offset;
    // Relative to the start of the section
    u32 group_offset;
    u16 start_frame;
    u16 end_frame;
    u32 _unknown0;
    char name[12];
    std::Array<GroupName, groups_len> groups;
};

struct Keyframe {
    float frame;
    u16 value;
    u16 _pad0;
};

struct CubicKeyframe {
    float frame;
    float value;
    float slope;
};

enum Interpolation : u8 {
    discrete,
    linear,
    cubic,
};

enum LayoutTarget : u8 {
    pane,
    material,
};

enum TranslationProperty : u8 {
    translate_x,
    translate_y,
    translate_z,
    
    rotate_x,
    rotate_y,
    rotate_z,
    
    scale_x,
    scale_y,
    
    size_x,
    size_y
};

enum ColorProperty : u8 {
    top_left_r,
    top_left_g,
    top_left_b,
    top_left_a,
    
    top_right_r,
    top_right_g,
    top_right_b,
    top_right_a,
    
    bottom_left_r,
    bottom_left_g,
    bottom_left_b,
    bottom_left_a,
    
    bottom_right_r,
    bottom_right_g,
    bottom_right_b,
    bottom_right_a,
    
    alpha,
};

enum TextureCoordinateProperty : u8 {
    translate_u,
    translate_v,
    rotate,
    scale_u,
    scale_v,
};

enum VisibilityProperty : u8 { visibility };
// This is more like "keyframes", not animations and the "PatternAnimation" ARE animations.

struct Animation<Kind> {
    u8 index;
    Kind property;
    Interpolation interpolation;
    u8 _pad0;
    u32 keyframes_len;
    u32 keyframes_offset;
    
    match (interpolation) {
        (Interpolation::discrete | Interpolation::linear): std::Array<Keyframe, keyframes_len> keyframes;
        (Interpolation::cubic): std::Array<CubicKeyframe, keyframes_len> keyframes;
    }
};

struct PropertyAnimation {
    char kind[4];
    u32 entries_len;
    std::Array<u32, entries_len> entries_offsets;
    
    // XXX: Get more BCLAN's to investigate.
    match (kind) {
        ("CLPA"): std::Array<Animation<TranslationProperty>, entries_len> translation;
        ("CLVC"): std::Array<Animation<ColorProperty>, entries_len> vertex_color;
        ("CLTS"): std::Array<Animation<TextureCoordinateProperty>, entries_len> texture_coordinate;
        ("CLVI"): std::Array<Animation<VisibilityProperty>, entries_len> visibility;
    }
};

struct PatternTarget {
    char name[20];
    u8 animations_len;
    LayoutTarget target;
    u8 _pad0[2];
    
    // From the start of this struct
    std::Array<u32, animations_len> animations_offsets;
    std::Array<PropertyAnimation, animations_len> animations;
};

struct PatternInfo {
    u32 start = $;
    
    u16 frames;
    bool loop;
    u8 _pad0;
    u16 textures_len;
    u16 entries_len;
    u32 entries_offsets_offset;
    std::Array<std::string::NullString, textures_len> textures;
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

