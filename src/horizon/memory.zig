// https://www.3dbrew.org/wiki/Memory_layout#ARM11%20User-land%20memory%20regions
// These are the virtual addresses as mapped by the kernel
pub const executable_begin: u32 = 0x00100000;
pub const heap_begin: u32 = 0x08000000;
pub const heap_end: u32 = 0x10000000;
pub const shared_memory_begin: u32 = heap_end;
pub const shared_memory_end: u32 = 0x14000000;
pub const old_linear_heap_begin: u32 = shared_memory_end;
pub const old_linear_heap_end: u32 = 0x1E800000;
pub const io_begin: u32 = 0x1EC00000;
pub const pdn_begin: u32 = 0x1EC41000;
pub const i2s_begin: u32 = 0x1EC45000;
pub const mic_begin: u32 = 0x1EC62000;
pub const lcd_begin: u32 = 0x1ED02000;
pub const gpu_begin: u32 = 0x1EF00000;
pub const io_end: u32 = 0x1F000000;
pub const vram_begin: u32 = io_end;
pub const vram_end: u32 = vram_begin + (memory.vram_size - 1);
pub const vram_a_begin: u32 = vram_begin;
pub const vram_a_end: u32 = vram_a_begin + (memory.vram_bank_size - 1);
pub const vram_b_begin: u32 = vram_a_end + 1;
pub const vram_b_end: u32 = vram_b_begin + (memory.vram_bank_size - 1);
pub const linear_heap_begin: u32 = 0x30000000;
pub const linear_heap_end: u32 = linear_heap_begin + 0x10000000;

pub const configuration_memory_begin = 0x1FF80000;
pub const shared_page_memory_begin = 0x1FF81000;

pub const pdn_registers: *volatile hardware.pdn.Registers = @ptrFromInt(pdn_begin);
pub const i2s_registers: *volatile hardware.i2s.Registers = @ptrFromInt(i2s_begin);
pub const mic_registers: *volatile hardware.mic.Registers = @ptrFromInt(mic_begin);
pub const lcd_registers: *volatile hardware.lcd.Registers = @ptrFromInt(lcd_begin);
pub const gpu_registers: *volatile hardware.pica.Registers = @ptrFromInt(gpu_begin);

pub const kernel_config: *const config.Kernel = @ptrFromInt(configuration_memory_begin);
pub const shared_config: *config.Shared = @ptrFromInt(shared_page_memory_begin);

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
const config = horizon.config;

const memory = zitrus.memory;
const hardware = zitrus.hardware;
