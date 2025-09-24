//! Type-safe PICA200 shader ISA encoder

pub const Negate = enum(u1) { @"+", @"-" };
pub const OperandDescriptorAllocationError = error{OutOfDescriptors};
pub const InstructionEncodingError = error{InvalidSourceRegisterCombination};

const max_descriptors = std.math.maxInt(u7);

instructions: std.ArrayList(Instruction),
descriptors: [max_descriptors]OperandDescriptor,
masks: [max_descriptors]OperandDescriptor.Mask,
allocated_descriptors: u8,

pub const init: Encoder = .{
    .instructions = .empty,
    .descriptors = undefined,
    .masks = undefined,
    .allocated_descriptors = 0,
};

pub fn move(encoder: *Encoder) Encoder {
    defer encoder.* = .init;
    return encoder.*;
}

pub fn deinit(encoder: *Encoder, allocator: Allocator) void {
    encoder.instructions.deinit(allocator);
    encoder.* = undefined;
}

pub fn getOrAllocateOperandDescriptor(encoder: *Encoder, comptime T: type, comptime descriptor_mask: OperandDescriptor.Mask, operand_descriptor: OperandDescriptor) OperandDescriptorAllocationError!T {
    std.debug.assert(T == u5 or T == u7);

    for (encoder.descriptors[0..encoder.allocated_descriptors], encoder.masks[0..encoder.allocated_descriptors], 0..) |*descriptor, *mask, i| {
        if (mask.*.contains(descriptor_mask) and operand_descriptor.equalsMasked(descriptor_mask, descriptor.*)) {
            // Reuse the descriptor
            return @intCast(i);
        }

        if (descriptor_mask.contains(mask.*) and operand_descriptor.equalsMasked(mask.*, descriptor.*)) {
            // Reuse and expand the descriptor
            descriptor.* = operand_descriptor;
            mask.* = descriptor_mask;
            return @intCast(i);
        }
    }

    if (encoder.descriptors.len == encoder.allocated_descriptors) {
        return error.OutOfDescriptors;
    }

    if (encoder.allocated_descriptors < std.math.maxInt(T)) {
        encoder.descriptors[encoder.allocated_descriptors] = operand_descriptor;
        encoder.masks[encoder.allocated_descriptors] = descriptor_mask;
        encoder.allocated_descriptors += 1;
        return @intCast(encoder.allocated_descriptors - 1);
    }

    // TODO:
    // Swap a non-reduced descriptor or return error
    return error.OutOfDescriptors;
}

pub fn addInstruction(encoder: *Encoder, allocator: Allocator, instruction: Instruction) !void {
    try encoder.instructions.append(allocator, instruction);
}

pub fn unparametized(encoder: *Encoder, alloc: Allocator, opcode: Instruction.Opcode) !void {
    return encoder.addInstruction(alloc, .{ .unparametized = .{ .opcode = opcode } });
}

pub fn unary(encoder: *Encoder, alloc: Allocator, opcode: Instruction.Opcode, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    const descriptor_id = try encoder.getOrAllocateOperandDescriptor(u7, .unary, .{
        .destination_mask = dst_mask,
        .src1_neg = src1_neg == .@"-",
        .src1_selector = src1_selector,
    });

    return encoder.addInstruction(alloc, .{ .register = .{
        .operand_descriptor_id = descriptor_id,
        .src1 = src1,
        .src2 = .v0,
        .address_index = src_rel,
        .dst = dest,
        .opcode = opcode,
    } });
}

pub fn binary(encoder: *Encoder, alloc: Allocator, opcode: Instruction.Opcode, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    if (!src1.isLimited() and !src2.isLimited()) {
        return error.InvalidSourceRegisterCombination;
    }

    if (src1.isLimited() != src2.isLimited() and !src2.isLimited()) {
        if (!opcode.isCommutative()) {
            if (opcode.invert()) |opcode_i| {
                const descriptor_id = try encoder.getOrAllocateOperandDescriptor(u7, .binary, .{ .destination_mask = dst_mask, .src1_neg = src1_neg == .@"-", .src1_selector = src1_selector, .src2_neg = src2_neg == .@"-", .src2_selector = src2_selector });

                return encoder.addInstruction(alloc, .{ .register_inverted = .{ .operand_descriptor_id = descriptor_id, .src2 = src2, .src1 = src1.toLimited().?, .address_index = src_rel, .dst = dest, .opcode = opcode_i } });
            }

            return error.InvalidSourceRegisterCombination;
        }

        const descriptor_id = try encoder.getOrAllocateOperandDescriptor(u7, .binary, .{ .destination_mask = dst_mask, .src1_neg = src2_neg == .@"-", .src1_selector = src2_selector, .src2_neg = src1_neg == .@"-", .src2_selector = src1_selector });

        return encoder.addInstruction(alloc, .{ .register = .{ .operand_descriptor_id = descriptor_id, .src2 = src1.toLimited().?, .src1 = src2, .address_index = src_rel, .dst = dest, .opcode = opcode } });
    }

    // TODO: If commutative we could search and reuse an operand descriptor with swapped src1 <=> src2
    const descriptor_id = try encoder.getOrAllocateOperandDescriptor(u7, .binary, .{ .destination_mask = dst_mask, .src1_neg = src1_neg == .@"-", .src1_selector = src1_selector, .src2_neg = src2_neg == .@"-", .src2_selector = src2_selector });

    return encoder.addInstruction(alloc, .{ .register = .{ .operand_descriptor_id = descriptor_id, .src2 = src2.toLimited().?, .src1 = src1, .address_index = src_rel, .dst = dest, .opcode = opcode } });
}

