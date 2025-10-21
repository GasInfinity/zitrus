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

pub const Geometry = union(Kind) {
    pub const Kind = enum {
        point,
        variable,
        fixed,
    };

    pub const Point = struct {
        inputs: u5,
    };

    pub const Variable = struct {
        full_vertices: u5,
    };

    pub const Fixed = struct {
        vertices: u5,
        uniform_start: register.Source.Constant,
    };

    point: Point,
    variable: Variable,
    fixed: Fixed,

    pub fn initPoint(inputs: u5) Geometry {
        return .{ .point = .{ .inputs = inputs } };
    }

    pub fn initVariable(full_vertices: u5) Geometry {
        return .{ .variable = .{ .full_vertices = full_vertices } };
    }

    pub fn initFixed(vertices: u5, uniform_start: register.Source.Constant) Geometry {
        return .{ .fixed = .{ .vertices = vertices, .uniform_start = uniform_start } };
    }
};

pub const as = @import("shader/as.zig");
pub const Encoder = @import("shader/Encoder.zig");

pub const register = @import("shader/register.zig");
pub const encoding = @import("shader/encoding.zig");

pub const spirv = @import("shader/spirv.zig");

comptime {
    _ = as;
    std.testing.refAllDecls(Encoder);

    _ = register;
    _ = encoding;

    // _ = spirv;
}

const std = @import("std");
