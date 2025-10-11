//! Zitrus PICA200 shader
//!
//! A simple shader format which omits the need for positional reads and has an overall simpler structure.
//! It omits numerous things that are not used or cannot be used by zitrus.
//!
//! Even if things are tightly packed, all sections are aligned to 32-bits.

pub const Header = extern struct {
    pub const magic_value = "ZPSH";

    pub const ShaderSize = packed struct(u16) {
        code_minus_one: u9,
        operands_minus_one: u7,

        pub fn init(code_size: usize, operands_size: usize) ShaderSize {
            return .{
                .code_minus_one = @intCast(code_size - 1),
                .operands_minus_one = @intCast(operands_size - 1),
            };
        }

        pub fn codeSize(size: ShaderSize) usize {
            return @as(usize, size.code_minus_one) + 1;
        }

        pub fn operandsSize(size: ShaderSize) usize {
            return @as(usize, size.operands_minus_one) + 1;
        }
    };

    magic: [magic_value.len]u8 = magic_value.*,
    shader_size: ShaderSize,
    entrypoints: u16,
    string_table_size: u32,
};

pub const EntrypointHeader = extern struct {
    pub const ShaderInfo = packed struct(u16) {
        type: shader.Type,
        _unused0: u15 = 0,
    };

    pub const BooleanConstantMask = packed struct(u16) {
        // zig fmt: off
        b0: bool, b1: bool, b2: bool, b3: bool, b4: bool, b5: bool, b6: bool, b7: bool,
        b8: bool, b9: bool, b10: bool, b11: bool, b12: bool, b13: bool, b14: bool, b15: bool,
        // zig fmt: on

        pub fn fromSet(set: std.EnumSet(BooleanRegister)) BooleanConstantMask {
            var mask: BooleanConstantMask = undefined;

            for (std.enums.values(BooleanRegister)) |b| {
                std.mem.writePackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(b), @intFromBool(set.contains(b)), .little);
            }

            return mask;
        }

        pub fn toSet(mask: BooleanConstantMask) std.EnumSet(BooleanRegister) {
            var set: std.EnumSet(BooleanRegister) = undefined;

            for (std.enums.values(BooleanRegister)) |b| {
                set.setPresent(b, std.mem.readPackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(b), .little) != 0);
            }

            return set;
        }
    };

    pub const IntegerConstantMask = packed struct(u16) {
        // zig fmt: off
        i0: bool, i1: bool,
        i2: bool, i3: bool,
        // zig fmt: on
        _: u12,

        pub fn fromSet(set: std.EnumSet(IntegerRegister)) IntegerConstantMask {
            var mask: IntegerConstantMask = undefined;

            for (std.enums.values(IntegerRegister)) |i| {
                std.mem.writePackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(i), @intFromBool(set.contains(i)), .little);
            }

            return mask;
        }

        pub fn toSet(mask: IntegerConstantMask) std.EnumSet(IntegerRegister) {
            var set: std.EnumSet(IntegerRegister) = undefined;

            for (std.enums.values(IntegerRegister)) |i| {
                set.setPresent(i, std.mem.readPackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(i), .little) != 0);
            }

            return set;
        }
    };

    pub const FloatingConstantMask = extern struct {
        // zig fmt: off
        pub const Low = packed struct(u32) {
            f0: bool, f1: bool, f2: bool, f3: bool, f4: bool, f5: bool, f6: bool, f7: bool,
            f8: bool, f9: bool, f10: bool, f11: bool, f12: bool, f13: bool, f14: bool, f15: bool,
            f16: bool, f17: bool, f18: bool, f19: bool, f20: bool, f21: bool, f22: bool, f23: bool,
            f24: bool, f25: bool, f26: bool, f27: bool, f28: bool, f29: bool, f30: bool, f31: bool, 
        };

        pub const Mid = packed struct(u32) {
            f32: bool, f33: bool, f34: bool, f35: bool, f36: bool, f37: bool, f38: bool, f39: bool,
            f40: bool, f41: bool, f42: bool, f43: bool, f44: bool, f45: bool, f46: bool, f47: bool,
            f48: bool, f49: bool, f50: bool, f51: bool, f52: bool, f53: bool, f54: bool, f55: bool,
            f56: bool, f57: bool, f58: bool, f59: bool, f60: bool, f61: bool, f62: bool, f63: bool, 
        };

        pub const High = packed struct(u32) {
            f64: bool, f65: bool, f66: bool, f67: bool, f68: bool, f69: bool, f70: bool, f71: bool,
            f72: bool, f73: bool, f74: bool, f75: bool, f76: bool, f77: bool, f78: bool, f79: bool,
            f80: bool, f81: bool, f82: bool, f83: bool, f84: bool, f85: bool, f86: bool, f87: bool,
            f88: bool, f89: bool, f90: bool, f91: bool, f92: bool, f93: bool, f94: bool, f95: bool,
        };
        // zig fmt: on

        low: Low,
        mid: Mid,
        high: High,

        pub fn fromSet(set: std.EnumSet(FloatingRegister)) FloatingConstantMask {
            var mask: FloatingConstantMask = undefined;

            for (std.enums.values(FloatingRegister)) |f| {
                std.mem.writePackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(f), @intFromBool(set.contains(f)), .little);
            }

            return mask;
        }

        pub fn toSet(mask: FloatingConstantMask) std.EnumSet(FloatingRegister) {
            var set: std.EnumSet(FloatingRegister) = undefined;

            for (std.enums.values(FloatingRegister)) |f| {
                set.setPresent(f, std.mem.readPackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(f), .little) != 0);
            }

            return set;
        }
    };

    pub const OutputMask = packed struct(u32) {
        // zig fmt: off
        o0: bool, o1: bool, o2: bool, o3: bool, o4: bool, o5: bool, o6: bool, o7: bool,
        o8: bool, o9: bool, o10: bool, o11: bool, o12: bool, o13: bool, o14: bool, o15: bool,
        _: u16 = 0,
        // zig fmt: on

        pub fn fromSet(set: std.EnumSet(OutputRegister)) OutputMask {
            var mask: OutputMask = undefined;

            for (std.enums.values(OutputRegister)) |o| {
                std.mem.writePackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(o), @intFromBool(set.contains(o)), .little);
            }

            return mask;
        }

        pub fn toSet(mask: OutputMask) std.EnumSet(OutputRegister) {
            var set: std.EnumSet(OutputRegister) = undefined;

            for (std.enums.values(OutputRegister)) |o| {
                set.setPresent(o, std.mem.readPackedInt(u1, std.mem.asBytes(&mask), @intFromEnum(o), .little) != 0);
            }

            return set;
        }
    };

    name_string_offset: u32,
    code_offset: u16,
    info: ShaderInfo,

    // NOTE: Constants are sorted, that is, e.g: f0 = true, f1 = false, f2 = true then in memory there will be two floating constant entries that correspond to f0 and f2. Same for integers and same for outputs.
    boolean_constant_mask: BooleanConstantMask,
    integer_constant_mask: IntegerConstantMask,
    floating_constant_mask: FloatingConstantMask,
    output_mask: OutputMask,
};

