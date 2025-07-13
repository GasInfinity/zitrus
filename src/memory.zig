pub const VRamBank = enum(u1) { a, b };

pub const vram_size: usize = 0x00600000;
pub const vram_bank_size: usize = @divExact(vram_size, 2);

pub const arm11 = struct {
    pub const io_begin: usize = 0x10000000;
    pub const gpu: *zitrus.gpu.Registers = @ptrFromInt(0x10400000);
    pub const vram_begin: usize = 0x18000000;
    pub const fcram_begin: usize = 0x20000000;
    pub const fcram_end_o3ds: usize = fcram_begin + 0x08000000;
    pub const fcram_end_n3ds: usize = fcram_end_o3ds + 0x08000000;
};

pub const arm9 = struct {};

const zitrus = @import("zitrus");
