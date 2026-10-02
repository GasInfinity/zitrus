// https://www.3dbrew.org/wiki/Memory_layout#ARM11%20User-land%20memory%20regions
// These are the virtual addresses as mapped by the kernel
pub const executable_begin: u32 = 0x00100000;
pub const heap_begin: u32 = 0x08000000;
pub const heap_end: u32 = 0x10000000;
pub const shared_memory_begin: u32 = heap_end;
pub const shared_memory_end: u32 = 0x13FFFFFF;
pub const old_linear_heap_begin: u32 = 0x14000000;
pub const old_linear_heap_end: u32 = 0x1E7FFFFF;
pub const io_begin: u32 = 0x1EC00000;
pub const config11_begin: u32 = 0x1EC40000;
pub const pdn_begin: u32 = 0x1EC41000;
pub const spi_1_begin: u32 = 0x1EC42000;
pub const spi_2_begin: u32 = 0x1EC43000;
pub const i2s_begin: u32 = 0x1EC45000;
pub const gpio_begin: u32 = 0x1EC47000;
pub const spi_0_begin: u32 = 0x1EC60000;
pub const mic_begin: u32 = 0x1EC62000;
pub const pxi_begin: u32 = 0x1EC63000;
pub const lcd_begin: u32 = 0x1ED02000;
pub const dsp_begin: u32 = 0x1ED03000;
pub const gpu_begin: u32 = 0x1EF00000;
pub const io_end: u32 = 0x1F000000;
pub const vram_begin: u32 = io_end;
pub const vram_end: u32 = vram_begin + (memory.vram_size - 1);
pub const vram_a_begin: u32 = vram_begin;
pub const vram_a_end: u32 = vram_a_begin + (memory.vram_bank_size - 1);
pub const vram_b_begin: u32 = vram_a_end + 1;
pub const vram_b_end: u32 = vram_b_begin + (memory.vram_bank_size - 1);
pub const shared_wram_begin = memory.shared_wram_begin;
pub const shared_wram_size = memory.shared_wram_size;
pub const shared_wram_end = shared_wram_begin + (shared_wram_size - 1);
pub const linear_heap_begin: u32 = 0x30000000;
pub const linear_heap_size: u32 = 0x10000000;
pub const linear_heap_end: u32 = linear_heap_begin + (linear_heap_size - 1);

pub const configuration_memory_begin = 0x1FF80000;
pub const shared_page_memory_begin = 0x1FF81000;

pub const config11: *volatile hardware.config.@"11" = @ptrFromInt(config11_begin);
pub const pdn: *volatile hardware.pdn.Registers = @ptrFromInt(pdn_begin);
pub const spi_1: *volatile hardware.spi.Registers = @ptrFromInt(spi_1_begin);
pub const spi_2: *volatile hardware.spi.Registers = @ptrFromInt(spi_2_begin);
pub const i2s: *volatile hardware.i2s.Registers = @ptrFromInt(i2s_begin);
pub const gpio: *volatile hardware.gpio.Registers = @ptrFromInt(gpio_begin);
pub const mic: *volatile hardware.mic.Registers = @ptrFromInt(mic_begin);
pub const pxi: *volatile hardware.pxi.@"11" = @ptrFromInt(pxi_begin);
pub const spi_0: *volatile hardware.spi.Registers = @ptrFromInt(spi_0_begin);
pub const lcd: *volatile hardware.lcd.Registers = @ptrFromInt(lcd_begin);
pub const dsp: *volatile hardware.dsp.Registers = @ptrFromInt(dsp_begin);
pub const gpu: *volatile hardware.pica.Registers = @ptrFromInt(gpu_begin);

pub const kernel_config: *const horizon.config.Kernel = @ptrFromInt(configuration_memory_begin);
pub const shared_config: *horizon.config.Shared = @ptrFromInt(shared_page_memory_begin);

pub fn isFullyLinear(address: u32, size: u32) bool {
    const end = address +% size;
    // zig fmt: off
    return (address >= old_linear_heap_begin and address <= old_linear_heap_end and end >= old_linear_heap_begin and end <= old_linear_heap_end)
        or (address >= linear_heap_begin and address <= linear_heap_end and end >= linear_heap_begin and end <= linear_heap_end);
    // zig fmt: on
}

pub fn toPhysical(ptr: u32) zitrus.hardware.PhysicalAddress {
    return @enumFromInt(switch (ptr) {
        old_linear_heap_begin...old_linear_heap_end => (ptr - old_linear_heap_begin) + memory.fcram_begin,
        linear_heap_begin...linear_heap_end => (ptr - linear_heap_begin) + memory.fcram_begin,
        vram_begin...vram_end => (ptr - vram_begin) + memory.vram_begin,
        else => 0,
    });
}

pub fn toVirtual(ptr: u32, fcram_base_offset: u32) ?[*]u8 {
    return switch (ptr) {
        zitrus.memory.fcram_begin...zitrus.memory.fcram_end_n3ds => @ptrFromInt(ptr -% fcram_base_offset),
        zitrus.memory.vram_begin...zitrus.memory.vram_end => @ptrFromInt((ptr - zitrus.memory.vram_begin) + horizon.memory.vram_begin),
        else => null,
    };
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const memory = zitrus.memory;
const hardware = zitrus.hardware;
