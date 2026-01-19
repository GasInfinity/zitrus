//! Definitions for ARM instructions and MMIO registers
//! which are common to both CPUs.
//!
//! See `arm9` and `arm11` for cpu-specific things.
//!
//! Based on the technical reference manuals of both.

// TODO: Not tested

pub const arm9 = @import("cpu/arm9.zig");
pub const arm11 = @import("cpu/arm11.zig");

// CP15 c0 c0 0 -> ID
// CP15 c0 c0 1 -> Cache Type

pub inline fn wfi() void {
    asm volatile ("mcr p15, 0, %[sbz], c7, c0, 4"
        :
        : [sbz] "r" (0),
    );
}

pub inline fn dsb() void {
    asm volatile ("mcr p15, 0, %[sbz], c7, c10, 4"
        :
        : [sbz] "r" (0),
    );
}

pub inline fn dmb() void {
    asm volatile ("mcr p15, 0, %[sbz], c7, c10, 5"
        :
        : [sbz] "r" (0),
    );
}

pub const cache = struct {
    pub const SetWay = packed struct(u32) {
        _reserved0: u4 = 0,
        /// Depends on cache size
        set: u13,
        _reserved1: u13,
        way: u2,

        pub inline fn invalidateInstruction(set_way: SetWay) void {
            asm volatile ("mcr p15, 0, %[sw], c7, c5, 2"
                :
                : [sw] "r" (set_way),
            );
        }

        pub inline fn invalidateData(set_way: SetWay) void {
            asm volatile ("mcr p15, 0, %[sw], c7, c6, 2"
                :
                : [sw] "r" (set_way),
            );
        }

        pub inline fn cleanData(set_way: SetWay) void {
            asm volatile ("mcr p15, 0, %[sw], c7, c10, 2"
                :
                : [sw] "r" (set_way),
            );
        }

        pub inline fn flushData(set_way: SetWay) void {
            asm volatile ("mcr p15, 0, %[sw], c7, c14, 2"
                :
                : [sw] "r" (set_way),
            );
        }
    };

    pub const Address = packed struct(u32) {
        virtual: u32,

        pub inline fn invalidateInstruction(address: Address) void {
            asm volatile ("mcr p15, 0, %[addr], c7, c5, 1"
                :
                : [addr] "r" (address),
            );
        }

        pub inline fn invalidateData(address: Address) void {
            asm volatile ("mcr p15, 0, %[addr], c7, c6, 1"
                :
                : [addr] "r" (address),
            );
        }

        pub inline fn cleanData(address: Address) void {
            asm volatile ("mcr p15, 0, %[addr], c7, c10, 1"
                :
                : [addr] "r" (address),
            );
        }

        pub inline fn flushData(address: Address) void {
            asm volatile ("mcr p15, 0, %[addr], c7, c14, 1"
                :
                : [addr] "r" (address),
            );
        }

        pub inline fn flushBranchPredictor(address: Address) void {
            asm volatile ("mcr p15, 0, %[addr], c7, c5, 7"
                :
                : [addr] "r" (address),
            );
        }
    };

    pub inline fn flushPrefetchBuffer() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c5, 4"
            :
            : [sbz] "r" (0),
        );
    }

    pub inline fn flushBranchPredictor() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c5, 6"
            :
            : [sbz] "r" (0),
        );
    }

    /// Also flushes branch predictor cache
    pub inline fn invalidateInstruction() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c5, 0"
            :
            : [sbz] "r" (0),
        );
    }

    pub inline fn invalidateData() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c6, 0"
            :
            : [sbz] "r" (0),
        );
    }

    /// Also flushes branch predictor cache
    pub inline fn invalidate() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c7, 0"
            :
            : [sbz] "r" (0),
        );
    }

    pub inline fn cleanData() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c10, 0"
            :
            : [sbz] "r" (0),
        );
    }

    pub inline fn flushData() void {
        asm volatile ("mcr p15, 0, %[sbz], c7, c14, 0"
            :
            : [sbz] "r" (0),
        );
    }
};

comptime {
    _ = arm11;
    _ = arm9;
}

const zitrus = @import("zitrus");
