//! Zitrus PICA200 texture
//!
//! A simple texture format for storing textures in PICA-native format, it literally stores
//! the bare minimum to get a texture up and running (width/height, format, levels and layers)

pub const magic = "ZPTX";

pub const Header = extern struct {
    pub const Metadata = packed struct(u32) {
        pub const Format = pica.Graphics.TextureUnits.Format;
        pub const Compression = enum(u8) {
            uncompressed,
            /// Reserved
            _,
        };

        width_log2: u4,
        height_log2: u4,
        format: Format,
        levels: u4,
        layers: u4,
        _reserved0: u4 = 0,
        compression: Compression,

        pub fn width(meta: Metadata) u16 {
            return @as(u16, 1) << meta.width_log2;
        }

        pub fn height(meta: Metadata) u16 {
            return @as(u16, 1) << meta.height_log2;
        }

        pub fn mangoFormat(meta: Metadata) zitrus.mango.Format {
            return switch (meta.format) {
                .abgr8888 => .a8b8g8r8_unorm,
                .bgr888 => .b8g8r8_unorm,
                .rgba5551 => .r5g5b5a1_unorm_pack16,
                .rgb565 => .r5g6b5_unorm_pack16,
                .rgba4444 => .r4g4b4a4_unorm_pack16,
                .ia88 => .i8a8_unorm,
                .hilo88 => .g8r8_unorm,
                .i8 => .i8_unorm,
                .a8 => .a8_unorm,
                .ia44 => .i4a4_unorm,
                .i4 => .i4_unorm,
                .a4 => .a4_unorm,
                .etc1 => .etc1_unorm,
                .etc1a4 => .etc1a4_unorm,
            };
        }
    };

    magic: [magic.len]u8 = magic.*,
    meta: Metadata,
    uncompressed_len: u32,
};

const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;
