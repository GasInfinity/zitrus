//! DVL (shbin) is a shader format used in official and homebrew 3DS games.
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/SHBIN

pub const Header = extern struct {
    pub const magic_value = "DVLB";

    magic: [4]u8 = magic_value.*,
    entrypoints: u32,

    // offset table with size dvle_num of u32's

    pub const CheckError = error{NotDvl};
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic_value)) return error.NotDvl;
    }
};

pub const Blob = extern struct {
    offset: u32,
    /// Context-dependent, may be in bytes, in words, etc...
    ///
    /// Usually in bytes unless otherwise noted.
    size: u32,
};

pub const ProgramHeader = extern struct {
    pub const magic_value = "DVLP";

    magic: [4]u8 = magic_value.*,
    version: u32,
    /// Size in `u32`s (`Instruction`)
    instructions: Blob,
    /// Size in `u32`s (`OperandDescriptor`)
    descriptors: Blob,
    /// Same value as filename symbol table offset
    _unknown0: u32,
    /// Always zero?
    _unknown1: u32 = 0,
    filename_symbol_table: Blob,

    pub const CheckError = error{NotDvl};
    pub fn check(hdr: ProgramHeader) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic_value)) return error.NotDvl;
    }
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

        pub fn count(mask: InputMask) usize {
            return @popCount(@as(u16, @bitCast(mask)));
        }
    };

    pub const OutputMask = packed struct(u16) {
        // zig fmt: off
        o0: bool, o1: bool, o2: bool, o3: bool, o4: bool, o5: bool, o6: bool, o7: bool,
        o8: bool, o9: bool, o10: bool, o11: bool, o12: bool, o13: bool, o14: bool, o15: bool,
        // zig fmt: on

        pub fn count(mask: OutputMask) usize {
            return @popCount(@as(u16, @bitCast(mask)));
        }
    };

    pub const Geometry = extern struct {
        pub const Type = enum(u8) {
            point,
            variable,
            fixed,
            _,
        };

        pub const FloatingConstant = packed struct(u8) {
            register: register.Source.Constant,
            _: u1 = 0,
        };

        type: Type,
        uniform_start: FloatingConstant,
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

    pub const CheckError = error{NotDvl};
    pub fn check(hdr: EntrypointHeader) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic_value)) return error.NotDvl;
    }
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
    pub const Type = enum(u8) {
        bool,
        u8x4,
        f24x4,
        _,
    };

    pub const Data = extern union {
        bool: bool,
        u8x4: [4]u8,
        f24x4: [4]hardware.LsbRegister(pica.F7_16),
    };

    type: Type,
    _pad0: u8,
    register: u8,
    _pad1: u8,
    data: Data,
};

pub const OutputEntry = extern struct {
    pub const Semantic = enum(u16) {
        position,
        normal_quaternion,
        color,
        texture_coordinates_0,
        texture_coordinates_0_w,
        texture_coordinates_1,
        texture_coordinates_2,

        view = 0x8,
        dummy, // NOTE: Not in 3dbrew but consistently shows in disassembled shaders, looks like it may be used with "merge output maps" or just as a placeholder.
        _,
    };

    pub const Mask = packed struct(u8) {
        enable_x: bool,
        enable_y: bool,
        enable_z: bool,
        enable_w: bool,
        _: u4,

        pub fn native(mask: Mask) pica.shader.encoding.Component.Mask {
            return .{
                .enable_x = mask.enable_x,
                .enable_y = mask.enable_y,
                .enable_z = mask.enable_z,
                .enable_w = mask.enable_w,
            };
        }
    };

    semantic: Semantic,
    register: u8,
    _pad0: u8,
    // TODO: Separate type for the mask
    mask: Mask,
    _pad1: u8,
    _unknown0: u16,
};

pub const UniformEntry = extern struct {
    pub const Register = enum(u8) {
        // zig fmt: off
        v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15,

        f0 = 0x10, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15,
        f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29,
        f30, f31, f32, f33, f34, f35, f36, f37, f38, f39, f40, f41, f42, f43,
        f44, f45, f46, f47, f48, f49, f50, f51, f52, f53, f54, f55, f56, f57,
        f58, f59, f60, f61, f62, f63, f64, f65, f66, f67, f68, f69, f70, f71,
        f72, f73, f74, f75, f76, f77, f78, f79, f80, f81, f82, f83, f84, f85,
        f86, f87, f88, f89, f90, f91, f92, f93, f94, f95,

        i0 = 0x70, i1, i2, i3, 

        b0 = 0x78, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15,
        _,
        // zig fmt: on
    };

    offset: u32,
    register_start: Register,
    _pad0: u8,
    register_end: Register,
    _pad1: u8,
};

const std = @import("std");

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const pica = zitrus.hardware.pica;

const register = pica.shader.register;
