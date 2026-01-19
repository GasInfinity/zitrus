pub const Control = packed struct(u32) {
    mmu: bool = false,
    _reserved0: u1 = 0,
    data_cache: bool = false,
    _reserved1: u4 = std.math.maxInt(u4),
    big_endian: bool = false,
    _reserved2: u4 = 0,
    instruction_cache: bool = false,
    alternate_exception_vectors: bool = false,
    cache_round_robin_replacement: bool = false,
    disable_thumb_by_pc_loads: bool = false,
    data_tcm: bool = false,
    data_tcm_load_mode: bool = false,
    instruction_tcm: bool = false,
    instruction_tcm_load_mode: bool = false,
    _reserved3: u12 = 0,

    pub inline fn read() Control {
        return asm volatile ("mrc p15, 0, %[cnt], c1, c0, 0"
            : [cnt] "=r" (-> Control),
        );
    }

    pub inline fn write(cnt: Control) void {
        return asm volatile ("mcr p15, 0, %[cnt], c1, c0, 0"
            :
            : [cnt] "r" (cnt),
        );
    }
};

pub const Interrupt = packed struct(u32) {
    pub const Registers = extern struct {
        enable: Interrupt,
        flags: Interrupt,
    };

    pub const Pxi = packed struct(u3) {
        sync: bool,
        send_emoty: bool,
        receive_full: bool,
    };

    pub const Sdio = packed struct(u2) {
        controller: bool,
        async: bool,
    };

    pub const Debug = packed struct(u2) {
        receive: bool,
        send: bool,
    };

    pub const Gamecard = packed struct(u2) {
        power_off: bool,
        insert: bool,
    };

    pub const Xdma = packed struct(u2) {
        event: bool,
        fault: bool,
    };

    ndma: BitpackedArray(bool, 8),
    timer: BitpackedArray(bool, 4),
    pxi: Pxi,
    aes: bool,
    sdio: BitpackedArray(Sdio, 2),
    debug: Debug,
    rsa: bool,
    ctr_card: BitpackedArray(bool, 2),
    gamecard: Gamecard,
    ntr_card: bool,
    xdma: Xdma,
    _unused0: u2 = 0,
};

// CP15 c0 c0 2 -> TCM size

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const BitpackedArray = hardware.BitpackedArray;
