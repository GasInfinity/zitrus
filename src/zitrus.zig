// TODO: Remove this somehow, the kernel COULD be able to provide us with a stack of X size if we could ask somehow in the 3dsx to luma/azahar
pub const ZitrusOptions = struct {
    stack_size: u32,
};

// XXX: Remove this when zig finally supports 64-bit atomics in ARMv6K+
pub fn atomicLoad64(comptime T: type, ptr: *T) T {
    if (@sizeOf(T) != 8) @compileError("only supported with 64-bit types");

    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile ("ldrexd %[lo], %[hi], [%[ptr]]"
        : [lo] "={r0}" (lo),
          [hi] "={r1}" (hi),
        : [ptr] "{r0}" (ptr),
    );

    return @bitCast((@as(u64, hi) << 32) | @as(u64, lo));
}

pub fn atomicStore64(comptime T: type, ptr: *T, value: T) void {
    if (@sizeOf(T) != 8) @compileError("only supported with 64-bit types");

    const value_u64: u64 = @bitCast(value);

    while (true) {
        asm volatile ("ldrexd r4, r5, [%[ptr]]"
            :
            : [ptr] "{r0}" (ptr),
            : .{ .r4 = true, .r5 = true, .memory = true });

        if (asm volatile ("strexd %[fail], %[lo], %[hi], [%[ptr]]"
            : [fail] "={r1}" (-> u32),
            : [lo] "{r2}" (@as(u32, @truncate(value_u64))),
              [hi] "{r3}" (@as(u32, @truncate(value_u64 >> 32))),
              [ptr] "{r0}" (ptr),
            : .{ .memory = true }) == 0)
            break;
    }
}

pub const PhysicalAddress = AlignedPhysicalAddress(.@"1", .@"1");

pub fn AlignedPhysicalAddress(comptime address_alignment: std.mem.Alignment, comptime address_shift: std.mem.Alignment) type {
    std.debug.assert(address_alignment.order(address_shift) != .lt);

    return enum(u32) {
        zero = 0x00,
        _,

        const AlignedPhysAddr = @This();
        pub const alignment = address_alignment;
        pub const shift = address_shift;

        pub fn fromAddress(address: usize) AlignedPhysAddr {
            return .fromPhysical(@as(PhysicalAddress, @enumFromInt(address)));
        }

        pub fn fromPhysical(aligned_address: anytype) AlignedPhysAddr {
            const OtherAlignedPhysAddr = @TypeOf(aligned_address);

            if (@typeInfo(OtherAlignedPhysAddr) != .@"enum" or !@hasDecl(OtherAlignedPhysAddr, "alignment") or !@hasDecl(OtherAlignedPhysAddr, "shift"))
                @compileError("please provide a valid AlignedPhysicalAddress to .of()");

            const other_alignment = @field(OtherAlignedPhysAddr, "alignment");
            const other_shift = @field(OtherAlignedPhysAddr, "shift");

            if (@TypeOf(other_alignment) != std.mem.Alignment or @TypeOf(other_shift) != std.mem.Alignment or OtherAlignedPhysAddr != AlignedPhysicalAddress(other_alignment, other_shift))
                @compileError("please provide a valid AlignedPhysicalAddress to .of()");

            const address = @intFromEnum(aligned_address) << @intCast(std.math.log2(other_shift.toByteUnits()));

            if (alignment.order(other_alignment) != .lt) {
                std.debug.assert(alignment.check(address));
            }

            return @enumFromInt(address >> @intCast(std.math.log2(shift.toByteUnits())));
        }
    };
}

comptime {
    _ = horizon.start;

    _ = compress;
    _ = fmt;
    _ = horizon;

    _ = pica;
    _ = mango;
}

pub const c = @import("c.zig");

pub const fmt = @import("fmt.zig");
pub const compress = @import("compress.zig");
pub const memory = @import("memory.zig");
pub const horizon = @import("horizon.zig");
pub const pica = @import("pica.zig");
pub const math = @import("math.zig");

pub const mango = @import("mango.zig");

const builtin = @import("builtin");
const std = @import("std");
