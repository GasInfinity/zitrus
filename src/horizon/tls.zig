pub const ThreadLocalData = extern struct {
    undefined0: [0x40]u8,
    exception_return: *anyopaque,
    exception_sp_control: u32,
    exception_context_control: u32,
    undefined1: [0x34]u8,
    ipc: ipc.Buffer,
};

pub inline fn getThreadLocalStorage() *ThreadLocalData {
    return asm volatile ("mrc p15, 0, %[tls], cr13, cr0, 3"
        : [tls] "=r" (-> *ThreadLocalData),
    );
}

const ipc = @import("ipc.zig");
