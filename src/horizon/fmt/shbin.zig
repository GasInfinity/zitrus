//! TODO: SHBIN
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/SHBIN

pub const Header = extern struct {
    pub const magic_value = "DVLB";

    magic: [4]u8 = magic_value.*,
    entrypoints: u32,

    // offset table with size dvle_num of u32's
};

pub const Blob = extern struct {
    offset: u32,
    count: u32,
};

pub const ProgramHeader = extern struct {
    pub const magic_value = "DVLP";

    magic: [4]u8 = magic_value.*,
    version: u32,
    /// Count in words
    instructions: Blob,
    /// Count in words
    descriptors: Blob,
    /// Same value as filename symbol table offset
    _unknown0: u32,
    /// Always zero?
    _unknown1: u32 = 0,
    filename_symbol_table: Blob,
};

pub const EntrypointHeader = extern struct {
    pub const magic_value = "DVLE";

    pub const Entry = extern struct {
        start: u32,
        end: u32,
    };

    pub const ShaderType = enum(u8) {
        vertex,
        geometry,
        _,
    };

    pub const InputMask = packed struct(u16) {
        // zig fmt: off
        v0: bool, v1: bool, v2: bool, v3: bool, v4: bool, v5: bool, v6: bool, v7: bool,
        v8: bool, v9: bool, v10: bool, v11: bool, v12: bool, v13: bool, v14: bool, v15: bool,
        // zig fmt: on
    };

    pub const OutputMask = packed struct(u16) {
        // zig fmt: off
        o0: bool, o1: bool, o2: bool, o3: bool, o4: bool, o5: bool, o6: bool, o7: bool,
        o8: bool, o9: bool, o10: bool, o11: bool, o12: bool, o13: bool, o14: bool, o15: bool,
        // zig fmt: on
    };

    pub const Geometry = extern struct {
        pub const Type = enum(u8) {
            point,
            variable,
            fixed,
            _,
        };

        type: Type,
        uniform_start: register.Source.Constant,
        fully_defined_vertices: u8,
        fixed_vertices: u8,
    };

    magic: [4]u8 = magic_value.*,
    version: u16,
    type: ShaderType,
    merge_output_maps: bool,
    /// In words
    entry: Entry,
    used_input_registers: InputMask,
    used_output_registers: OutputMask,
    geometry: Geometry,
    constant_table: Blob,
    label_table: Blob,
    output_register_table: Blob,
    uniform_table: Blob,
    symbol_table: Blob,
};

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
    pub const Register = enum(u8) {
        pub const Type = enum(u8) {
            bool,
            u8x4,
            f24x4,
        };

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

        pub fn kind(reg: Register) Kind {
            return switch (@intFromEnum(reg)) {
                @intFromEnum(Register.v0)...@intFromEnum(Register.v15) => .input,
                @intFromEnum(Register.f0)...@intFromEnum(Register.f95) => .floating_constant,
                @intFromEnum(Register.i0)...@intFromEnum(Register.i3) => .integer_constant,
                @intFromEnum(Register.b0)...@intFromEnum(Register.b15) => .boolean_constant,
                else => unreachable,
            };
        }
    };

    pub const Data = extern union {
        bool: bool,
        u8x4: [4]i8,
        f24x4: [4]pica.F7_16,
    };

    type: Register.Type,
    register_id: Register,
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

const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;

const register = pica.shader.register;
