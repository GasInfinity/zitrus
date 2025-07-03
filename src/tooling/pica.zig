pub const register = @import("pica/register.zig");
pub const encoding = @import("pica/encoding.zig");
pub const Encoder = @import("pica/Encoder.zig");
pub const as = @import("pica/as.zig");
pub const disas = @import("pica/disas.zig");

pub const F3_12 = packed struct(u16) { 
    pub const Float = zsflt.Float(3, 12);

    value: Float,
};


pub const F7_12 = packed struct(u32) { 
    pub const Float = zsflt.Float(7, 12);

    value: Float,
    _: u12 = 0,
};

pub const F7_16 = packed struct(u32) { 
    pub const Float = zsflt.Float(7, 16);

    value: Float,
    _: u8 = 0,
};

pub const F7_23 = packed struct(u32) { 
    pub const Float = zsflt.Float(7, 23);

    value: Float,
    _: u1 = 0,
};

pub const I8x4 = extern struct { x: i8, y: i8, z: i8, w: i8 };

pub const F7_16x4 = extern struct {
    x: F7_16,
    y: F7_16,
    z: F7_16,
    w: F7_16,
};

const zsflt = @import("zsflt");
