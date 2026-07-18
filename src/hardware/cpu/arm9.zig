pub const Kind = enum(u1) { data, instruction };
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

pub const Cachable = packed struct(u32) {
    area: BitpackedArray(bool, 8),
    _: u24 = 0,

    pub inline fn read(comptime kind: Kind) Cachable {
        return asm volatile ("mrc p15, 0, %[cnt], c2, c0, %[kind]"
            : [cnt] "=r" (-> Cachable),
            : [kind] "i" (@intFromEnum(kind))
        ); 
    }

    pub inline fn write(cachable: Cachable, comptime kind: Kind) void {
        return asm volatile ("mcr p15, 0, %[cnt], c2, c0, %[kind]"
            :
            : [cnt] "r" (cachable),
              [kind] "i" (@intFromEnum(kind))
        ); 
    }
};

pub const Bufferable = packed struct(u32) {
    area: BitpackedArray(bool, 8),
    _: u24 = 0,

    pub inline fn read() Bufferable {
        return asm volatile ("mrc p15, 0, %[cnt], c3, c0, 0"
            : [cnt] "=r" (-> Bufferable),
        ); 
    }

    pub inline fn write(bufferable: Bufferable) void {
        return asm volatile ("mcr p15, 0, %[cnt], c3, c0, 0" 
            :
            : [cnt] "r" (bufferable),
        ); 
    }
};

pub const Access = packed struct(u32) {
    pub const Extended = packed struct(u32) {
        pub const Permission = enum(u4) {
            none = 0b0000,
            p_rw = 0b0001,
            p_rw_u_ro = 0b0010,
            p_ro = 0b0101,
            p_ro_u_ro = 0b0110,
            _,
        };


        area: BitpackedArray(Extended.Permission, 8),

        pub inline fn read(comptime kind: Kind) Cachable {
            return asm volatile ("mrc p15, 0, %[cnt], c5, c0, %[kind]"
                : [cnt] "=r" (-> Access),
                : [kind] "i" (2 + @intFromEnum(kind))
            ); 
        }

        pub inline fn write(access: Access, comptime kind: Kind) void {
            return asm volatile ("mcr p15, 0, %[cnt], c5, c0, %[kind]"
                :
                : [cnt] "r" (access),
                  [kind] "i" (2 + @intFromEnum(kind))
            ); 
        }
    };
    
    pub const Permission = enum(u2) {
        none,
        p_rw,
        p_rw_u_ro,
        p_rw_u_rw,
    };

    area: BitpackedArray(Permission, 8),
    _: u16 = 0,

    pub inline fn read(comptime kind: Kind) Cachable {
        return asm volatile ("mrc p15, 0, %[cnt], c5, c0, %[kind]"
            : [cnt] "=r" (-> Access),
            : [kind] "i" (@intFromEnum(kind))
        ); 
    }

    pub inline fn write(access: Access, comptime kind: Kind) void {
        return asm volatile ("mcr p15, 0, %[cnt], c5, c0, %[kind]"
            :
            : [cnt] "r" (access),
              [kind] "i" (@intFromEnum(kind))
        ); 
    }
};


pub const Region = packed struct(u32) {
    pub const Size = enum(u5) {
        @"4KB" = 0b01011,
        @"8KB",
        @"16KB",
        @"32KB",
        @"64KB",
        @"128KB",
        @"256KB",
        @"1MB",
        @"2MB",
        @"4MB",
        @"8MB",
        @"16MB",
        @"32MB",
        @"64MB",
        @"128MB",
        @"256MB",
        @"512MB",
        @"1GB",
        @"2GB",
        @"4GB",
        _,
    };

    enable: bool,
    size: Size,
    _unused0: u6 = 0,
    base: u20,
    
    pub inline fn read(comptime unit: u3) Region {
        return asm volatile ("mrc p15, 0, %[cnt], c5, c%[unit:c], 0"
            : [cnt] "=r" (-> Region),
            : [unit] "i" (@as(u32, unit))
        ); 
    }

    pub inline fn write(region: Region, comptime unit: u3) void {
        return asm volatile ("mcr p15, 0, %[cnt], c5, c%[unit:c], 0"
            :
            : [cnt] "r" (region),
              [unit] "i" (@as(u32, unit))
        ); 
    }
};

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const BitpackedArray = hardware.BitpackedArray;
