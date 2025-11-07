//! Ericsson Texture Compression Decoder
//!
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
