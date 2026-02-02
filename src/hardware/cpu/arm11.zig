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

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const BitpackedArray = hardware.BitpackedArray;
