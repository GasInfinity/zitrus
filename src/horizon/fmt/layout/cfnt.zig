pub const magic = "CFNT";

pub const Info = extern struct {
    pub const magic = "FINF";

    pub const Type = enum(u8) {
        _,
    };

    type: Type,
    line_feed: u8,
    alternative_character_index: u16,
    default_info: Character,
    encoding: u8,
    texture_glyph_offset: u32,
    character_widths_offset: u32,
    character_map_offset: u32,
    height: u8,
    width: u8,
    ascent: u8,
    _reserved0: u8,
};

pub const TextureGlyphLayout = extern struct {
    pub const Format = pica.Graphics.TextureUnits.Format;

    cell_width: u8,
    cell_height: u8,
    baseline_position: u8,
    max_character_width: u8,
    sheet_size: u32,
    sheets: u16,
    sheet_format: Format,
    colums: u16,
    rows: u16,
    sheet_width: u16,
    sheet_height: u16,
    sheet_data_offset: u32,
};

pub const Character = extern struct {
    pub const Map = extern struct {
        pub const Method = enum(u16) {
            direct,
            table,
            scan,
        };

        codepoint_begin: u16,
        codepoint_end: u16,
        method: Method,
        _unused0: [2]u8 = @splat(0),
        next: u32,
    };
    
    pub const Info = extern struct {
        start: u16,
        /// Inclusive
        end: u16,
        next: u32,
    };

    left: u8,
    glyph_width: u8,
    character_width: u8, 
};

const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;
