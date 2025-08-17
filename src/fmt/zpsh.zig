//! Zitrus PICA200 shader
//!
//! A simple shader format which omits the need for positional reads and has an overall simpler structure.
//! It omits numerous things that are not used or cannot be used by zitrus.
//!

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
    };

    pub const OutputIntegerInfo = packed struct(u8) {
        integer_constants: u3,
        outputs: u5,
    };

    pub const IntegerConstantEntry = extern struct {
        pub const Info = packed struct(u32) {
            register: shader.register.Integral.Integer,
            _: u30 = 0,
            
            pub fn init(reg: shader.register.Integral.Integer) Info {
                return .{ .register = reg };
            }
        }; 

        info: Info,
        value: pica.I8x4,
    };

    pub const FloatingConstantEntry = extern struct {
        pub const Info = packed struct(u32) {
            register: shader.register.Source.Constant,
            _: u25 = 0,
            
            pub fn init(reg: shader.register.Source.Constant) Info {
                return .{ .register = reg };
            }
        };

        info: Info,
        value: pica.F7_16x4,
    };

    pub const OutputEntry = packed struct(u32) {
        reg: shader.register.Destination.Output,
        x: pica.OutputMap.Semantic,
        y: pica.OutputMap.Semantic,
        z: pica.OutputMap.Semantic,
        w: pica.OutputMap.Semantic,
        _: u8 = 0,
    };

    name_string_offset: u32,
    code_offset: u16,
    info: ShaderInfo,
    boolean_constant_mask: BooleanConstantMask,
    floating_constants: u8,
    output_integer_info: OutputIntegerInfo,
};

pub const Parsed = struct {
    instructions: []align(1) const shader.encoding.Instruction,
    operand_descriptors: []align(1) const shader.encoding.OperandDescriptor,
    string_table: []const u8,
    entrypoint_data: []const u8,
    entrypoints: u16,

    pub fn initBuffer(buffer: []const u8) Parsed {
        var hdr = std.mem.bytesAsValue(Header, buffer).*;

        if(builtin.cpu.arch.endian() != .little) {
            std.mem.byteSwapAllFields(Header, &hdr);
        }

        const byte_code_size = @sizeOf(shader.encoding.Instruction) * hdr.shader_size.codeSize();
        const byte_operands_size = @sizeOf(shader.encoding.OperandDescriptor) * hdr.shader_size.operandsSize();

        return .{
            .instructions = std.mem.bytesAsSlice(pica.shader.encoding.Instruction, buffer[@sizeOf(Header)..][0..byte_code_size]),
            .operand_descriptors = std.mem.bytesAsSlice(pica.shader.encoding.OperandDescriptor, buffer[(@sizeOf(Header) + byte_code_size)..][0..byte_operands_size]),
            .string_table = buffer[(@sizeOf(Header) + byte_code_size + byte_operands_size)..][0..hdr.string_table_size],
            .entrypoint_data = buffer[(@sizeOf(Header) + byte_code_size + byte_operands_size + hdr.string_table_size)..],
            .entrypoints = hdr.entrypoints,
        };
    }

    pub fn entrypointIterator(parsed: *const Parsed) EntrypointIterator {
        return .{
            .parsed = parsed,
            .byte_offset  = 0,
            .current_entry = 0,
        };
    }
    
    pub const EntrypointIterator = struct {
        pub const Entry = struct {
            info: EntrypointHeader.ShaderInfo,
            offset: u16,

            name: [:0]const u8,
            boolean_constants: EntrypointHeader.BooleanConstantMask,
            floating_constants: []align(1) const EntrypointHeader.FloatingConstantEntry, 
            integer_constants: []align(1) const EntrypointHeader.IntegerConstantEntry, 
            outputs: []align(1) const EntrypointHeader.OutputEntry,
        };

        parsed: *const Parsed,
        byte_offset: u32,
        current_entry: u16,

        pub fn next(it: *EntrypointIterator) ?Entry {
            if(it.current_entry == it.parsed.entrypoints) return null;
            
            const entry_start = it.parsed.entrypoint_data[it.byte_offset..];
            var hdr = std.mem.bytesAsValue(EntrypointHeader, entry_start).*;

            if(builtin.cpu.arch.endian() != .little) {
                std.mem.byteSwapAllFields(EntrypointHeader, &hdr);
            }

            const byte_floating_size = @as(u32, @sizeOf(EntrypointHeader.FloatingConstantEntry)) * hdr.floating_constants;
            const byte_int_size = @as(u32, @sizeOf(EntrypointHeader.IntegerConstantEntry)) * hdr.output_integer_info.integer_constants;
            const byte_output_size = @as(u32, @sizeOf(EntrypointHeader.OutputEntry)) * hdr.output_integer_info.outputs;

            const value: Entry = .{
                .info = hdr.info,
                .offset = hdr.code_offset,

                .name = std.mem.span(@as([*:0]const u8, @ptrCast(it.parsed.string_table[hdr.name_string_offset..].ptr))),
                .boolean_constants = hdr.boolean_constant_mask,
                .floating_constants = std.mem.bytesAsSlice(EntrypointHeader.FloatingConstantEntry, entry_start[@sizeOf(EntrypointHeader)..][0..byte_floating_size]),
                .integer_constants = std.mem.bytesAsSlice(EntrypointHeader.IntegerConstantEntry, entry_start[(@sizeOf(EntrypointHeader) + byte_floating_size)..][0..byte_int_size]),
                .outputs = std.mem.bytesAsSlice(EntrypointHeader.OutputEntry, entry_start[(@sizeOf(EntrypointHeader) + byte_floating_size + byte_int_size)..][0..byte_output_size]),
            };

            it.current_entry += 1;
            it.byte_offset += @as(u32, @sizeOf(EntrypointHeader)) + byte_floating_size + byte_int_size + byte_output_size;
            return value;
        }
    };
};

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.pica;
const shader = pica.shader;