pub fn flow(encoder: *Encoder, alloc: Allocator, opcode: Instruction.Opcode, num: u8, dest: u12, condition: Condition, x: bool, y: bool) !void {
    return encoder.addInstruction(alloc, .{ .control_flow = .{
        .num = num,
        .dst = dest,
        .condition = condition,
        .ref_x = x,
        .ref_y = y,
        .opcode = opcode,
    } });
}

pub fn flowConstant(encoder: *Encoder, alloc: Allocator, opcode: Instruction.Opcode, num: u8, dest: u12, constant: IntegralRegister) !void {
    return encoder.addInstruction(alloc, .{ .constant_control_flow = .{
        .num = num,
        .dst = dest,
        .constant_id = constant,
        .opcode = opcode,
    } });
}

pub fn add(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .add, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn dp3(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .dp3, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn dp4(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .dp4, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn dph(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .dph, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn dst(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .dst, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn ex2(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .ex2, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn lg2(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .lg2, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn litp(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .litp, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn mul(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .mul, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn sge(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .sge, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn slt(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .slt, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn flr(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .flr, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn max(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .max, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn min(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.binary(alloc, .min, dest, dst_mask, src1_neg, src1, src1_selector, src2_neg, src2, src2_selector, src_rel);
}

pub fn rcp(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .rcp, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn rsq(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .rsq, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

pub fn mova(encoder: *Encoder, alloc: Allocator, a_mask: register.RelativeComponent.Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .mova, .o0, .{ .enable_x = a_mask.enable_x, .enable_y = a_mask.enable_y }, src1_neg, src1, src1_selector, src_rel);
}

pub fn mov(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src_rel: RelativeComponent) !void {
    return encoder.unary(alloc, .mov, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
}

// dphi handled by dph
// dsti handled by dst
// sgei handled by sge
// slti handled by slt

pub fn @"break"(encoder: *Encoder, alloc: Allocator) !void {
    return encoder.unparametized(alloc, .@"break");
}

pub fn nop(encoder: *Encoder, alloc: Allocator) !void {
    return encoder.unparametized(alloc, .nop);
}

pub fn end(encoder: *Encoder, alloc: Allocator) !void {
    return encoder.unparametized(alloc, .end);
}

pub fn breakc(encoder: *Encoder, alloc: Allocator, condition: Condition, x: bool, y: bool) !void {
    return encoder.flow(alloc, .breakc, 0, 0, condition, x, y);
}

pub fn call(encoder: *Encoder, alloc: Allocator, dest: i12, num: u8) !void {
    return encoder.flow(alloc, .call, num, dest, .@"and", false, false);
}

pub fn callc(encoder: *Encoder, alloc: Allocator, condition: Condition, x: bool, y: bool, dest: i12, num: u8) !void {
    return encoder.flow(alloc, .callc, num, dest, condition, x, y);
}

pub fn callu(encoder: *Encoder, alloc: Allocator, b: BooleanRegister, dest: u12, num: u8) !void {
    return encoder.flowConstant(alloc, .callu, num, dest, .{ .bool = b });
}

pub fn ifu(encoder: *Encoder, alloc: Allocator, b: BooleanRegister, dest: u12, num: u8) !void {
    return encoder.flowConstant(alloc, .ifu, num, dest, .{ .bool = b });
}

pub fn ifc(encoder: *Encoder, alloc: Allocator, condition: Condition, x: bool, y: bool, dest: u12, num: u8) !void {
    return encoder.flow(alloc, .ifc, num, dest, condition, x, y);
}

pub fn loop(encoder: *Encoder, alloc: Allocator, i: IntegerRegister, dest: u12) !void {
    return encoder.flowConstant(alloc, .loop, 0, dest, .{ .int = .{ .used = i } });
}

pub fn setemit(encoder: *Encoder, alloc: Allocator, vertex_id: u2, primitive: Primitive, winding: Winding) !void {
    return encoder.addInstruction(alloc, .{ .set_emit = .{
        .winding = winding,
        .primitive_emit = primitive,
        .vertex_id = vertex_id,
        .opcode = .setemit,
    } });
}

pub fn emit(encoder: *Encoder, alloc: Allocator) !void {
    return encoder.unparametized(alloc, .emit);
}

pub fn jmpc(encoder: *Encoder, alloc: Allocator, condition: Condition, x: bool, y: bool, dest: u12) !void {
    return encoder.flow(alloc, .jmpc, 0, dest, condition, x, y);
}

pub fn jmpu(encoder: *Encoder, alloc: Allocator, b: BooleanRegister, if_true: bool, dest: u12) !void {
    return encoder.flowConstant(alloc, .jmpu, @intFromBool(!if_true), dest, .{ .bool = b });
}

pub fn cmp(encoder: *Encoder, alloc: Allocator, src1_neg: Negate, src1: SourceRegister, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src_rel: RelativeComponent, x: Comparison, y: Comparison) !void {
    if (!src1.isLimited() and !src2.isLimited()) {
        return error.InvalidSourceRegisterCombination;
    }

    const descriptor_id, const i_src1, const i_src2, const x_cmp, const y_cmp = if (!src2.isLimited())
        .{ try encoder.getOrAllocateOperandDescriptor(u7, .comparison, .{ .src1_neg = src2_neg == .@"-", .src1_selector = src2_selector, .src2_neg = src1_neg == .@"-", .src2_selector = src1_selector }), src2, src1.toLimited().?, x.invert(), y.invert() }
    else
        .{ try encoder.getOrAllocateOperandDescriptor(u7, .comparison, .{ .src1_neg = src1_neg == .@"-", .src1_selector = src1_selector, .src2_neg = src2_neg == .@"-", .src2_selector = src2_selector }), src1, src2.toLimited().?, x, y };

    return encoder.addInstruction(alloc, .{ .comparison = .{
        .operand_descriptor_id = descriptor_id,
        .src2 = i_src2,
        .src1 = i_src1,
        .address_index = src_rel,
        .x_operation = x_cmp,
        .y_operation = y_cmp,
        .opcode = Instruction.Opcode.cmp.toComparison().?,
    } });
}

// madi handled by mad

pub fn mad(encoder: *Encoder, alloc: Allocator, dest: DestinationRegister, dst_mask: Mask, src1_neg: Negate, src1: SourceRegister.Limited, src1_selector: Selector, src2_neg: Negate, src2: SourceRegister, src2_selector: Selector, src3_neg: Negate, src3: SourceRegister, src3_selector: Selector, src_rel: RelativeComponent) !void {
    if (!src2.isLimited() and !src3.isLimited()) {
        return error.InvalidSourceRegisterCombination;
    }

    const descriptor_id = try encoder.getOrAllocateOperandDescriptor(u5, .full, .{
        .destination_mask = dst_mask,
        .src1_neg = src1_neg == .@"-",
        .src1_selector = src1_selector,
        .src2_neg = src2_neg == .@"-",
        .src2_selector = src2_selector,
        .src3_neg = src3_neg == .@"-",
        .src3_selector = src3_selector,
    });

    if (src2.isLimited() != src3.isLimited() and src2.isLimited()) {
        return try encoder.addInstruction(alloc, .{ .mad_inverted = .{
            .operand_descriptor_id = descriptor_id,
            .src1 = src1,
            .src2 = src2.toLimited().?,
            .src3 = src3,
            .address_index = src_rel,
            .dst = dest,
            .opcode = Instruction.Opcode.madi.toMad().?,
        } });
    }

    return try encoder.addInstruction(alloc, .{ .mad = .{
        .operand_descriptor_id = descriptor_id,
        .src1 = src1,
        .src2 = src2,
        .src3 = src3.toLimited().?,
        .address_index = src_rel,
        .dst = dest,
        .opcode = Instruction.Opcode.mad.toMad().?,
    } });
}

test Encoder {
    var fixed: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fixed);
    const alloc = fba.allocator();

    const expected_output: []const u32 = &.{
        0b000000_10000_00_0000000_00001_0000000,
        0b001011_10001_00_0010000_00000_0000000,
        0b001000_10001_00_0000011_01000_0000001,
    };

    var encoder: Encoder = .init;
    defer encoder.deinit(alloc);

    try encoder.add(alloc, .r0, .x, .@"+", .v0, .xyzw, .@"+", .v1, .xyzw, .none);

    // Must have same descriptor as the previous instruction
    try encoder.flr(alloc, .r1, .x, .@"+", .r0, .xyzw, .none);

    // Should create a new descriptor
    try encoder.mul(alloc, .r1, .x, .@"+", .v3, .wyxz, .@"+", .v8, .xxxx, .none);

    // FIXME: Regression, cannot use this on the 3DS test runner.
    // try testing.expectEqualSlices(u32, expected_output, std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(encoder.instructions.items)));
    for (expected_output, std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(encoder.instructions.items))) |output, expected| {
        try testing.expect(expected == output);
    }
}

const Encoder = @This();

const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

const zitrus = @import("zitrus");
const shader = zitrus.pica.shader;

const encoding = shader.encoding;
const Instruction = encoding.Instruction;
const OperandDescriptor = encoding.OperandDescriptor;
const Condition = encoding.Condition;
const Comparison = encoding.ComparisonOperation;
const Winding = encoding.Winding;
const Primitive = encoding.Primitive;

const Mask = encoding.Component.Mask;
const Selector = encoding.Component.Selector;

const register = shader.register;
const RelativeComponent = register.RelativeComponent;
const SourceRegister = register.Source;
const DestinationRegister = register.Destination;

const IntegralRegister = register.Integral;
const BooleanRegister = IntegralRegister.Boolean;
const IntegerRegister = IntegralRegister.Integer;
