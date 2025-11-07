pub const etc = @import("compress/etc.zig");

pub const lz = @import("compress/lz.zig");
pub const yaz = @import("compress/yaz.zig");
pub const lz10 = @import("compress/lz10.zig");
pub const lz11 = @import("compress/lz11.zig");
pub const lzrev = @import("compress/lzrev.zig");

comptime {
    _ = lzrev;
    _ = yaz;
    _ = lz10;
    _ = lz11;
}
