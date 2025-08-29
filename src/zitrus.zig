// TODO: Remove this somehow, the kernel COULD be able to provide us with a stack of X size if we could ask somehow in the 3dsx to luma/azahar
pub const ZitrusOptions = struct {
    stack_size: u32,
};

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
    _ = start;

    _ = fmt;
    _ = horizon;

    _ = pica;
    _ = mango;
}

pub const fmt = @import("fmt.zig");
pub const panic = @import("panic.zig");
pub const arm = @import("arm.zig");
pub const memory = @import("memory.zig");
pub const start = @import("start.zig");
pub const horizon = @import("horizon.zig");
pub const pica = @import("pica.zig");
pub const math = @import("math.zig");

pub const mango = @import("mango.zig");

const builtin = @import("builtin");
const std = @import("std");
