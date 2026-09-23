//! Based on the ARM11 MPCore r2p0 Technical Reference Manual

// CP15 c0 c0 3 -> TLB Type
// CP15 c0 c0 5 -> CPUID
// CP15 c0 c1 -> Feature Registers
// CP15 c0 c2 -> ISA Attributes Registers

pub const Control = packed struct(u32) {
    pub const Auxiliary = packed struct(u32) {
        pub const Multiprocessing = enum(u1) { amp, smp };

        return_stack: bool = false,
        dynamic_branch_prediction: bool = false,
        static_branch_prediction: bool = false,
        instruction_folding: bool = false,
        exclusive_caches: bool = false,
        multiprocessing: Multiprocessing,
        l1_parity_errors: bool = false,
        _reserved0: u25 = 0,

        pub inline fn read() Auxiliary {
            return asm volatile ("mrc p15, 0, %[cnt], c1, c0, 1"
                : [cnt] "=r" (-> Auxiliary),
            );
        }

        pub inline fn write(cnt: Auxiliary) void {
            return asm volatile ("mcr p15, 0, %[cnt], c1, c0, 1"
                :
                : [cnt] "r" (cnt),
            );
        }
    };

    mmu: bool = false,
    /// Data abort on unaligned loads/stores
    strict_alignment: bool = false,
    l1_data_cache: bool = false,
    _reserved0: u4 = std.math.maxInt(u4),
    _reserved1: u1 = 0,
    /// Deprecated
    system_protection: bool = false,
    /// Deprecated
    rom_protection: bool = false,
    _reserved2: u1 = 0,
    branch_prediction: bool = false,
    l1_instruction_cache: bool = false,
    alternate_exception_vectors: bool = false,
    _reserved3: u1 = 1,
    disable_thumb_by_pc_loads: bool = false,
    _unused0: u6 = 0,
    unaligned_access: bool = false,
    subpage_access_permissions: bool = false,
    _reserved4: u1 = 0,
    set_cpsr_e_on_exception: bool = false,
    _reserved5: u1 = 0,
    non_maskable_fast_irq: bool = false,
    tex_remap: bool = false,
    force_access_permissions: bool = false,
    _reserved6: u2 = 0,

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

pub const CoprocessorAccess = packed struct(u32) {
    pub const Mode = enum(u2) { denied, supervisor, full = 3 };

    _reserved0: u20 = 0,
    @"10": Mode = .denied,
    @"11": Mode = .denied,
    _reserved1: u8 = 0,

    pub inline fn read() CoprocessorAccess {
        return asm volatile ("mrc p15, 0, %[acc], c1, c0, 2"
            : [acc] "=r" (-> CoprocessorAccess),
        );
    }

    pub inline fn write(acc: CoprocessorAccess) void {
        return asm volatile ("mcr p15, 0, %[acc], c1, c0, 2"
            :
            : [acc] "r" (acc),
        );
    }
};

pub const TranslationTable = extern struct {
    pub const Cachable = enum(u2) {
        none,
        write_back_allocate,
        write_through,
        write_back,
    };

    pub const Base = packed struct(u32) {
        _reserved0: u1 = 0,
        shared: bool = false,
        _reserved1: u1 = 0,
        region: Cachable = .none,
        /// TTBL 0 base depends on `Control.separate_table_boundary` and TTBL 1 is restricted to 16KB pages
        base: u27,

        pub inline fn read(comptime table: u1) Base {
            return asm volatile ("mrc p15, 0, %[base], c2, c0, %[reg]"
                : [base] "=r" (-> Base),
                : [reg] "i" (table),
            );
        }

        pub inline fn write(base: Base, comptime table: u1) void {
            return asm volatile ("mcr p15, 0, %[base], c2, c0, %[reg]"
                :
                : [base] "r" (base),
                  [reg] "i" (table),
            );
        }
    };

    pub const Control = packed struct(u32) {
        pub const Boundary = enum(u3) {
            @"16KB",
            @"8KB",
            @"4KB",
            @"2KB",
            @"1KB",
            @"512B",
            @"256B",
            @"128B",
        };

        separate_table_boundary: Boundary,
        _reserved0: u29 = 0,

        pub inline fn read() TranslationTable.Control {
            return asm volatile ("mrc p15, 0, %[cnt], c2, c0, 2"
                : [cnt] "=r" (-> TranslationTable.Control),
            );
        }

        pub inline fn write(cnt: TranslationTable.Control) void {
            return asm volatile ("mcr p15, 0, %[cnt], c2, c0, 2"
                :
                : [cnt] "r" (cnt),
            );
        }
    };
};

pub const DomainAccess = packed struct(u32) {
    pub const Mode = enum(u2) { none, client, manager = 3 };

    access: BitpackedArray(Mode, 16),

    pub inline fn read() DomainAccess {
        return asm volatile ("mrc p15, 0, %[acc], c3, c0, 0"
            : [acc] "=r" (-> DomainAccess),
        );
    }

    pub inline fn write(acc: DomainAccess) void {
        return asm volatile ("mcr p15, 0, %[acc], c3, c0, 0"
            :
            : [acc] "r" (acc),
        );
    }
};

pub const Fault = packed struct(u32) {
    pub const Kind = enum(u1) { data, instruction };
    pub const Operation = enum(u1) { read, write };
    pub const Status = enum(u5) {
        alignment = 0b00001,
        instruction_cache_maintenance = 0b00100,
        first_level_external_abort = 0b01100,
        second_level_external_abort = 0b01110,
        section_translation = 0b00101,
        page_translation = 0b00111,
        section_access = 0b00011,
        page_access = 0b00110,
        section_domain = 0b01001,
        page_domain = 0b01011,
        section_permission = 0b01101,
        page_permission = 0b01111,
        precise_external_abort = 0b01000,
        imprecise_external_abort = 0b10110,
        debug = 0b00010,
        _,
    };

    status_lo: u4,
    domain: u4,
    _reserved0: u2 = 0,
    status_hi: u1,
    operation: Operation,
    external_abort: bool,
    _reserved1: u19,

    pub fn status(fault: Fault) Status {
        return @enumFromInt(fault.status_lo | (@as(u5, fault.status_hi) << 4));
    }

    pub inline fn read(comptime kind: Kind) Fault {
        return asm volatile ("mrc p15, 0, %[st], c5, c0, %[kind]"
            : [st] "=r" (-> DomainAccess),
            : [kind] "i" (@intFromEnum(kind)),
        );
    }

    pub inline fn write(st: Fault, comptime kind: Kind) void {
        return asm volatile ("mcr p15, 0, %[st], c5, c0, %[kind]"
            :
            : [st] "r" (st),
              [kind] "i" (@intFromEnum(kind)),
        );
    }

    pub const Address = packed struct(u32) {
        pub const Kind = enum(u1) { default, watchpoint };

        virtual: u32,

        pub inline fn read(comptime kind: Address.Kind) u32 {
            return asm volatile ("mrc p15, 0, %[addr], c6, c0, %[kind]"
                : [addr] "=r" (-> Address),
                : [kind] "i" (@intFromEnum(kind)),
            );
        }

        pub inline fn write(addr: Address, comptime kind: Address.Kind) void {
            return asm volatile ("mcr p15, 0, %[addr], c6, c0, %[kind]"
                :
                : [addr] "r" (addr),
                  [kind] "i" (@intFromEnum(kind)),
            );
        }
    };
};

pub fn Monitor(comptime T: type) type {
    return extern struct {
        raw: T,

        pub fn init(value: T) MonitorSelf {
            return .{ .raw = value };
        }

        /// Performs a load, putting the monitor into a exclusive access state.
        pub fn load(mon: *const MonitorSelf) T {
            return switch (@bitSizeOf(T)) {
                8 => @bitCast(asm volatile ("ldrexb %[to], %[ptr]"
                    : [to] "=r" (-> u8),
                    : [ptr] "p" (&mon.raw),
                )),
                16 => @bitCast(asm volatile ("ldrexh %[to], %[ptr]"
                    : [to] "=r" (-> u16),
                    : [ptr] "p" (&mon.raw),
                )),
                32 => @bitCast(asm volatile ("ldrex %[to], %[ptr]"
                    : [to] "=r" (-> u32),
                    : [ptr] "p" (&mon.raw),
                )),
                64 => asm volatile ("ldrexd %[to:Q], %[to:R], %[ptr]"
                    : [to] "=r" (-> u64),
                    : [ptr] "p" (&mon.raw),
                ),
                else => @compileError("Unsupported Monitor(" ++ @typeName(T) ++ ")"),
            };
        }

        /// Tries to perform a store. If the monitor is still in exclusive access after a
        /// `load`, the store succeeds and returns `false` putting the monitor into an
        /// open state again.
        ///
        /// Spurious changes to an open state may happen.
        pub fn store(mon: *MonitorSelf, value: T) bool {
            return switch (@bitSizeOf(T)) {
                8 => asm volatile ("strexb %[fail], %[value], %[ptr]"
                    : [fail] "=&r" (-> bool),
                    : [ptr] "p" (&mon.raw),
                      [value] "r" (value),
                    : .{ .memory = true }),
                16 => asm volatile ("strexh %[fail], %[value], %[ptr]"
                    : [fail] "=&r" (-> bool),
                    : [ptr] "p" (&mon.raw),
                      [value] "r" (value),
                    : .{ .memory = true }),
                32 => asm volatile ("strex %[fail], %[value], %[ptr]"
                    : [fail] "=&r" (-> bool),
                    : [ptr] "p" (&mon.raw),
                      [value] "r" (value),
                    : .{ .memory = true }),
                64 => asm volatile ("strexd %[fail], %[value:Q], %[value:R], %[ptr]"
                    : [fail] "=&r" (-> bool),
                    : [ptr] "p" (&mon.raw),
                      [value] "r" (value),
                    : .{ .memory = true }),
                else => @compileError("Unsupported Monitor(" ++ @typeName(T) ++ ")"),
            };
        }

        /// Puts the monitor into an open state.
        pub fn clear(_: *MonitorSelf) void {
            asm volatile ("clrex");
        }

        const MonitorSelf = @This();
    };
}

pub const Interrupt = enum(u7) {
    // zig fmt: off
    soft_0, soft_1, soft_2, soft_3, soft_4,
    soft_5, soft_6, soft_7, soft_8, soft_9,
    soft_10, soft_11, soft_12, soft_13, soft_14,
    soft_15,
    p_16, p_17, p_18, p_19, p_20, p_21, p_22,
    p_23, p_24, p_25, p_26, p_27, p_28,
    private_timer,
    private_watchdog,
    legacy,
    u_32, u_33, u_34, u_35,
    spi_2 = 0x24,
    u_37, u_38, u_39,
    psc0 = 0x28,
    psc1 = 0x29,
    pdc0 = 0x2a,
    pdc1 = 0x2b,
    ppf = 0x2c,
    p3d = 0x2d,
    u_46, u_47,
    old_cdma_0, old_cdma_1, old_cdma_2,
    old_cdma_3, old_cdma_4, old_cdma_5,
    old_cdma_6, old_cdma_7, old_cdma_8,
    old_cdma_faulting = 0x39,
    new_cdma = 0x3a,
    new_cdma_faulting = 0x3b,
    u_60, u_61, u_62, u_63,
    wifi_sdio_0 = 0x40,
    wifi_sdio_1 = 0x41,
    debug_wifi_sdio_0 = 0x42,
    debug_wifi_sdio_1 = 0x43,
    ntrcard = 0x44,
    l2b_0 = 0x45,
    l2b_1 = 0x46,
    u_70,
    camera_inner_right = 0x48,
    camera_left = 0x49,
    dsp = 0x4a,
    y2r1 = 0x4b,
    lgy_fb_0 = 0x4c,
    lgy_fb_1 = 0x4d,
    y2r2 = 0x4e,
    mvd = 0x4f,
    pxi_sync_0 = 0x50,
    pxi_sync_1 = 0x51,
    pxi_send_empty = 0x52,
    pxi_receive_not_empty = 0x53,
    i2c_0 = 0x54,
    i2c_1 = 0x55,
    spi_0 = 0x56,
    spi_1 = 0x57,
    pdn = 0x58,
    pdn_legacy = 0x59,
    mic = 0x5a,
    hid = 0x5b,
    i2c_2 = 0x5c,
    u_93, u_94,
    mp = 0x5f,
    shell_opened = 0x60,
    u_97,
    shell_closed = 0x62,
    touch_pressed = 0x63,
    headphones_inserted = 0x64,
    u_101,
    twl_depop = 0x66,
    u_103,
    new_hid = 0x68,
    ir = 0x69,
    gyroscope = 0x6a,
    new_hid_stop = 0x6b,
    ir_tx = 0x6c,
    ir_rx = 0x6d,
    nfc_0 = 0x6e,
    nfc_1 = 0x6f,
    headphones_button = 0x70,
    mcu = 0x71,
    nfc_2 = 0x72,
    qtm = 0x73,
    gamecard_related = 0x74,
    gamecard_inserted = 0x75,
    l2c = 0x76,
    u_119,
    performance_counter_overflow_0 = 0x78,
    performance_counter_overflow_1 = 0x79,
    performance_counter_overflow_2 = 0x7a,
    performance_counter_overflow_3 = 0x7b,
    u_124, u_125, u_126,
    none = 0x7f,
    // zig fmt: on
};

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const BitpackedArray = hardware.BitpackedArray;
