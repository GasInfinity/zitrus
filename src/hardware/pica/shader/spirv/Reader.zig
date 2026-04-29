const spec = @import("spec.zig");

pub const Version = packed struct(u32) {
    _unused0: u8,
    minor: u8,
    major: u8,
    _unused1: u8,
};

pub fn detectEndianness(magic: [4]u8) ?std.builtin.Endian {
    const magic_word: u32 = @bitCast(magic);

    return switch (magic_word) {
        spec.magic_number => builtin.cpu.arch.endian(),
        @byteSwap(spec.magic_number) => switch (builtin.cpu.arch.endian()) {
            .little => .big,
            .big => .little,
        },
        else => null,
    };
}

pub const Instruction = struct {
    op: spec.instruction.Opcode,

    /// In SPIR-V endian
    slice: []u32,
};

pub const InitError = error{InvalidMagic};

parent: *std.Io.Reader,
endian: std.builtin.Endian,

version: Version,
generator: u32,
bound: u32,
schema: u32,

pub fn init(reader: *std.Io.Reader) !SpvReader {
    const magic = try reader.takeArray(4);
    const endianness = detectEndianness(magic.*) orelse return error.InvalidMagic;
    const version = try reader.takeStruct(Version, endianness);

    const generator = try reader.takeInt(u32, endianness);
    const bound = try reader.takeInt(u32, endianness);
    const schema = try reader.takeInt(u32, endianness);

    return .{
        .parent = reader,
        .endian = endianness,

        .version = version,
        .generator = generator,
        .bound = bound,
        .schema = schema,
    };
}

pub const Prefix = packed struct(u32) {
    opcode: spec.instruction.Opcode,
    word_count: u16,
};

pub fn peekPrefix(reader: SpvReader) !?Prefix {
    return reader.parent.peekStruct(Prefix, reader.endian) catch |err| switch (err) {
        error.EndOfStream => null,
        else => return err,
    };
}

/// Invalidates any previously taken or decoded instruction.
pub fn takeInstruction(reader: SpvReader) !?Instruction {
    const prefix = try reader.peekPrefix() orelse return null;
    if (prefix.word_count >= reader.parent.buffer.len) return error.InstructionTooLong;

    const instruction_bytes = try reader.parent.take(prefix.word_count * @as(usize, @sizeOf(u32)));
    const instruction_words: []u32 = @ptrCast(@alignCast(instruction_bytes));

    return .{
        .op = prefix.opcode,
        .slice = instruction_words[1..],
    };
}

pub fn skipInstruction(reader: SpvReader) !void {
    _ = try reader.takeInstruction();
}

pub fn decodeInstruction(reader: SpvReader, comptime T: type, instruction: Instruction) !T {
    std.debug.assert(@typeInfo(T) == .@"struct");
    var inst: T = undefined;

    var remaining = instruction.slice;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        const Operand = field.type;

        @field(inst, field.name), const words_taken = try reader.decodeOperand(Operand, remaining);
        remaining = remaining[words_taken..];
    }

    std.debug.assert(remaining.len == 0);
    return inst;
}

pub fn decodeOperand(reader: SpvReader, comptime T: type, slice: []u32) !struct { T, u16 } {
    return switch (@typeInfo(T)) {
        .void => .{ {}, 0 },
        .@"enum" => .{ reader.decodeEnum(T, slice), 1 },
        .pointer => |p| {
            if (p.is_const and p.child == u8) return reader.decodeString(slice);
            if (@sizeOf(p.child) != @sizeOf(u32)) @compileError("TODO?");
            const words, const taken = reader.decodeWordArray(slice);
            return .{ @ptrCast(words), taken };
        },
        .@"union" => |u| {
            std.debug.assert(u.tag_type != null);

            const value = reader.decodeEnum(u.tag_type.?, slice);

            switch (value) {
                _ => return error.UnknownOperand,
                inline else => |v| {
                    const name = @tagName(v);
                    const Case = @FieldType(T, name);

                    const case_value, const words_taken = try reader.decodeOperand(Case, slice[1..]);
                    return .{ @unionInit(T, name, case_value), 1 + words_taken };
                },
            }
        },
        else => @compileError("How do I deserialize the type? " ++ @typeName(T)),
    };
}

pub fn decodeWordArray(reader: SpvReader, slice: []u32) struct { []const u32, u16 } {
    if (reader.endian != std.builtin.Endian.native) std.mem.byteSwapAllElements(u32, slice);
    return .{ slice, @intCast(slice.len) };
}

pub fn decodeEnum(reader: SpvReader, comptime T: type, slice: []u32) T {
    return @enumFromInt(std.mem.readInt(@typeInfo(T).@"enum".tag_type, @ptrCast(&slice[0]), reader.endian));
}

pub fn decodeString(reader: SpvReader, slice: []u32) !struct { []const u8, u16 } {
    const bytes: []u8 = @ptrCast(slice);
    var i: usize = 0;

    while (i < slice.len) {
        slice[i] = switch (reader.endian) {
            .little => slice[i],
            .big => @byteSwap(slice[i]),
        };
        const word: [4]u8 = @bitCast(slice[i]);
        i += 1;

        for (&word, 0..) |c, s| if (c == 0) {
            return .{ bytes[0..(i * @sizeOf(u32) + s)], @intCast(i) };
        };
    }

    // Not null terminated?
    return error.InvalidOperand;
}

const SpvReader = @This();

const builtin = @import("builtin");
const std = @import("std");
