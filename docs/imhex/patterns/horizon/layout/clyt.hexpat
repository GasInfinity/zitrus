// Copyright 2025 GasInfinity
// SPDX-License-Identifier: MIT

#pragma author GasInfinity
#pragma description CTR Layout
#pragma magic [ 43 4C 59 54 ] @ 0x00
#pragma endian little

// WARNING: WIP

import std.io;
import std.mem;
import std.math;
import std.string;
import std.array;
import type.size;
import type.color;
import hex.core;
import ctr.lyt;

enum Origin : u32 { classic, normal };

struct Vector2 {
    float x; float y;
};

struct Vector3 {
    float x; float y; float z;
};

bitfield MaterialFlags {
    unsigned texture_units : 2;
    unsigned matrices : 2;
    unsigned texture_coordinate_source : 2;
    unsigned configured_texture_combiners : 3;
    bool enable_alpha_test : 1;
    bool enable_blend : 1;
    bool no_tint : 1;
    bool separate_blend : 1;
    bool indirect : 1;
    unsigned texture_generation_projections : 2;
    bool enable_font_shadow : 1;
    unsigned pad : 15;
};

struct Material {
    char name[20];
    type::RGBA8 combiner_buffer_color;
    std::Array<type::RGBA8, 6> combiner_unit_constant;
    MaterialFlags flags;
    // TODO: Material Extra data based on flags!
};

struct Layout {
    Origin origin;
    Vector2 canvas_size;    
};

struct List<T, auto Size> {
    u32 _start = $;
    u32 entries;
    u32 offsets[entries];
    std::Array<T, entries> names;
    u32 _len = $ - _start;
    std::mem::Bytes<Size - sizeof(ctr::lyt::BlockHeader) - _len> _pad0;
};

bitfield PaneProperties {
    bool visible : 1;
    bool enable_blend : 1;
    bool flex : 1;
    unsigned _pad : 5;
};

bitfield PaneLayoutProperties {
    bool child_ignore_scale : 1;
    bool fit_to_contents : 1;
    unsigned _pad : 6;
};

enum PaneOrigin : u8 { center = 1, right, left };

struct Pane {
    PaneProperties properties;
    PaneOrigin origin;
    u8 alpha;
    PaneLayoutProperties layout;
    u8 name[16];
    u8 data[8];
    Vector3 translation;
    Vector3 rotation;
    Vector2 scale;
    Vector2 size;
};

struct Picture {
    Pane pane;
    std::Array<type::RGBA8, 4> color; // Top left to bottom right
    u16 material_index;
    u16 coordinates_len;
    std::Array<std::Array<Vector2, 4>, coordinates_len> coordinates;
};

struct PaneName {
    char data[16];
};

struct Group {
    char name[16];
    u32 panes_len;
    std::Array<PaneName, panes_len> panes;
};

struct Block {
    ctr::lyt::BlockHeader hdr;
    
    match (hdr.kind) {
        ("lyt1"): Layout layout;
        ("txl1"): List<std::string::NullString, hdr.size> textures;
        ("fnl1"): List<std::string::NullString, hdr.size> fonts;
        ("mat1"): List<Material, hdr.size> materials;
        ("pan1"): Pane pane;
        ("pic1"): Picture picture;
        ("bnd1"): Pane bounding;
        ("grp1"): Group group;
        (_): std::mem::Bytes<hdr.size - sizeof(ctr::lyt::BlockHeader)> unknown;
    }
};

ctr::lyt::Header<"CLYT"> header @ 0x00;
std::Array<Block, header.blocks> blocks @ header.header_size;
