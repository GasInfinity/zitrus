pub const register = @import("pica/register.zig");
pub const encoding = @import("pica/encoding.zig");
pub const Encoder = @import("pica/Encoder.zig");
pub const as = @import("pica/as.zig");
pub const disas = @import("pica/disas.zig");

pub const F3_12 = zsflt.Float(3, 12);
pub const F7_12 = zsflt.Float(7, 12);
pub const F7_16 = zsflt.Float(7, 16);
pub const F7_23 = zsflt.Float(7, 23);

pub const I8x4 = extern struct { x: i8, y: i8, z: i8, w: i8 };

pub const F7_16x4 = extern struct {
    pub const Storage = packed struct(u32) { value: F7_16, _unused0: u8 = 0 };

    x: Storage,
    y: Storage,
    z: Storage,
    w: Storage,
};

const zsflt = @import("zsflt");
