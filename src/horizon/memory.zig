// https://www.3dbrew.org/wiki/Memory_layout#ARM11%20User-land%20memory%20regions

pub const executable_memory_begin: usize = 0x00100000;
pub const heap_memory_begin: usize = 0x08000000;
pub const heap_memory_end: usize = 0x10000000;
pub const shared_memory_begin: usize = heap_memory_end;
pub const shared_memory_end: usize = 0x14000000;
pub const linear_heap_memory_begin: usize = shared_memory_end;
pub const linear_heap_memory_end: usize = 0x1E800000;
