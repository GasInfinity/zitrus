/// Represents an `AlignedPhysicalAddress` with no alignment.
pub const PhysicalAddress = AlignedPhysicalAddress(.@"1", .@"1");

/// Represents a `PhysicalAddress` which is aligned to `address_alignment` and stored with `address_shift`
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

/// Represents a a register which only spans the LSB bits of a word, leaving the others unused.
pub fn LsbRegister(comptime T: type) type {
    std.debug.assert(@bitSizeOf(T) < @bitSizeOf(u32));

    return packed struct(u32) {
        const Lsb = @This();

        value: T,
        _: std.meta.Int(.unsigned, @bitSizeOf(u32) - @bitSizeOf(T)) = 0,

        pub fn init(value: T) Lsb {
            return .{ .value = value };
        }
    };
}

/// Represents a a register which only spans the MSB bits of a word, leaving the others unused.
pub fn MsbRegister(comptime T: type) type {
    std.debug.assert(@bitSizeOf(T) < @bitSizeOf(u32));

    return packed struct(u32) {
        const Msb = @This();

        _: std.meta.Int(.unsigned, @bitSizeOf(u32) - @bitSizeOf(T)) = 0,
        value: T,

        pub fn init(value: T) Msb {
            return .{ .value = value };
        }
    };
}

pub const pica = @import("hardware/pica.zig");
pub const csnd = @import("hardware/csnd.zig");

const std = @import("std");
