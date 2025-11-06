//! Physical memory map of both ARM11 and ARM9 CPUs.
//!
//! If something is specific to one core, it belongs to `arm9` or `arm11`,
//! e.g: ARM9 *can't* access `arm11.pica` and ARM11 *can't* access

pub const VRamBank = enum(u1) { a, b };

pub const arm11 = struct {
    pub const pica: *volatile zitrus.hardware.pica.Registers = @ptrFromInt(io_begin + 0x400000);
};

pub const arm9 = struct {
    pub const itcm_begin: usize = 0x00000000;
    pub const wram_begin: usize = 0x08000000;
    pub const pxi_begin: usize = io_begin + 0x8000;
};

pub const vram_size: usize = 0x00600000;
pub const vram_bank_size: usize = @divExact(vram_size, 2);
pub const vram_begin: usize = 0x18000000;

pub const io_begin: usize = 0x10000000;
pub const csnd_begin: usize = io_begin + 0x103000;
pub const csnd: *volatile zitrus.hardware.csnd.Registers = @ptrFromInt(csnd_begin);
pub const hid_begin: usize = io_begin + 0x146000;
pub const hid: *volatile zitrus.hardware.hid.Registers = @ptrFromInt(hid_begin);
pub const pxi_begin: usize = io_begin + 0x163000;
pub const pxi: *volatile zitrus.hardware.pxi.Registers = @ptrFromInt(pxi_begin);
pub const i2c_bus_1_begin: usize = io_begin + 0x144000;
pub const i2c_bus_1: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_1_begin);
pub const i2c_bus_2_begin: usize = io_begin + 0x148000;
pub const i2c_bus_2: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_2_begin);
pub const i2c_bus_0_begin: usize = io_begin + 0x161000;
pub const i2c_bus_0: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_0_begin);
pub const dsp_begin: usize = 0x1FF00000;
pub const axiwram_begin: usize = 0x1FF80000;

pub const fcram_begin: usize = 0x20000000;
pub const fcram_end_o3ds: usize = fcram_begin + 0x08000000;
pub const fcram_end_n3ds: usize = fcram_end_o3ds + 0x08000000;

const zitrus = @import("zitrus");
