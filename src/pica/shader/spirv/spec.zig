pub const magic_value: u32 = 0x07230203;

pub const Version = packed struct(u32) {
    _unused0: u8,
    minor: u8,
    major: u8,
    _unused1: u8,
};

pub fn detectEndianness(magic: [4]u8) ?std.builtin.Endian {
    const magic_word: u32 = @bitCast(magic);

    return switch (magic_word) {
        magic_value => builtin.cpu.arch.endian(),
        @byteSwap(magic_value) => switch(builtin.cpu.arch.endian()) {
            .little => .big,
            .big => .little,
        },
        else => null,
    };
}

pub const Capability = enum(u32) {
    matrix,
    shader,
    geometry,
    _,

    pub fn isSupported(capability: Capability) bool {
        return switch (capability) {
            .matrix,
            .shader,
            .geometry,
            => true,
            _ => false,
        };
    }
};

pub const AddressingModel = enum(u32) {
    logical = 0,
    _,

    pub fn isSupported(model: AddressingModel) bool {
        return switch (model) {
            .logical => true,
            _ => false,
        };
    }
};

pub const MemoryModel = enum(u32) {
    simple,
    glsl450,
    opencl,
    vulkan,
    _,
};

pub const ExecutionMode = enum(u32) {
    vertex = 0,
    geometry = 3,
    _,

    pub fn isSupported(mode: ExecutionMode) bool {
        return switch (mode) {
            .vertex,
            .geometry,
            => true,
            _ => false,
        };
    }
};

pub const SourceLanguage = enum(u32) { _ };

pub const Builtin = enum(u32) {
    position = 0,
    _,

    pub fn isSupported(b: Builtin) bool {
        return switch (b) {
            .position => true,
            _ => false,
        };
    }
};

pub const Decoration = enum(u32) {
    block = 2,
    builtin = 11,
    constant = 22,
    location = 30,
    component = 31,
    _,

    pub fn isSupported(decoration: Decoration) bool {
        return switch (decoration) {
            .block,
            .builtin,
            .constant,
            .location,
            .component,
            => true,
            _ => false,
        };
    }

    pub const Extra = union {
        none: void,
        builtin: Builtin,
        location: u32,
    };
};

pub const StorageClass = enum(u32) {
    uniform_constant = 0,
    input = 1,
    output = 3,
    private = 6,
    function = 7,
    _,
};

pub const Id = enum(u32) { _ };

pub const Instruction = union(Prefix.Op) {
    pub const Prefix = packed struct(u32) {
        // NOTE: Not all SPIR-V instructions are handled!
        pub const Op = enum(u16) {
            nop = 0,
            undef = 1,
            source = 3,
            source_extension = 4,
            name = 5,
            member_name = 6,
            ext_inst_import = 11,
            memory_model = 14,
            entry_point = 15,
            capability = 17,
            type_void = 19,
            type_bool = 20,
            type_int = 21,
            type_float = 22,
            type_vector = 23,
            type_matrix = 24,
            type_array = 28,
            type_struct = 30,
            type_pointer = 32,
            type_function = 33,
            constant_true = 41,
            constant_false = 42,
            constant = 43,
            function = 54,
            function_parameter = 55,
            function_end = 56,
            variable = 59,
            load = 61,
            store = 62,
            access_chain = 65,
            decorate = 71,
            member_decorate = 72,
            composite_construct = 80,
            composite_extract = 81,
            label = 248,
            @"return" = 253,
            _,
        };

        op: Op,
        word_count: u16,
    };

    nop,
    undef: struct {
        type: Id,
        result: Id,
    },
    source,
    source_extension,
    name,
    member_name,
    ext_inst_import: struct {
        id: Id,
        name: []const u8,   
    },
    memory_model: struct {
        addressing: AddressingModel,
        memory: MemoryModel,
    },
    entry_point: struct {
        execution_mode: ExecutionMode,
        entry: Id,
        name: []const u8,
        interface: []const Id,
    },
    capability: Capability,
    type_void: Id,
    type_bool: Id,
    type_int: struct {
        target: Id,
        width: u32,
        signedness: std.builtin.Signedness,
    },
    type_float: struct {
        target: Id,
        width: u32,
    },
    type_vector: struct {
        target: Id,
        component: Id,
        count: u32,
    },
    type_matrix: struct {
        target: Id,
        column: Id,
        count: u32,
    },
    type_array: struct {
        target: Id,
        type: Id,
        length: u32,
    },
    type_struct,
    type_pointer: struct {
        target: Id,
        storage_class: StorageClass,
        type: Id,
    },
    type_function,
    constant_true: struct {
        type: Id,
        target: Id,
    },
    constant_false: struct {
        type: Id,
        target: Id,
    },
    constant: struct {
        type: Id,
        target: Id,
        value: u32,
    },
    function,
    function_parameter,
    function_end,
    variable,
    load,
    store,
    access_chain,
    decorate: struct {
        target: Id,
        decoration: Decoration,
        extra: Decoration.Extra,
    },
    member_decorate: struct {
        type: Id,
        member: u32,
        decoration: Decoration,
        extra: Decoration.Extra,
    },
    composite_construct,
    composite_extract,
    label,
    @"return",
};

