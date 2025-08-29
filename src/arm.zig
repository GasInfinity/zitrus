pub inline fn dsb() void {
    asm volatile ("mcr p15, 0, %[unused], c7, c10, 4"
        :
        : [unused] "r" (0),
        : .{ .memory = true });
}
