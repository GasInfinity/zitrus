pub const Handle = enum(u32) {
    null = 0,
    _,
};

/// Deduplicated on shader creation.
pub const Code = struct {
    pub const Key = struct {
        hash: u32,

        instructions: []const pica.shader.encoding.Instruction,
        descriptors: []const pica.shader.encoding.OperandDescriptor,

        pub fn initCode(code: *Code) Key {
            return .{
                .hash = code.hash,
                .instructions = code.instructions,
                .descriptors = code.descriptors,
            };
        }

        pub fn initZpsh(parsed: zitrus.fmt.zpsh.Parsed) Key {
            return .{
                .hash = parsed.code_hash,
                .instructions = parsed.instructions,
                .descriptors = parsed.operand_descriptors,
            };
        }
    };

    ref: std.atomic.Value(u32),
    hash: u32,
    uid: u32,

    instructions: []const pica.shader.encoding.Instruction,
    descriptors: []const pica.shader.encoding.OperandDescriptor,

    pub fn init(uid: u32, hash: u32, instructions: []const pica.shader.encoding.Instruction, descriptors: []const pica.shader.encoding.OperandDescriptor) Code {
        return .{
            .ref = .init(1),
            .hash = hash,
            .uid = uid,
            .instructions = instructions,
            .descriptors = descriptors,
        };
    }
};

code: *Code,

entry: u16,
info: zpsh.EntrypointHeader.ShaderInfo,

boolean_constant_set: std.enums.EnumSet(BooleanRegister),
integer_constant_set: std.enums.EnumSet(IntegerRegister),
floating_constant_set: std.enums.EnumSet(FloatingRegister),
output_set: std.enums.EnumSet(OutputRegister),

integer_constants: []const [4]u8,
floating_constants: []const pica.F7_16x4,
output_map: []const pica.OutputMap,

pub fn init(gpa: std.mem.Allocator, code: *Code, entry: zpsh.Parsed.EntrypointIterator.Entry) !Shader {
    const all_data = try gpa.alloc(u32, entry.integer_constants.len + entry.output_map.len + entry.floating_constants.len * @divExact(@sizeOf(pica.F7_16x4), @sizeOf(u32)));
    errdefer comptime unreachable;

    const integer_constants: [][4]u8 = @ptrCast(all_data[0..entry.integer_constants.len]);
    const output_map: []pica.OutputMap = @ptrCast(all_data[entry.integer_constants.len..][0..entry.output_map.len]);
    const floating_constants: []pica.F7_16x4 = @ptrCast(all_data[entry.integer_constants.len + entry.output_map.len ..]);
    @memcpy(integer_constants, entry.integer_constants);
    @memcpy(output_map, entry.output_map);
    @memcpy(floating_constants, entry.floating_constants);

    return .{
        .code = code,
        .entry = entry.offset,
        .info = entry.info,
        .boolean_constant_set = entry.boolean_constant_set,
        .integer_constant_set = entry.integer_constant_set,
        .floating_constant_set = entry.floating_constant_set,
        .output_set = entry.output_set,

        .integer_constants = integer_constants,
        .floating_constants = floating_constants,
        .output_map = output_map,
    };
}

pub fn deinit(shader: *Shader, gpa: std.mem.Allocator) void {
    const data_start: [*]const u32 = @ptrCast(@alignCast(shader.integer_constants.ptr));
    const all_data = data_start[0..(shader.integer_constants.len + shader.output_map.len + (shader.floating_constants.len * @sizeOf(pica.F7_16x4)))];

    gpa.free(all_data);
    shader.* = undefined;
}

pub fn toHandle(shader: *Shader) Handle {
    return @enumFromInt(@intFromPtr(shader));
}

pub fn fromHandleMutable(handle: Handle) ?*Shader {
    return @as(?*Shader, @ptrFromInt(@intFromEnum(handle)));
}

const Shader = @This();

const std = @import("std");
const zitrus = @import("zitrus");

const zpsh = zitrus.fmt.zpsh;
const pica = zitrus.hardware.pica;

const BooleanRegister = pica.shader.register.Integral.Boolean;
const IntegerRegister = pica.shader.register.Integral.Integer;
const FloatingRegister = pica.shader.register.Source.Constant;
const OutputRegister = pica.shader.register.Destination.Output;
