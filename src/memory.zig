pub const VRamBank = enum(u1) { a, b };

pub const vram_size: usize = 0x00600000;
pub const vram_bank_size: usize = @divExact(vram_size, 2);

pub const arm11 = struct {
    pub const gpu: *zitrus.gpu.Registers = @ptrFromInt(0x10400000);
};

pub const arm9 = struct {

};

const zitrus = @import("zitrus");