pub const InstructionIterator = struct {
    reader: *std.Io.Reader,
    endian: std.builtin.Endian,

    pub fn init(reader: *std.Io.Reader, endian: std.builtin.Endian) InstructionIterator {
        return .{
            .reader = reader,
            .endian = endian,
        };
    }

    pub fn takeLiteral(it: *InstructionIterator, maybe_literal_word_count: ?u16, gpa: std.mem.Allocator) ![]const u8 {
        const reader = it.reader;
        const endian = it.endian;

        var builder: std.ArrayList(u8) = try .initCapacity(gpa, (maybe_literal_word_count orelse 1) * @sizeOf(u32)); 

        if(maybe_literal_word_count) |literal_word_count| {
            for (0..literal_word_count) |_| {
                const current = try reader.takeInt(u32, endian);

                inline for (0..@sizeOf(u32)) |i| {
                    builder.appendAssumeCapacity(@truncate(current >> (i * @bitSizeOf(u8))));
                }
            }
        } else {
            read: while (true) {
                const current = try reader.takeInt(u32, endian);

                inline for (0..@sizeOf(u32)) |i| {
                    const byte: u8 = @truncate(current >> (i * @bitSizeOf(u8)));

                    switch (byte) {
                        0 => break :read,
                        else => builder.appendAssumeCapacity(byte),
                    }
                }
            }
        }

        return try builder.toOwnedSlice(gpa);
    }

    pub fn takeDecorationExtra(it: *InstructionIterator, deco: Decoration) !Decoration.Extra {
        const reader = it.reader;
        const endian = it.endian;

        return switch (deco) {
            .location => .{ .location = try reader.takeInt(u32, endian) },
            .builtin => .{ .builtin = try reader.takeEnum(Builtin, endian) },
            else => .{ .none = {} },
        };
    }

    pub fn next(it: *InstructionIterator, gpa: std.mem.Allocator) !?Instruction {
        const reader = it.reader;
        const endian = it.endian;

        while(true) { 
            const prefix = reader.takeStruct(Instruction.Prefix, endian) catch |err| switch (err) {
                error.EndOfStream => return null,
                else => return err,
            };

            const op = prefix.op;

            switch (op) {
                .undef => return .{ .undef = .{
                    .type = try reader.takeEnum(Id, endian),
                    .result = try reader.takeEnum(Id, endian),
                }},
                .ext_inst_import => return .{ .ext_inst_import = .{
                    .id = try reader.takeEnum(Id, endian),
                    .name = try it.takeLiteral(prefix.word_count - 2, gpa),
                }},
                .memory_model => return .{ .memory_model = .{
                    .addressing = try reader.takeEnum(AddressingModel, endian),
                    .memory = try reader.takeEnum(MemoryModel, endian),
                }},
                .entry_point => {
                    const execution_mode = try reader.takeEnum(ExecutionMode, endian);
                    const entry = try reader.takeEnum(Id, endian);
                    const name = try it.takeLiteral(null, gpa); 

                    const aligned_name_len = std.mem.alignForward(usize, name.len + 1, @sizeOf(u32));
                    const interface = try reader.readSliceEndianAlloc(gpa, u32, prefix.word_count - (3 + @divExact(aligned_name_len, @sizeOf(u32))), endian);

                    return .{ .entry_point = .{
                        .execution_mode = execution_mode,
                        .entry = entry,
                        .name = name,
                        .interface = @ptrCast(interface),
                    }};
                },
                .capability => return .{ .capability = try reader.takeEnum(Capability, endian) },
                .decorate => {
                    const target= try reader.takeEnum(Id, endian);
                    const decoration = try reader.takeEnum(Decoration, endian);

                    if(!decoration.isSupported()) {
                        return error.UnsupportedDecoration;
                    }

                    return .{ .decorate = .{
                        .target = target,
                        .decoration = decoration,
                        .extra = try it.takeDecorationExtra(decoration),
                    }};
                },
                .member_decorate => {
                    const target = try reader.takeEnum(Id, endian);
                    const member = try reader.takeInt(u32, endian);
                    const decoration = try reader.takeEnum(Decoration, endian);

                    if(!decoration.isSupported()) {
                        return error.UnsupportedDecoration;
                    }

                    return .{ .member_decorate = .{
                        .type = target,
                        .member = member,
                        .decoration = decoration,
                        .extra = try it.takeDecorationExtra(decoration),
                    }};
                },
                _ => {
                    std.debug.print("unhandled op {}! skipping...\n", .{op});       
                    try reader.discardAll((prefix.word_count - 1) * @sizeOf(u32));
                },
                else => {
                    try reader.discardAll((prefix.word_count - 1) * @sizeOf(u32));
                }
            }
        }
    }
};

const builtin = @import("builtin");
const std = @import("std");
