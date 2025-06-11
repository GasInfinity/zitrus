pub const OperandDescriptorAllocationError = error{OutOfDescriptors};

const max_descriptors = std.math.maxInt(u7);

instructions: ArrayList(Instruction),
descriptors: [max_descriptors]OperandDescriptor,
allocated_descriptors: u7,

pub fn init() Encoder {
    return .{
        .instructions = .empty,
        .descriptors = undefined,
        .allocated_descriptors = 0,
    };
}

pub fn deinit(encoder: *Encoder, allocator: Allocator) void {
    encoder.instructions.deinit(allocator);
}

// TODO: Use and allocate partial operand descriptors (to reuse them)
pub fn getOrAllocateFullOperandDescriptor(encoder: *Encoder, comptime T: type, operand_descriptor: OperandDescriptor) OperandDescriptorAllocationError!T {
    std.debug.assert(T == u5 or T == u7);

    for (encoder.descriptors[0..encoder.allocated_descriptors], 0..) |descriptor, i| {
        if(operand_descriptor == descriptor) {
            return @intCast(i);
        }
    }

    if(encoder.descriptors.len == encoder.allocated_descriptors) {
        return error.OutOfDescriptors;
    }

    if(encoder.allocated_descriptors < std.math.maxInt(T)) {
        encoder.descriptors[encoder.allocated_descriptors] = operand_descriptor;
        encoder.allocated_descriptors += 1;
        return encoder.allocated_descriptors - 1;
    }

    // TODO:
    // Swap a non-reduced descriptor or return error
    return error.OutOfDescriptors;
}

pub fn addInstruction(encoder: *Encoder, allocator: Allocator, instruction: Instruction) !void {
    if(std.meta.activeTag(instruction).descriptorSize()) |sz| switch (sz) {
        5 => std.debug.assert(@as(u5, @truncate(instruction.raw())) < encoder.allocated_descriptors),
        7 => std.debug.assert(@as(u7, @truncate(instruction.raw())) < encoder.allocated_descriptors),
        else => unreachable,
    };

    try encoder.instructions.append(allocator, instruction);
}

pub fn add(encoder: *Encoder, alloc: Allocator, dst: DestinationRegister, dst_mask: Mask, src1: SourceRegister, src1_selector: Selector, src1_neg: bool, src1_rel: RelativeComponent, src2: SourceRegister.Limited, src2_selector: Selector, src2_neg: bool) !void { 
    const descriptor_id = try encoder.getOrAllocateFullOperandDescriptor(u7, .{
        .destination_mask = dst_mask,
        .src1_neg = src1_neg,
        .src1_selector = src1_selector,
        .src2_neg = src2_neg,
        .src2_selector = src2_selector,
        .src3_neg = false,
        .src3_selector = .xyzw,
    });

    try encoder.addInstruction(alloc, .{ .register = .{
        .operand_descriptor_id = descriptor_id,
        .src2 = src2,
        .src1 = src1,
        .address_index = src1_rel,
        .dst = dst,
        .opcode = .add,
    }});
}

test Encoder {
    const expected_output: []const u32 = &.{
        0x02000080 
    };

    var encoder: Encoder = .init();
    defer encoder.deinit(testing.allocator);

    try encoder.add(testing.allocator, .r0, .x, .v0, .xyzw, false, .none, .v1, .xyzw, false);

    for (encoder.instructions.items, expected_output) |ins, expected| {
        try testing.expectEqual(expected, ins.raw());
    }
}

const Encoder = @This();

const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const encoding = @import("encoding.zig");
const Instruction = encoding.Instruction;
const OperandDescriptor = encoding.OperandDescriptor;

const Mask = encoding.Component.Mask;
const Selector = encoding.Component.Selector;

const register = @import("register.zig");
const RelativeComponent = register.RelativeComponent;
const SourceRegister = register.SourceRegister;
const DestinationRegister = register.DestinationRegister;
