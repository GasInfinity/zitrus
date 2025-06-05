// https://www.3dbrew.org/wiki/Memory_layout#ARM11%20User-land%20memory%20regions
// These are the virtual addresses as mapped by the kernel
pub const executable_memory_begin: usize = 0x00100000;
pub const heap_memory_begin: usize = 0x08000000;
pub const heap_memory_end: usize = 0x10000000;
pub const shared_memory_begin: usize = heap_memory_end;
pub const shared_memory_end: usize = 0x14000000;
pub const linear_heap_memory_begin: usize = shared_memory_end;
pub const linear_heap_memory_end: usize = 0x1E800000;
pub const io_memory_begin: usize = 0x1EC00000;
pub const gpu_memory_begin: usize = 0x1EF00000;
pub const io_memory_end: usize = 0x1F000000;
pub const vram_memory_begin: usize = io_memory_end;
pub const vram_memory_end: usize = vram_memory_begin + memory.vram_size;
pub const vram_a_memory_begin: usize = vram_memory_begin;
pub const vram_a_memory_end: usize = vram_a_memory_begin + memory.vram_bank_size;
pub const vram_b_memory_begin: usize = vram_a_memory_end;
pub const vram_b_memory_end: usize = vram_b_memory_begin + memory.vram_bank_size;

pub const configuration_memory_begin = 0x1FF80000;
pub const shared_page_memory_begin = 0x1FF81000;

pub const gpu_registers: *gpu.Registers = @ptrFromInt(gpu_memory_begin);

pub const kernel_config: *const config.KernelConfig = @ptrCast(configuration_memory_begin);
pub const shared_config: *config.SharedConfig = @ptrCast(shared_page_memory_begin);

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const config = horizon.config;

const memory = zitrus.memory;
const gpu = zitrus.gpu;
