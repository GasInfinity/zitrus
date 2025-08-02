// https://www.3dbrew.org/wiki/SHBIN

pub const Header = extern struct {
    pub const magic_value = "DVLB";

    magic: [4]u8 = magic_value.*,
    dvle_num: u32,

    // offset table with size dvle_num of u32's
};

pub const Dvlp = extern struct {
    pub const magic_value = "DVLP";

    magic: [4]u8 = magic_value.*,
    version: u32,
    shader_binary_offset: u32,
    /// In words
    shader_binary_size: u32,
    operand_descriptor_offset: u32,
    operand_descriptor_entries: u32,
    /// Same value as filename symbol table offset
    _unknown0: u32,
    /// Always zero?
    _unknown1: u32 = 0,
    filename_symbol_table_offset: u32,
    filename_symbol_table_size: u32,
};

pub const ShaderType = enum(u8) {
    vertex,
    geometry,
};

pub const GeometryShaderType = enum(u8) {
    point,
    variable,
    fixed,
};

pub const Dvle = extern struct {
    pub const magic_value = "DVLE";

    magic: [4]u8 = magic_value.*,
    version: u16,
    type: ShaderType,
    merge_output_maps: bool,
    /// In words
    executable_main_offset: u32,
    executable_main_end_offset: u32,
    used_input_registers: u16,
    used_output_registers: u16,
    geometry_type: GeometryShaderType,
    starting_float_register_fixed: u8,
    fully_defined_vertices_variable: u8,
    vertices_variable: u8,
    constant_table_offset: u32,
    constant_table_entries: u32,
    label_table_offset: u32,
    label_table_entries: u32,
    output_register_table_offset: u32,
    output_register_table_entries: u32,
    uniform_table_offset: u32,
    uniform_table_entries: u32,
    symbol_table_offset: u32,
    symbol_table_size: u32,

    pub const LabelEntry = extern struct {
        label_id: u16,
        _unknown0: u16 = 1,
        /// In words
        label_offset: u32,
        /// In words
        label_size: u32,
        label_symbol_offset: u32,
    };

    pub const ConstantEntry = extern struct {
        pub const Type = enum(u8) {
            bool,
            u8x4,
            f24x4,
        };

        pub const Data = extern union {
            bool: bool,
            u8x4: pica.I8x4,
            f24x4: pica.F7_16x4,
        };

        type: Type,
        register_id: UniformRegister,
        data: Data,
    };

    pub const OutputEntry = extern struct {
        pub const Semantic = enum(u16) {
            position,
            normal_quaternion,
            color,
            texure_coordinates_0,
            texure_coordinates_0_w,
            texure_coordinates_1,
            texure_coordinates_2,

            view = 0x8,
        };

        semantic: Semantic,
        register_id: u16,
        // TODO: Separate type for the mask
        output_attribute_mask: u16,
        _unknown0: u16,
    };

    pub const UniformEntry = extern struct {
        // TODO: Values of this
        pub const Register = enum(u16) { _ };

        offset: u32,
        register_start: Register,
        register_end: Register,
    };
};

const zitrus_tooling = @import("zitrus-tooling");
const pica = zitrus_tooling.pica;
const UniformRegister = pica.UniformRegister;
