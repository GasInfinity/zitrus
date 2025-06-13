pub const RelativeComponent = enum(u2) {
    none,
    x,
    y,
    l,
};

pub const SourceRegister = enum(u7) {
    pub const Limited = enum(u5) {
        // zig fmt: off
        v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15,
        r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
        // zig fmt: on
    };

    pub const Kind = enum {
        input,
        temporary,
        constant,

        pub fn amount(k: Kind) usize {
            return switch (k) {
                .input, .temporary => 16,
                .constant => 96,
            };
        }
    };

    // zig fmt: off
    v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15,
    r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,
    f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15,
    f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29,
    f30, f31, f32, f33, f34, f35, f36, f37, f38, f39, f40, f41, f42, f43,
    f44, f45, f46, f47, f48, f49, f50, f51, f52, f53, f54, f55, f56, f57,
    f58, f59, f60, f61, f62, f63, f64, f65, f66, f67, f68, f69, f70, f71,
    f72, f73, f74, f75, f76, f77, f78, f79, f80, f81, f82, f83, f84, f85,
    f86, f87, f88, f89, f90, f91, f92, f93, f94, f95, 
    // zig fmt: on

    pub fn initLimited(limited: Limited) SourceRegister {
        return @enumFromInt(@intFromEnum(limited));
    }

    pub fn initInput(register: u4) SourceRegister {
        return @enumFromInt(register);
    }

    pub fn initTemporary(register: u4) SourceRegister {
        return @enumFromInt(@as(u5, 1 << 4) | register);
    }

    pub fn initConstant(register: u7) SourceRegister {
        std.debug.assert(register < Kind.constant.amount());
        return @enumFromInt(register + 0x20);
    }

    pub fn initKind(k: Kind, index: u7) SourceRegister {
        return switch (k) {
            .input => .initInput(@intCast(index)),
            .temporary => .initTemporary(@intCast(index)),
            .constant => .initConstant(index),
        };
    }

    pub fn isLimited(register: SourceRegister) bool {
        return @as(u7, @intFromEnum(register)) < 32;
    }

    pub fn toLimited(register: SourceRegister) ?Limited {
        return if (register.isLimited()) @enumFromInt(@as(u5, @intCast(@intFromEnum(register)))) else null;
    }

    pub fn kind(register: SourceRegister) Kind {
        return switch (@intFromEnum(register)) {
            else => |r| if (r > 0x1F) .constant else (if ((r & (1 << 4)) != 0) .temporary else .input),
        };
    }

    pub const ParseError = error{
        Syntax,
        InvalidRegister,
        InvalidIndex,
    };

    pub fn parse(value: []const u8) ParseError!SourceRegister {
        if (value.len < 2 or (!std.ascii.isAlphabetic(value[0]) or !std.ascii.isDigit(value[1]))) {
            return error.Syntax;
        }

        const k: Kind = @enumFromInt(std.mem.indexOf(u8, "vrf", &.{value[0]}) orelse return error.InvalidRegister);

        const index = std.fmt.parseUnsigned(u7, value[1..], 10) catch |err| switch (err) {
            error.Overflow => return error.InvalidIndex,
            error.InvalidCharacter => return error.Syntax,
        };

        if (index >= k.amount()) {
            return error.InvalidIndex;
        }

        return SourceRegister.initKind(k, index);
    }

    test parse {
        try testing.expectEqual(SourceRegister.v0, try parse("v0"));
        try testing.expectEqual(SourceRegister.v15, try parse("v15"));
        try testing.expectEqual(SourceRegister.r0, try parse("r0"));
        try testing.expectEqual(SourceRegister.r15, try parse("r15"));
        try testing.expectEqual(SourceRegister.f95, try parse("f95"));
        try testing.expectError(error.InvalidRegister, parse("o5"));
        try testing.expectError(error.InvalidIndex, parse("v16"));
        try testing.expectError(error.InvalidIndex, parse("f105"));
    }
};

pub const DestinationRegister = enum(u5) {
    pub const Kind = enum {
        output,
        temporary,

        pub fn amount(_: Kind) usize {
            return 16;
        }
    };

    // zig fmt: off
    o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10, o11, o12, o13, o14, o15,
    r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, 
    // zig fmt: on

    pub fn initOutput(register: u4) DestinationRegister {
        return @enumFromInt(register);
    }

    pub fn initTemporary(register: u4) DestinationRegister {
        return @enumFromInt(@as(u5, 1 << 4) | register);
    }

    pub fn initKind(k: Kind, register: u4) DestinationRegister {
        return switch (k) {
            .output => .initOutput(register),
            .temporary => .initTemporary(register),
        };
    }

    pub fn kind(register: DestinationRegister) Kind {
        return if ((@intFromEnum(register) & (1 << 4)) != 0) .temporary else .output;
    }

    pub const ParseError = error{
        Syntax,
        InvalidRegister,
        InvalidIndex,
    };

    pub fn parse(value: []const u8) ParseError!DestinationRegister {
        if (value.len < 2 or (!std.ascii.isAlphabetic(value[0]) or !std.ascii.isDigit(value[1]))) {
            return error.Syntax;
        }

        const k: Kind = @enumFromInt(std.mem.indexOf(u8, "or", &.{value[0]}) orelse return error.InvalidRegister);

        const index = std.fmt.parseUnsigned(u4, value[1..], 10) catch |err| switch (err) {
            error.Overflow => return error.InvalidIndex,
            error.InvalidCharacter => return error.Syntax,
        };

        if (index >= k.amount()) {
            return error.InvalidIndex;
        }

        return DestinationRegister.initKind(k, index);
    }

    test parse {
        try testing.expectEqual(DestinationRegister.o0, try parse("o0"));
        try testing.expectEqual(DestinationRegister.o15, try parse("o15"));
        try testing.expectEqual(DestinationRegister.r0, try parse("r0"));
        try testing.expectEqual(DestinationRegister.r15, try parse("r15"));
        try testing.expectError(error.InvalidRegister, parse("i5"));
        try testing.expectError(error.InvalidIndex, parse("o16"));
        try testing.expectError(error.InvalidIndex, parse("r105"));
    }
};

pub const BooleanRegister = enum(u4) {
    b0,
    b1,
    b2,
    b3,
    b4,
    b5,
    b6,
    b7,
    b8,
    b9,
    b10,
    b11,
    b12,
    b13,
    b14,
    b15,
};

pub const IntegerRegister = enum(u4) { i0, i1, i2, i3 };

pub const IntegralRegister = packed union {
    bool: BooleanRegister,
    int: IntegerRegister,
};

comptime {
    std.debug.assert(@typeInfo(RelativeComponent).@"enum".is_exhaustive);
    std.debug.assert(@typeInfo(SourceRegister).@"enum".is_exhaustive);
    std.debug.assert(@typeInfo(DestinationRegister).@"enum".is_exhaustive);
}

const std = @import("std");
const testing = std.testing;
