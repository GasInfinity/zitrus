//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Hardware

pub const arm9_ticks_per_s = time.arm9_ticks_per_s;
pub const arm11_ticks_per_s = time.arm11_ticks_per_s;

/// New3DS prototype according to 3dbrew. Can be seen in PDN registers.
pub const arm11_lgr1_ticks_per_s = time.arm11_lgr1_ticks_per_s;
pub const arm11_lgr2_ticks_per_s = time.arm11_lgr2_ticks_per_s;
pub const arm11_new_ticks_per_s = time.arm11_new_ticks_per_s;

pub const ns_per_arm11_tick = @as(comptime_float, std.time.ns_per_s) / @as(comptime_float, arm11_ticks_per_s);

pub const unix_epoch_since_ntp_ms = 2_208_988_800_000;

/// Current nanoseconds from `horizon.getSystemTick`
pub fn getSystemNanoseconds() u96 {
    const scale: u64 = @as(u64, std.time.ns_per_s << 32) / arm11_ticks_per_s;
    return (@as(u96, horizon.getSystemTick()) * scale) >> 32;
}

/// Current milliseconds elapsed since January 1900 (NTP)
pub fn getRealMilliseconds() u64 {
    return horizon.memory.shared_config.latestSystemTime().current();
}

/// Current milliseconds elapsed since January 1970 (Unix)
pub fn getUnixMilliseconds() u64 {
    return getRealMilliseconds() -| unix_epoch_since_ntp_ms;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const time = zitrus.time;
