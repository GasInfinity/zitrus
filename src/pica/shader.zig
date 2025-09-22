//! PICA200 shader ISA encoder, assembler and (TODO) disassembler.
//!
//! * `as` - zitrus PICA200 shader assembler / disassebler.
//! * `register` - register enums for everything shader related
//! * `encoding` - single instruction encoding
//! * `spirv` - ?? :) (TODO)
//!
//! * `Encoder` - Type-safe PICA200 shader ISA encoder

pub const Type = enum(u1) {
    vertex,
    geometry,
};

pub const GeometryMode = union(Kind) {
    pub const Kind = enum {
        point,
        variable_primitive,
        fixed_primitive,
    };

    point: u8,
    variable_primitive, // TODO
    fixed_primitive, // TODO
};

pub const as = @import("shader/as.zig");
pub const Encoder = @import("shader/Encoder.zig");

pub const register = @import("shader/register.zig");
pub const encoding = @import("shader/encoding.zig");

pub const spirv = @import("shader/spirv.zig");

comptime {
    _ = as;
    _ = Encoder;

    _ = register;
    _ = encoding;

    // _ = spirv;
}
