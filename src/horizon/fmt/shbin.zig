//! TODO: SHBIN
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/SHBIN

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
            u8x4: [4]i8,
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

pub const UniformRegister = enum(u8) {
    pub const Kind = enum {
        input,
        floating_constant,
        integer_constant,
        boolean_constant,
    };

    // zig fmt: off
    v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15,

    f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15,
    f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29,
    f30, f31, f32, f33, f34, f35, f36, f37, f38, f39, f40, f41, f42, f43,
    f44, f45, f46, f47, f48, f49, f50, f51, f52, f53, f54, f55, f56, f57,
    f58, f59, f60, f61, f62, f63, f64, f65, f66, f67, f68, f69, f70, f71,
    f72, f73, f74, f75, f76, f77, f78, f79, f80, f81, f82, f83, f84, f85,
    f86, f87, f88, f89, f90, f91, f92, f93, f94, f95,

    i0, i1, i2, i3, 

    b0 = 0x78, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15,
    // zig fmt: on

    pub fn kind(reg: UniformRegister) Kind {
        return switch (@intFromEnum(reg)) {
            @intFromEnum(UniformRegister.v0)...@intFromEnum(UniformRegister.v15) => .input,
            @intFromEnum(UniformRegister.f0)...@intFromEnum(UniformRegister.f95) => .floating_constant,
            @intFromEnum(UniformRegister.i0)...@intFromEnum(UniformRegister.i3) => .integer_constant,
            @intFromEnum(UniformRegister.b0)...@intFromEnum(UniformRegister.b15) => .boolean_constant,
            else => unreachable,
        };
    }
};

const zitrus = @import("zitrus");
const pica = zitrus.pica;
