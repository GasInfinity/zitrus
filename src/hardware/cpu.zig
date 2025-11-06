//! Definitions for ARM instructions and MMIO registers
//! which are common to both CPUs.
//!
//! See `arm9` and `arm11` for cpu-specific things.
//!
//! Based on the technical reference manuals of both.

pub const arm9 = @import("cpu/arm9.zig");
pub const arm11 = @import("cpu/arm11.zig");

pub inline fn wfi() void {
    asm volatile ("mcr p15, 0, r0, c7, c0, 4");
}

const zitrus = @import("zitrus");
