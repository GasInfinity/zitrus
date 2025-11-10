//! **L**a**y**ou**t**
//!
//! Based on the documentation found in GBATEK:
//! * https://www.problemkaputt.de/gbatek.htm#3dsfilesvideolayoutclytflyt

pub const magic = "CLYT";

pub const Layout = extern struct {
    pub const Origin = enum(u32) {
        classic,
        normal,
        _,
    };

    origin: Origin,
    canvas_size: [2]f32,
};

/// An index in the texture list
pub const Texture = enum(u16) { _ };

/// An index in the font list
pub const Font = enum(u16) { _ };

pub const Material = extern struct {
    /// An index in the material list
    pub const Index = enum(u16) { _ };

    pub const Flags = packed struct(u32) {
        texture_units: u2,
        matrices: u2,
        texture_coordinate_source: u2, // ?
        configured_texture_combiners: u3,
        enable_alpha_test: bool,
        enable_blend: bool,
        no_tint: bool,
        separate_blend: bool,
        indirect: bool, // ?
        texture_generation_projections: u2, // ?
        enable_font_shadow: bool,
        _unused0: u15 = 0,
    };

    name: [20]u8, 
    combiner_buffer_constant: [4]u8,
    combiner_unit_constant: [6][4]u8,
    flags: Flags,

    pub const TextureUnit = extern struct {
        pub const AddressMode = enum(u8) {
            clamp,
            repeat,
            mirror,
            _,
        };
        pub const Filter = enum(u8) { nearest, linear, _ };

        /// Index into the texture list
        texture: u16,
        address_mode_u: AddressMode,
        min_filter: Filter,
        address_mode_v: AddressMode,
        mag_filter: Filter,
    };

    pub const Matrix = extern struct {
        translation: [2]f32,
        rotation: f32,
        scale: [2]f32,
    };

    pub const TextureCoordinateSource = extern struct {
        a: u8,
        source: u8,
        b: u8,
    };

    pub const TextureCombiner = extern struct {
        pub const Source = enum(u4) {
            texture_0,
            texture_1,
            texture_2,
            texture_3,
            constant,
            primary,
            previous,
            previous_buffer,
        };

        pub const ColorFactor = enum(u4) {
            src_color,
            one_minus_src_color,
            src_alpha,
            one_minus_src_alpha,
            src_red,
            one_minus_src_red,
            src_green,
            one_minus_src_green,
            src_blue,
            one_minus_src_blue,
        };

        pub const AlphaFactor = enum(u4) {
            src_alpha,
            one_minus_src_alpha,
            src_red,
            one_minus_src_red,
            src_green,
            one_minus_src_green,
            src_blue,
            one_minus_src_blue,
        };

        pub const Operation = enum(u4) {
            replace,
            modulate,
            add,
            add_signed,
            interpolate,
            subtract,
            add_multiply,
            multiply_add,
            overlay,
            indirect,
            blend_indirect,
            each_indirect,
        };

        pub const ColorConfig = packed struct(u32) {
        };

        pub const AlphaConfig = packed struct(u32) {
        };

        color: ColorConfig,
        alpha: AlphaConfig,
    };

    pub const AlphaTest = extern struct {
        compare_op: u32,
        reference: f32,
    };

    pub const Blend = extern struct {

    };
};

pub const Pane = extern struct {
    pub const Reference = [16]u8; // Uh (?)

    pub const Properties = packed struct(u8) {
        visible: bool,
        enable_blend: bool,
        flex: bool, // LocationAdjust? Maybe something like a flex / autolayout?
        _: u5 = 0,
    };

    pub const LayoutProperties = packed struct(u8) {
        child_ignore_scale: bool, // IgnorePartsMagnify (?)
        fit_to_contents: bool, // AdjustToPartsBounds
        _: u6 = 0,
    };

    pub const Origin = enum(u8) { center = 1, right, left };

    properties: Properties,
    origin: Origin,
    alpha: u8,
    layout: LayoutProperties,
    name: [16]u8,
    data: [8]u8,
    translation: [3]f32,
    rotation: [3]f32,
    scale: [2]f32,
    size: [2]f32,
};

pub const Picture = extern struct {
    pane: Pane,
    color: [4][4]u8,
    material: Material.Index,
    coordinate_entries: u16,
};

pub const Window = extern struct {
    pane: Pane,
};

pub const Bounding = extern struct {
    pane: Pane,
};

pub const Text = extern struct {
    pane: Pane,
    max_len: u16,
    text_len: u16,
    material: Material.Index,
    font: Font,
    _unknown0: [4]u8, // (?)
    text_offset: u16,
    top_color: [4]u8,
    bottom_color: [4]u8,
    font_scale: [2]f32,
    font_spacing: [2]f32,
};

pub const Group = extern struct {
    name: [16]u8,
    panes: u32,
};

pub const Userdata = extern struct {
    pub const Entry = extern struct {
        pub const Kind = enum(u16) { string, int, float };

        key_offset: u32,
        value_offset: u32,
        len: u16,
        kind: Kind,
    };

    entries_len: u16,
};

const zitrus = @import("zitrus");
const lyt = zitrus.horizon.fmt.layout;
