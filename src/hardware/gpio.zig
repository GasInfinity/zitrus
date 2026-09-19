//! Definitions for MMIO `GPIO` registers.
//!
//! Based on the documentation found in 3dbrew:
//! - https://www.3dbrew.org/wiki/GPIO_Registers 

pub const Direction = enum(u1) { input, output };
pub const Configuration = enum(u1) { rising, falling };

pub const Plain = extern struct {
    data: hardware.BitpackedArray(bool, 8),
    _unused0: [15]u8,
};

pub const Configurable = extern struct {
    data: hardware.BitpackedArray(bool, 8),
    direction: hardware.BitpackedArray(Direction, 8),
    irq_config: hardware.BitpackedArray(Configuration, 8),
    irq_enable: hardware.BitpackedArray(bool, 8),
    extra: hardware.BitpackedArray(bool, 16),
    _unused0: [10]u8,
};

pub const Registers = extern struct {
    @"1": Plain,
    @"2": Configurable,
    @"3": Configurable,
};

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
