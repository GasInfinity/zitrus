//! Ericsson Texture Compression Decoder
//!
//! Based on:
//! - https://registry.khronos.org/OpenGL/extensions/OES/OES_compressed_ETC1_RGB8_texture.txt
//!
//! TODO: Move this into its own library

pub const pixels_per_block = 4;

/// All fields should be read as big endian.
pub const Pkm = extern struct {
    pub const Format = enum(u16) {
        etc1_rgb,
        etc2_rgb,
        etc2_rgba_old,
        etc2_rgba,
        etc2_rgba1,
        etc2_r,
        etc2_rg,
        etc2_r_signed,
        etc2_rg_signed,
        _,
    };

    pub const magic_value = "PKM ";

    magic: [magic_value.len]u8 = magic_value.*,
    /// "10" for ETC1, "20" for ETC2
    version: [2]u8 = "10".*,
    format: Format,
    width: u16,
    height: u16,
    real_width: u16,
    real_height: u16,
};

pub const code_word_table: [8][2]u8 = .{
    .{ 2, 8 },
    .{ 5, 17 },
    .{ 9, 29 },
    .{ 13, 42 },
    .{ 18, 60 },
    .{ 24, 80 },
    .{ 33, 106 },
    .{ 47, 183 },
};

pub const Block = packed struct(u64) {
    pub const Direction = enum(u1) {
        /// Two 2x4 blocks, side by side
        vertical,
        /// Two 4x2 blocks
        horizontal,
    };

    pub const Type = enum(u1) { individual, differential };
    pub const Storage = packed union(u30) {
        pub const Either = packed struct(u30) {
            c2: u3,
            c1: u3,
            _: u24,
        };

        pub const Individual = packed struct(u30) {
            const factor: u8 = @divExact(std.math.maxInt(u8), std.math.maxInt(u4));
            c2: u3,
            c1: u3,

            b2: u4,
            b1: u4,
            g2: u4,
            g1: u4,
            r2: u4,
            r1: u4,

            pub fn unpack(individual: Individual) [2]@Vector(4, u8) {
                return .{
                    .{ individual.r1 * factor, individual.g1 * factor, individual.b1 * factor, 0 },
                    .{ individual.r2 * factor, individual.g2 * factor, individual.b2 * factor, 0 },
                };
            }
        };

        pub const Differential = packed struct(u30) {
            c2: u3,
            c1: u3,

            diff_b2: i3,
            b1: u5,
            diff_g2: i3,
            g1: u5,
            diff_r2: i3,
            r1: u5,

            pub fn unpack(differential: Differential) [2]@Vector(4, u8) {
                const uS = unpackScale;
                const r2: u5 = @bitCast(@as(i5, @bitCast(differential.r1)) +| differential.diff_r2);
                const g2: u5 = @bitCast(@as(i5, @bitCast(differential.g1)) +| differential.diff_g2);
                const b2: u5 = @bitCast(@as(i5, @bitCast(differential.b1)) +| differential.diff_b2);

                return .{
                    .{ uS(differential.r1), uS(differential.g1), uS(differential.b1), 0 },
                    .{ uS(r2), uS(g2), uS(b2), 0 },
                };
            }

            fn unpackScale(value: u5) u8 {
                return @intCast((value * @as(u16, std.math.maxInt(u8))) / std.math.maxInt(u5));
            }
        };

        either: Either,
        individual: Individual,
        differential: Differential,
    };

    large: u16,
    negative: u16,
    direction: Direction,
    type: Type,
    storage: Storage,

    pub fn pack(buffer: *[16][4]u8) Block {
        _ = buffer;
        @panic("TODO");
    }

    pub fn bufUnpack(block: Block, buffer: *[16][4]u8) void {
        const sub_code: [2]u3 = .{ block.storage.either.c1, block.storage.either.c2 };
        const sub_colors: [2]@Vector(4, u8) = switch (block.type) {
            .individual => block.storage.individual.unpack(),
            .differential => block.storage.differential.unpack(),
        };

        const sub_index_pixel_shift: u2 = switch (block.direction) {
            .vertical => 0,
            .horizontal => 2,
        };

        for (0..16) |index_u| {
            const index: u4 = @intCast(index_u);
            const sub_index = ((index >> sub_index_pixel_shift) & 0b11) >> 1;
            const pixel: u4 = @intCast(std.math.rotr(u4, index, 2));

            const color = sub_colors[sub_index];
            const code_word = sub_code[sub_index];
            const factor: @Vector(4, u8) = @splat(code_word_table[code_word][(block.large >> pixel) & 1]);
            buffer[index] = if (((block.negative >> pixel) & 1) != 0) color -| factor else color +| factor;
        }
    }
};

const std = @import("std");
