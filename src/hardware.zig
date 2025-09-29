//! Definitions for 3DS hardware

pub const pica = @import("hardware/pica.zig");
pub const csnd = @import("hardware/csnd.zig");

/// Represents a register which is triggered by writing a value to it.
pub const Trigger = enum(u1) { trigger = 1 };

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

/// Represents a a register which only spans the LSb of a word, leaving the others unused.
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

/// Represents a a register which only spans the MSb of a word, leaving the others unused.
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

/// Represents a bitpacked array of `n` elements of `T`.
/// Stored in native endian.
///
/// A `BitpackedArray` is stored from LSb (0) to MSb (n - 1).
pub fn BitpackedArray(comptime T: type, comptime n: usize) type {
    const total_bit_size = @bitSizeOf(T) * n;
    const ArrayInt = std.meta.Int(.unsigned, total_bit_size);
    const ElementInt = std.meta.Int(.unsigned, @bitSizeOf(T));

    return packed struct(ArrayInt) {
        pub const Int = ArrayInt;

        raw: ArrayInt,

        pub inline fn init(value: [n]T) Self {
            // NOTE: Cannot be `undefined`, any `undefined` bits make the entire value `undefined`.
            var bt: Self = std.mem.zeroes(Self);
            inline for (0..n) |i| bt.set(i, value[i]);
            return bt;
        }

        pub inline fn splat(value: T) Self {
            // NOTE: Cannot be `undefined`, any `undefined` bits make the entire value `undefined`.
            var bt: Self = std.mem.zeroes(Self);
            inline for (0..n) |i| bt.set(i, value);
            return bt;
        }

        pub inline fn slice(bt: Self, index: usize, comptime len: usize) BitpackedArray(T, len) {
            // TODO: Safety check?
            const NewBitpacked = BitpackedArray(T, len);
            const bt_int: Int = @bitCast(bt);
            const new_bt_int: NewBitpacked.Int = @truncate(bt_int >> (index * @bitSizeOf(T)));
            return @bitCast(new_bt_int);
        }

        pub inline fn get(bt: Self, index: usize) T {
            const value = std.mem.readPackedIntNative(ElementInt, @ptrCast(&bt.raw), index * @bitSizeOf(ElementInt));

            return switch (@typeInfo(T)) {
                .@"enum" => @enumFromInt(value),
                else => @bitCast(value),
            };
        }

        pub inline fn copyWith(bt: Self, comptime index: usize, value: T) Self {
            var new_bt: Self = bt;
            new_bt.set(index, value);
            return new_bt;
        }

        pub inline fn set(bt: *Self, index: usize, value: T) void {
            std.mem.writePackedIntNative(ElementInt, @ptrCast(&bt.raw), index * @bitSizeOf(ElementInt), switch (@typeInfo(T)) {
                .@"enum" => @intFromEnum(value),
                else => @bitCast(value),
            });
        }

        const Self = @This();
    };
}

comptime {
    _ = pica;
    _ = csnd;
}

const testing = std.testing;

test BitpackedArray {
    const Thing = enum(u1) { foo, bar };
    const ThingArray = BitpackedArray(Thing, 4);

    var bt: ThingArray = .splat(.foo);

    bt.set(3, .bar);

    try testing.expect(bt.get(3) == .bar);

    bt.set(3, .foo);

    try testing.expect(bt.get(3) == .foo);

    bt.set(0, .bar);

    try testing.expect(bt.get(0) == .bar);
}

const std = @import("std");
