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

comptime {
    _ = horizon;

    _ = compress;
    _ = memory;
    _ = fmt;
    _ = time;
    _ = horizon;
    _ = hardware;
    _ = math;
    _ = debug;

    _ = mango;
}

pub const c = @import("c.zig");

pub const fmt = @import("fmt.zig");
pub const compress = @import("compress.zig");
pub const memory = @import("memory.zig");
pub const time = @import("time.zig");
pub const horizon = @import("horizon.zig");
pub const hardware = @import("hardware.zig");
pub const math = @import("math.zig");
pub const debug = @import("debug.zig");

pub const mango = @import("mango.zig");

const builtin = @import("builtin");
const std = @import("std");

pub const std_os_options: std.Options.OperatingSystem = if (builtin.target.os.tag == .@"3ds")
    horizon.default_std_os_options
else
    .{};
