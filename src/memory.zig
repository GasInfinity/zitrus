pub const VRamBank = enum(u1) { a, b };

pub const vram_size: usize = 0x00600000;
pub const vram_bank_size: usize = @divExact(vram_size, 2);
