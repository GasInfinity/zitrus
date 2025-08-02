pub const encoding = @import("pica/encoding.zig");
pub const Encoder = @import("pica/Encoder.zig");
pub const as = @import("pica/as.zig");
pub const disas = @import("pica/disas.zig");

pub const RelativeComponent = register.RelativeComponent;
pub const TemporaryRegister = register.TemporaryRegister;
pub const SourceRegister = register.SourceRegister;
pub const DestinationRegister = register.DestinationRegister;
pub const IntegralRegister = register.IntegralRegister;
pub const UniformRegister = register.UniformRegister;

pub const F3_12 = zsflt.Float(3, 12);
pub const F7_12 = zsflt.Float(7, 12);
pub const F7_16 = zsflt.Float(7, 16);
pub const F7_23 = zsflt.Float(7, 23);

pub const I8x4 = extern struct { x: i8, y: i8, z: i8, w: i8 };
pub const U16x2 = packed struct(u32) { x: u16, y: u16 };
pub const I16x2 = packed struct(u32) { x: i16, y: i16 };

pub const F7_16x4 = extern struct {
    pub const Unpacked = struct { x: F7_16, y: F7_16, z: F7_16, w: F7_16 };

    data: [@divExact(@bitSizeOf(F7_16) * 4, @bitSizeOf(u32))]u32,

    pub fn pack(x: F7_16, y: F7_16, z:F7_16, w: F7_16) F7_16x4 {
        var vec: F7_16x4 = undefined;
        const vec_bytes = std.mem.asBytes(&vec.data);

        // TODO: 0.15 write the packed struct instead of bitcasting
        std.mem.writePackedInt(u24, vec_bytes, 0, @bitCast(x), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16), @bitCast(y), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 2, @bitCast(z), .little);
        std.mem.writePackedInt(u24, vec_bytes, @bitSizeOf(F7_16) * 3, @bitCast(w), .little);
        std.mem.swap(u32, &vec.data[0], &vec.data[2]); 

        return vec;
    }
};

const register = @import("pica/register.zig");

const std = @import("std");
const zsflt = @import("zsflt");
