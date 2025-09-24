//! ## Zitrus - 3DS SDK
//!
//! Zitrus is a SDK for writing code for the 3DS family. It doesn't discriminate usage,
//! it can be used to write normal *applications*, *sysmodules* and even *freestanding* code.
//!
//! ## Namespaces
//!
//! * `compress` - Compression and decompression functions used in some 3DS formats.
//!
//! * `fmt` - File formats not originating from `horizon`, e.g: `fmt.@"3dsx"`, `fmt.zpsh`.
//!
//! * `horizon` - Horizon OS support layer. You'll be using this most of the time.
//!
//! * `hardware` - Low-level and type-safe 3DS hardware registers.
//!
//! * `mango` - A Vulkan-like graphics api for the PICA200.

// TODO: Remove this somehow, the kernel COULD be able to provide us with a stack of X size if we could ask somehow in the 3dsx to luma/azahar
pub const ZitrusOptions = struct {
    stack_size: u32,
};

// XXX: Remove this when zig finally supports 64-bit atomics in ARMv6K+
pub fn atomicLoad64(comptime T: type, ptr: *T) T {
    if (@sizeOf(T) != 8) @compileError("only supported with 64-bit types");

    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("ldrexd %[lo], %[hi], [%[ptr]]"
        : [lo] "={r0}" (lo),
          [hi] "={r1}" (hi),
        : [ptr] "{r0}" (ptr),
    );

    return @bitCast((@as(u64, hi) << 32) | @as(u64, lo));
}

pub fn atomicStore64(comptime T: type, ptr: *T, value: T) void {
    if (@sizeOf(T) != 8) @compileError("only supported with 64-bit types");

    const value_u64: u64 = @bitCast(value);

    while (true) {
        asm volatile ("ldrexd r4, r5, [%[ptr]]"
            :
            : [ptr] "{r0}" (ptr),
            : .{ .r4 = true, .r5 = true, .memory = true });

        if (asm volatile ("strexd %[fail], %[lo], %[hi], [%[ptr]]"
            : [fail] "={r1}" (-> u32),
            : [lo] "{r2}" (@as(u32, @truncate(value_u64))),
              [hi] "{r3}" (@as(u32, @truncate(value_u64 >> 32))),
              [ptr] "{r0}" (ptr),
            : .{ .memory = true }) == 0)
            break;
    }
}

comptime {
    _ = horizon.start;

    _ = compress;
    _ = fmt;
    _ = horizon;

    _ = pica;
    _ = mango;
}

/// Deprecated: use `hardware.PhysicalAddress`
pub const PhysicalAddress = hardware.PhysicalAddress;

/// Deprecated: use `hardware.AlignedPhysicalAddress`
pub const AlignedPhysicalAddress = hardware.AlignedPhysicalAddress;

pub const c = @import("c.zig");

pub const fmt = @import("fmt.zig");
pub const compress = @import("compress.zig");
pub const memory = @import("memory.zig");
pub const horizon = @import("horizon.zig");
pub const hardware = @import("hardware.zig");
pub const math = @import("math.zig");

pub const mango = @import("mango.zig");

// Deprecated: use `hardware.pica`
pub const pica = hardware.pica;

const builtin = @import("builtin");
const std = @import("std");
