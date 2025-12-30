//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Hardware

pub const arm9_ticks_per_s = 134_055_928;
pub const arm11_ticks_per_s = arm9_ticks_per_s * 2;

/// New3DS prototype according to 3dbrew. Can be seen in PDN registers.
pub const arm11_lgr1_ticks_per_s = arm11_ticks_per_s * 2;
pub const arm11_lgr2_ticks_per_s = arm11_ticks_per_s * 3;
pub const arm11_new_ticks_per_s = arm11_lgr2_ticks_per_s;

pub const ns_per_arm11_tick = @as(comptime_float, std.time.ns_per_s) / @as(comptime_float, arm11_ticks_per_s);

/// Current nanoseconds from `horizon.getSystemTick`
pub fn getSystemNanoseconds() u96 {
    const scale: u64 = @as(u64, std.time.ns_per_s << 32) / arm11_ticks_per_s;
    return (@as(u96, horizon.getSystemTick()) * scale) >> 32;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
