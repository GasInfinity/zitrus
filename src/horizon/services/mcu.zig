//! MCU services
//!
//! Based on 3dbrew:
//! - https://www.3dbrew.org/wiki/MCU_Services

pub const Realtime = extern struct {
    second: u8,
    minute: u8,
    hour: u8,
    weekday: u8,
    day: u8,
    month: u8,
    year: u8,
};

pub const Codec = @import("mcu/Codec.zig");
pub const Platform = @import("mcu/Platform.zig");
