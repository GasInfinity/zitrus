pub const OperandDescriptor = packed struct(u32) {
    pub const Component = enum(u2) {
        pub const Mask = packed struct(u4) { x: bool, y: bool, z: bool, w: bool };
        pub const Selector = packed struct(u8) { @"3": Component, @"2": Component, @"1": Component, @"0": Component };

        x,
        y,
        z,
        w,
    };

    destination_mask: Component.Mask,
    src1_neg: bool,
    src1_selector: Component.Selector,
    src2_neg: bool,
    src2_selector: Component.Selector,
    src3_neg: bool,
    src3_selector: Component.Selector,
};

pub const ComparisonOperation = enum(u3) { eq, ne, lt, le, gt, ge, _ };

pub const Condition = enum(u2) {
    @"or",
    @"and",
    x,
    y,
};

pub const RelativeRegister = enum(u3) { none, x, y, l };

pub const SourceRegister = enum(u7) {
    pub const Limited = enum(u5) { _ };
    pub const Kind = enum { input, temporary, constant };
    _,

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
        return @enumFromInt(register + 0x20);
    }

    pub fn kind(register: SourceRegister) Kind {
        return switch (@intFromEnum(register)) {
            else => |r| if (r > 0x1F) .constant else (if ((r & (1 << 4)) != 0) .temporary else .input),
        };
    }
};

pub const DestinationRegister = enum(u5) {
    pub const Kind = enum { output, temporary };
    _,

    pub fn initOutput(register: u4) SourceRegister {
        return @enumFromInt(register);
    }
    pub fn initTemporary(register: u4) SourceRegister {
        return @enumFromInt(@as(u5, 1 << 4) | register);
    }

    pub fn kind(register: DestinationRegister) Kind {
        return if ((@intFromEnum(register) & (1 << 4)) != 0) .temporary else .input;
    }
};

pub const Instruction = union(Format) {
    pub const Opcode = enum(u6) {
        pub const Mad = enum(u3) { _ };
        pub const Comparison = enum(u5) { _ };

        add,
        dp3,
        dp4,
        dph,
        dst,
        ex2,
        lg2,
        litp,
        mul,
        sge,
        slt,
        flr,
        max,
        min,
        rcp,
        rsq,

        mova = 0x12,
        mov,

        dphi = 0x18,
        dsti,
        sgei,
        slti,

        @"break" = 0x20,
        nop,
        end,
        breakc,
        call,
        callc,
        callu,
        ifu,
        ifc,
        loop,
        emit,
        setemit,
        jmpc,
        jmpu,
        cmp = 0x2E, // - 0x2F
        madi = 0x30, // - 0x37
        mad = 0x38, // - 0x3F
        _,

        pub fn toComparison(opcode: Opcode) ?Comparison {
            return switch (opcode) {
                .cmp...@as(Opcode, @enumFromInt(0x2F)) => @enumFromInt(@intFromEnum(.cmp) >> 3),
                else => null,
            };
        }

        pub fn toMad(opcode: Opcode) ?Mad {
            return switch (opcode) {
                .madi...@as(Opcode, @enumFromInt(0x37)) => @enumFromInt(@intFromEnum(.madi) >> 3),
                .mad...@as(Opcode, @enumFromInt(0x3F)) => @enumFromInt(@intFromEnum(.mad) >> 3),
                else => null,
            };
        }
    };

    pub const format = struct {
        pub const Unparametized = packed struct(u32) { _unused0: u26, opcode: u6 };

        pub fn Register(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u7,
                src2: (if (inverted) SourceRegister else SourceRegister.Limited),
                src1: (if (inverted) SourceRegister.Limited else SourceRegister),
                address_index: RelativeRegister,
                dst: DestinationRegister,
                opcode: Opcode,
            };
        }

        pub const Comparison = packed struct(u32) {
            operand_descriptor_id: u7,
            src2: SourceRegister.Limited,
            src1: SourceRegister,
            address_index: RelativeRegister,
            x_operation: ComparisonOperation,
            y_operation: ComparisonOperation,
            opcode: Opcode.Comparison,
        };

        pub const ControlFlow = packed struct(u32) {
            num: u8,
            dst_word_offset: u12,
            condition: Condition,
            ref_y: bool,
            ref_x: bool,
            opcode: Opcode,
        };

        pub const ConstantControlFlow = packed struct(u32) {
            num: u8,
            dst_word_offset: u12,
            constant_id: u4,
            opcode: Opcode,
        };

        pub const SetEmit = packed struct(u32) {
            _unused: u22,
            winding: bool,
            primitive_emit: bool,
            vertex_id: u2,
            opcode: Opcode,
        };

        pub fn Mad(comptime inverted: bool) type {
            return packed struct(u32) {
                operand_descriptor_id: u5,
                src3: (if (inverted) SourceRegister else SourceRegister.Limited),
                src2: (if (inverted) SourceRegister.Limited else SourceRegister),
                src1: SourceRegister.Limited,
                address_index: RelativeRegister,
                opcode: Opcode.Mad,
            };
        }
    };

    pub const Format = enum {
        unparametized,
        register,
        register_inverted,
        register_unary,
        comparison,
        control_flow,
        constant_control_flow,
        set_emit,
        mad,
        mad_inverted,

        pub fn operands(fmt: Format) usize {
            return switch (fmt) {
                .unparametized => 0,
                .register_unary, .comparison => 2,
                .register, .register_inverted => 3,
                .control_flow => 1,
                .constant_control_flow => 2,
                .set_emit => 1,
                .mad, .mad_inverted => 4,
            };
        }
    };

    const Encoding = struct { format: Format };

    unparametized: format.Unparametized,
    register: format.Register(false),
    register_inverted: format.Register(true),
    register_unary: format.Register(false),
    comparison: format.Comparison,
    control_flow: format.ControlFlow,
    constant_control_flow: format.ConstantControlFlow,
    set_emit: format.SetEmit,
    mad: format.Mad(false),
    mad_inverted: format.Mad(true),

    pub const opcode_to_encoding = encoding_map: {
        const Entry = struct { Instruction.Opcode, Instruction.Format };
        const encodings: []const Entry = @import("encodings.zon");

        var set = std.EnumMap(Instruction.Opcode, Instruction.Encoding).init(.{});

        for (encodings) |encoding| {
            set.put(encoding[0], .{ .format = encoding[1] });
        }

        break :encoding_map set;
    };
};

// TODO:
// - Write a assembler/disassembler
// - Handle assembler correctness
// - https://www.3dbrew.org/wiki/SHBIN

const std = @import("std");
