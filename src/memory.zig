//! Physical memory map of both ARM11 and ARM9 CPUs.
//!
//! If something is specific to one core, it belongs to `arm9` or `arm11`,
//! e.g: ARM9 *can't* access `arm11.pica`

pub const VRamBank = enum(u1) { a, b };

pub const arm11 = struct {
    pub const lcd: *volatile hardware.lcd.Registers = @ptrFromInt(io_begin + 0x202000);
    pub const pica: *volatile hardware.pica.Registers = @ptrFromInt(io_begin + 0x400000);
};

pub const arm9 = struct {
    pub const itcm_begin: u32 = 0x00000000;
    pub const wram_begin: u32 = 0x08000000;
};

pub const vram_size: u32 = 0x00600000;
pub const vram_bank_size: u32 = @divExact(vram_size, 2);
pub const vram_begin: u32 = 0x18000000;
pub const vram_end: u32 = vram_begin + (vram_size - 1);
pub const vram_a_begin: u32 = 0x18000000;
pub const vram_b_begin: u32 = 0x18000000 + vram_bank_size;

pub const io_begin: u32 = 0x10000000;
pub const csnd_begin: u32 = io_begin + 0x103000;
pub const csnd: *volatile zitrus.hardware.csnd.Registers = @ptrFromInt(csnd_begin);
pub const pdn_begin: u32 = io_begin + 0x141000;
pub const pdn: *volatile zitrus.hardware.pdn.Registers = @ptrFromInt(pdn_begin);
pub const spi_bus_1_begin: u32 = io_begin + 0x142000;
pub const spi_bus_1: *volatile zitrus.hardware.spi.Registers = @ptrFromInt(spi_bus_1_begin);
pub const spi_bus_2_begin: u32 = io_begin + 0x143000;
pub const spi_bus_2: *volatile zitrus.hardware.spi.Registers = @ptrFromInt(spi_bus_2_begin);
pub const i2c_bus_1_begin: u32 = io_begin + 0x144000;
pub const i2c_bus_1: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_1_begin);
pub const i2s_begin: u32 = io_begin + 0x145000;
pub const i2s: *volatile zitrus.hardware.i2s.Registers = @ptrFromInt(i2s_begin);
pub const hid_begin: u32 = io_begin + 0x146000;
pub const hid: *volatile zitrus.hardware.hid.Registers = @ptrFromInt(hid_begin);
pub const i2c_bus_2_begin: u32 = io_begin + 0x148000;
pub const i2c_bus_2: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_2_begin);
pub const spi_bus_0_begin: u32 = io_begin + 0x160000;
pub const spi_bus_0: *volatile zitrus.hardware.spi.Registers = @ptrFromInt(spi_bus_0_begin);
pub const i2c_bus_0_begin: u32 = io_begin + 0x161000;
pub const i2c_bus_0: *volatile zitrus.hardware.i2c.Bus = @ptrFromInt(i2c_bus_0_begin);
pub const mic_begin: u32 = io_begin + 0x162000;
pub const mic: *volatile zitrus.hardware.mic.Registers = @ptrFromInt(mic_begin);
pub const pxi_begin: u32 = io_begin + 0x163000;
pub const pxi: *volatile zitrus.hardware.pxi.Registers = @ptrFromInt(pxi_begin);
pub const dsp_begin: u32 = 0x1FF00000;
pub const axiwram_begin: u32 = 0x1FF80000;

pub const fcram_begin: u32 = 0x20000000;
pub const fcram_end_o3ds: u32 = fcram_begin + 0x08000000;
pub const fcram_end_n3ds: u32 = fcram_end_o3ds + 0x08000000;

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
