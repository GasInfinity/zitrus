pub inline fn ldrex(address: *const u32) u32 {
    return asm volatile ("ldrex %[loaded], [%[address]]"
        : [loaded] "=r" (-> u32),
        : [address] "r" (address),
        : "memory"
    );
}

pub inline fn strex(address: *u32, value: u32) bool {
    return asm volatile ("strex %[failed], %[value], [%[address]]"
        : [failed] "=&r" (-> u32),
        : [address] "r" (address),
          [value] "r" (value),
        : "memory"
    ) == 0;
}

pub inline fn clrex() void {
    asm volatile ("clrex" ::: "memory");
}

pub inline fn dsb() void {
    asm volatile ("mcr p15, 0, %[unused], c7, c10, 4"
        :
        : [unused] "r" (0),
        : "memory"
    );
}