pub const Parsed = struct {
    instructions: []const shader.encoding.Instruction,
    operand_descriptors: []const shader.encoding.OperandDescriptor,
    string_table: []const u8,
    entrypoint_data: []const u8,
    entrypoints: u16,

    pub fn initBuffer(buffer: []const u8) Parsed {
        var hdr = std.mem.bytesAsValue(Header, buffer).*;

        if (builtin.cpu.arch.endian() != .little) {
            std.mem.byteSwapAllFields(Header, &hdr);
        }

        const byte_code_size = @sizeOf(shader.encoding.Instruction) * hdr.shader_size.codeSize();
        const byte_operands_size = @sizeOf(shader.encoding.OperandDescriptor) * hdr.shader_size.operandsSize();

        return .{
            .instructions = @alignCast(std.mem.bytesAsSlice(pica.shader.encoding.Instruction, buffer[@sizeOf(Header)..][0..byte_code_size])),
            .operand_descriptors = @alignCast(std.mem.bytesAsSlice(pica.shader.encoding.OperandDescriptor, buffer[(@sizeOf(Header) + byte_code_size)..][0..byte_operands_size])),
            .string_table = buffer[(@sizeOf(Header) + byte_code_size + byte_operands_size)..][0..hdr.string_table_size],
            .entrypoint_data = buffer[(@sizeOf(Header) + byte_code_size + byte_operands_size + hdr.string_table_size)..],
            .entrypoints = hdr.entrypoints,
        };
    }

    pub fn entrypointIterator(parsed: *const Parsed) EntrypointIterator {
        return .{
            .parsed = parsed,
            .byte_offset = 0,
            .current_entry = 0,
        };
    }

    pub const EntrypointIterator = struct {
        pub const Entry = struct {
            info: EntrypointHeader.ShaderInfo,
            offset: u16,

            name: [:0]const u8,
            boolean_constant_set: std.enums.EnumSet(BooleanRegister),
            integer_constant_set: std.enums.EnumSet(IntegerRegister),
            floating_constant_set: std.enums.EnumSet(FloatingRegister),
            output_set: std.enums.EnumSet(OutputRegister),

            integer_constants: []const [4]i8,
            floating_constants: []const pica.F7_16x4,
            output_map: []const pica.OutputMap,
        };

        parsed: *const Parsed,
        byte_offset: u32,
        current_entry: u16,

        pub fn next(it: *EntrypointIterator) ?Entry {
            if (it.current_entry == it.parsed.entrypoints) return null;

            const entry_start = it.parsed.entrypoint_data[it.byte_offset..];
            const hdr = if (builtin.cpu.arch.endian() != .little) hdr: {
                const hdr_ptr: *const EntrypointHeader = @alignCast(std.mem.bytesAsValue(EntrypointHeader, entry_start));
                var hdr = hdr_ptr.*;
                std.mem.byteSwapAllFields(EntrypointHeader, &hdr);
                break :hdr hdr;
            } else std.mem.bytesAsValue(EntrypointHeader, entry_start).*;

            // TODO: byte-swap these bit-sets if not big endian like above ^
            const integer_constant_set: std.EnumSet(IntegerRegister) = hdr.integer_constant_mask.toSet();
            const floating_constant_set: std.EnumSet(FloatingRegister) = hdr.floating_constant_mask.toSet();
            const output_map_set: std.EnumSet(OutputRegister) = hdr.output_mask.toSet();

            const integer_constants_byte_size = integer_constant_set.count() * @sizeOf([4]i8);
            const floating_constants_byte_size = floating_constant_set.count() * @sizeOf(pica.F7_16x4);
            const output_map_byte_size = output_map_set.count() * @sizeOf(pica.OutputMap);

            defer {
                it.current_entry += 1;
                it.byte_offset += @as(u32, @sizeOf(EntrypointHeader)) + integer_constants_byte_size + floating_constants_byte_size + output_map_byte_size;
            }

            return .{
                .info = hdr.info,
                .offset = hdr.code_offset,

                .name = std.mem.span(@as([*:0]const u8, @ptrCast(it.parsed.string_table[hdr.name_string_offset..].ptr))),
                .boolean_constant_set = hdr.boolean_constant_mask.toSet(),
                .integer_constant_set = integer_constant_set,
                .floating_constant_set = floating_constant_set,
                .output_set = output_map_set,

                .integer_constants = @alignCast(std.mem.bytesAsSlice([4]i8, entry_start[@sizeOf(EntrypointHeader)..][0..integer_constants_byte_size])),
                .floating_constants = @alignCast(std.mem.bytesAsSlice(pica.F7_16x4, entry_start[(@sizeOf(EntrypointHeader) + integer_constants_byte_size)..][0..floating_constants_byte_size])),
                .output_map = @alignCast(std.mem.bytesAsSlice(pica.OutputMap, entry_start[(@sizeOf(EntrypointHeader) + integer_constants_byte_size + floating_constants_byte_size)..][0..output_map_byte_size])),
            };
        }
    };
};

comptime {
    std.debug.assert(std.mem.isAligned(@sizeOf(Header), @sizeOf(u32)));
    std.debug.assert(std.mem.isAligned(@sizeOf(EntrypointHeader), @sizeOf(u32)));
}

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.hardware.pica;
const shader = pica.shader;

const BooleanRegister = shader.register.Integral.Boolean;
const IntegerRegister = shader.register.Integral.Integer;
const FloatingRegister = shader.register.Source.Constant;
const OutputRegister = shader.register.Destination.Output;
