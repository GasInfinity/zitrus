pub const register = @import("pica/register.zig");
pub const encoding = @import("pica/encoding.zig");
pub const Encoder = @import("pica/Encoder.zig");
pub const as = @import("pica/as.zig");

pub const F24 = zsflt.Float(7, 16);
pub const F31 = zsflt.Float(7, 23);

pub const I8x4 = [4]i8;

pub const F24x4 = struct {
    F24,
    F24,
    F24,
    F24,
};

const zsflt = @import("zsflt");
