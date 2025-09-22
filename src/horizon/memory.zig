// https://www.3dbrew.org/wiki/Memory_layout#ARM11%20User-land%20memory%20regions
// These are the virtual addresses as mapped by the kernel
pub const executable_begin: usize = 0x00100000;
pub const heap_begin: usize = 0x08000000;
pub const heap_end: usize = 0x10000000;
pub const shared_memory_begin: usize = heap_end;
pub const shared_memory_end: usize = 0x14000000;
pub const old_linear_heap_begin: usize = shared_memory_end;
pub const old_linear_heap_end: usize = 0x1E800000;
pub const io_begin: usize = 0x1EC00000;
pub const gpu_begin: usize = 0x1EF00000;
pub const io_end: usize = 0x1F000000;
pub const vram_begin: usize = io_end;
pub const vram_end: usize = vram_begin + memory.vram_size;
pub const vram_a_begin: usize = vram_begin;
pub const vram_a_end: usize = vram_a_begin + memory.vram_bank_size;
pub const vram_b_begin: usize = vram_a_end;
pub const vram_b_end: usize = vram_b_begin + memory.vram_bank_size;
pub const linear_heap_begin: usize = 0x30000000;
pub const linear_heap_end: usize = linear_heap_begin + 0x10000000;

pub const configuration_memory_begin = 0x1FF80000;
pub const shared_page_memory_begin = 0x1FF81000;

pub const gpu_registers: *pica.Registers = @ptrFromInt(gpu_begin);

pub const kernel_config: *const config.Kernel = @ptrFromInt(configuration_memory_begin);
pub const shared_config: *config.SharedConfig = @ptrFromInt(shared_page_memory_begin);

pub fn toPhysical(ptr: usize) zitrus.PhysicalAddress {
    return @enumFromInt(switch (ptr) {
        old_linear_heap_begin...old_linear_heap_end => (ptr - old_linear_heap_begin) + memory.arm11.fcram_begin,
        linear_heap_begin...linear_heap_end => (ptr - linear_heap_begin) + memory.arm11.fcram_begin,
        vram_begin...vram_end => (ptr - vram_begin) + memory.arm11.vram_begin,
        else => unreachable,
    });
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const config = horizon.config;

const memory = zitrus.memory;
const pica = zitrus.pica;
