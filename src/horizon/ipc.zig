// https://www.3dbrew.org/wiki/IPC
// https://www.3dbrew.org/wiki/Services_API
// https://www.3dbrew.org/wiki/Services

pub const TranslationDescriptor = packed union {
    pub const Type = enum(u3) {
        handle,
        static_buffer,
        _,
    };

    pub const Handle = packed struct(u32) {
        pub const replace_by_proccess_id: Handle = .{ .replace_by_process_id = true };

        _reserved0: u1 = 0,
        type: Type = .handle,
        close_handles: bool = false,
        replace_by_process_id: bool = false,
        _reserved1: u20 = 0,
        extra_handles: u6 = 0,

        pub fn init(len: u6) Handle {
            std.debug.assert(len > 0);
            return .{ .extra_handles = (len - 1) };
        }

        pub fn initClose(len: u6) Handle {
            std.debug.assert(len > 0);
            return .{ .close_handles = true, .extra_handles = len - 1 };
        }
    };

    pub const StaticBuffer = packed struct(u32) {
        _reserved0: u1 = 0,
        type: Type = .static_buffer,
        _reserved1: u6 = 0,
        index: u4,
        size: u18,

        pub fn init(size: u18, buffer_id: u4) StaticBuffer {
            return .{
                .index = buffer_id,
                .size = size,
            };
        }
    };

    pub const BufferMapping = packed struct(u32) {
        _reserved0: u1 = 0,
        read: bool,
        write: bool,
        type: u1 = 1,
        size: u28,

        pub fn init(size: u28, read: bool, write: bool) BufferMapping {
            return .{
                .read = read,
                .write = write,
                .size = size,
            };
        }
    };

    handle: Handle,
    static_buffer: StaticBuffer,
    buffer_mapping: BufferMapping,
};

pub const ReplaceByProcessId = enum(u0) { replace };

pub fn MoveHandle(comptime T: type) type {
    return packed struct(u32) {
        const MovHandle = @This();
        pub const Handle = T;

        handle: Handle,

        pub fn init(handle: Handle) MovHandle {
            return .{ .handle = handle };
        }
    };
}

pub fn StaticSlice(comptime index: u4) type {
    return struct {
        const StSlice = @This();

        pub const static_buffer_index = index;

        slice: []const u8,

        pub fn init(slice: []const u8) StSlice {
            return .{ .slice = slice };
        }
    };
}

pub const MappingModifier = packed struct(u2) {
    pub const read: MappingModifier = .{ .read_only = true };
    pub const write: MappingModifier = .{ .write_only = true };
    pub const read_write: MappingModifier = .{ .read_only = true, .write_only = true };

    read_only: bool = false,
    write_only: bool = false,
};

pub fn MappedSlice(comptime mapping_modifier: MappingModifier) type {
    return struct {
        const Mapped = @This();
        pub const modifier = mapping_modifier;
        pub const Slice = if(modifier.write_only) []u8 else []const u8;

        slice: Slice,

        pub fn init(slice: Slice) Mapped {
            return .{ .slice = slice };
        }
    };
}

pub fn Command(comptime CommandId: type, comptime command_id: CommandId, comptime CommandRequest: type, comptime CommandResponse: type) type {
    std.debug.assert(@typeInfo(CommandRequest) == .@"struct");
    std.debug.assert(@typeInfo(CommandResponse) == .@"struct");

    return struct {
        pub const Id = CommandId;
        pub const id = command_id;

        pub const input_static_buffers = if (@hasDecl(CommandRequest, "static_buffers")) @field(CommandRequest, "static_buffers") else 0;
        pub const output_static_buffers = if (@hasDecl(CommandResponse, "static_buffers")) @field(CommandResponse, "static_buffers") else 0;

        pub const Request = CommandRequest;
        pub const Response = CommandResponse;

        pub const request = calculateParameters(CommandRequest);
        pub const response = response: {
            const params = calculateParameters(CommandResponse);

            // XXX: add the ResultCode of every response
            break :response Buffer.PackedCommand.Header.Parameters{ .normal = params.normal + 1, .translate = params.translate };
        };
    };
}

pub fn calculateParameters(comptime T: type) Buffer.PackedCommand.Header.Parameters {
    const t_info = @typeInfo(T).@"struct";

    if (t_info.layout != .auto) {
        return .{ .normal = (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32), .translate = 0 };
    }

    const fields = t_info.fields;

    comptime var normal = 0;
    comptime var translate = 0;

    inline for (fields) |f| ty: switch (f.type) {
        else => |typ| switch (@typeInfo(typ)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool, .int, .float => {
                if (translate != 0) {
                    @compileError("normal parameters cannot be added after adding translate parameters");
                }

                normal += (@sizeOf(typ) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
            },
            .@"enum" => |e| {
                if (typ == horizon.Object or typ == ReplaceByProcessId) {
                    translate += 2; // descriptor + handle
                    continue;
                }

                continue :ty e.tag_type;
            },
            .array => |a| arr: switch (a.child) {
                else => |at| switch (@typeInfo(at)) {
                    .undefined, .void, .noreturn, .@"opaque" => {},
                    .bool, .int, .float => {
                        if (translate != 0) {
                            @compileError("normal parameters cannot be added after adding translate parameters");
                        }

                        normal += (@sizeOf(typ) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
                    },
                    .@"enum" => |e| {
                        if (at == horizon.Object or at == ReplaceByProcessId) {
                            translate += 1 + a.len;
                            continue;
                        }

                        continue :arr e.tag_type;
                    },
                    .@"struct" => |s| {
                        if (s.layout == .@"packed" or s.layout == .@"extern") {
                            if (@hasDecl(at, "Handle") and @bitSizeOf(@field(at, "Handle")) == @bitSizeOf(u32) and at == MoveHandle(@field(at, "Handle"))) {
                                translate += 1 + a.len;
                                continue;
                            }

                            if (s.fields.len == 1) {
                                continue :arr s.fields[0].type;
                            }

                            continue :arr std.meta.Int(.unsigned, @bitSizeOf(at));
                        }

                        @compileError("cannot serialize struct with non-defined layout");
                    },
                    .@"union" => |u| {
                        if (u.layout != .@"packed" or u.layout != .@"extern") {
                            @compileError("cannot serialize union with non-defined layout");
                        }

                        continue :arr std.meta.Int(.unsigned, @bitSizeOf(at));
                    },
                    .@"fn" => @compileError("cannot serialize fn"),
                    .optional => @compileError("cannot serialize optional as it doesn't have a defined layout"),
                    .error_union, .error_set => @compileError("cannot serialize errors as they are obviously not supported"),
                    .array => @compileError("nested arrays are not supported"),
                    .pointer => @compileError("pointers/slices are not supported, please use mapped and static slice types"),
                    else => @compileError("cannot serialize " ++ @typeName(f.type) ++ " (in array)"),
                },
            },
            .@"struct" => |s| {
                // NOTE: looks like a hack, is there a better way to do this?

                // zig fmt: off
                if ((@hasDecl(typ, "static_buffer_index") and @TypeOf(@field(typ, "static_buffer_index")) == u4 and typ == StaticSlice(@field(typ, "static_buffer_index")))
                or (@hasDecl(typ, "modifier") and @TypeOf(@field(typ, "modifier")) == MappingModifier and typ == MappedSlice(@field(typ, "modifier")))
                or (@hasDecl(typ, "Handle") and @bitSizeOf(@field(typ, "Handle")) == @bitSizeOf(u32)) and typ == MoveHandle(@field(typ, "Handle"))) {
                // zig fmt: on

                    translate += 2;
                    continue;
                }

                if (s.layout == .@"packed" or s.layout == .@"extern") {
                    if (s.fields.len == 1) {
                        continue :ty s.fields[0].type;
                    }

                    continue :ty std.meta.Int(.unsigned, @bitSizeOf(typ));
                }

                @compileError("cannot serialize struct with non-defined layout");
            },
            .@"union" => |u| {
                if (u.layout != .@"packed" or u.layout != .@"extern") {
                    @compileError("cannot serialize union with non-defined layout");
                }

                continue :ty std.meta.Int(.unsigned, @bitSizeOf(typ));
            },
            .@"fn" => @compileError("cannot serialize fn"),
            .optional => @compileError("cannot serialize optional as it doesn't have a defined layout"),
            .error_union, .error_set => @compileError("cannot serialize errors as they are obviously not supported"),
            else => @compileError("cannot serialize " ++ @typeName(f.type)),
        },
    };

    return .{ .normal = normal, .translate = translate };
}

pub fn Response(comptime T: type, comptime static_buffers: usize) type {
    return struct {
        response: T,
        static_buffers: [static_buffers][]const u8,
    };
}

pub const Buffer = extern struct {
    pub const Target = enum {
        request,
        response,

        pub fn Type(target: Target, comptime DefinedCommand: type) type {
            return switch (target) {
                .request => DefinedCommand.Request,
                .response => DefinedCommand.Response,
            };
        }
    };

    pub const PackedCommand = extern struct {
        pub const Header = packed struct(u32) {
            parameters: Parameters,
            _unused: u4 = 0,
            command_id: u16,

            pub const Parameters = packed struct(u12) {
                translate: u6,
                normal: u6,
            };
        };

        header: Header,
        parameters: [63]u32,
    };

    packed_command: PackedCommand,
    static_buffers: [32]u32,

    pub fn sendRequest(buffer: *Buffer, session: ClientSession, comptime DefinedCommand: type, request: DefinedCommand.Request, static_buffers: [DefinedCommand.input_static_buffers][]u8) !Result(Response(DefinedCommand.Response, DefinedCommand.output_static_buffers)) {
        buffer.packRequest(DefinedCommand, request, static_buffers);
        try session.sendRequest();
        return buffer.unpackResponse(DefinedCommand);
    }

    pub fn packRequest(buffer: *Buffer, comptime DefinedCommand: type, request: DefinedCommand.Request, static_buffers: [DefinedCommand.input_static_buffers][]u8) void {
        return buffer.pack(DefinedCommand, .request, request, static_buffers);
    }

    pub fn unpackResponse(buffer: *Buffer, comptime DefinedCommand: type) Result(Response(DefinedCommand.Response, DefinedCommand.output_static_buffers)) {
        return buffer.unpack(DefinedCommand, .response);
    }

    fn pack(buffer: *Buffer, comptime DefinedCommand: type, comptime target: Target, value: target.Type(DefinedCommand), static_buffers: [DefinedCommand.input_static_buffers][]u8) void {
        std.debug.assert(@typeInfo(DefinedCommand) == .@"struct");

        const T: type, const params: PackedCommand.Header.Parameters = switch (target) {
            .request => .{ DefinedCommand.Request, DefinedCommand.request },
            .response => .{ DefinedCommand.Response, DefinedCommand.response },
        };

        buffer.packed_command.header = .{
            .parameters = params,
            .command_id = @intFromEnum(DefinedCommand.id),
        };

        var current_parameter: u6 = 0;

        const t_info = @typeInfo(T).@"struct";

        if (t_info.layout == .auto) {
            const fields = @typeInfo(T).@"struct".fields;

            inline for (fields) |f| {
                packType(buffer, &current_parameter, f.type, @field(value, f.name));
            }
        } else {
            packType(buffer, &current_parameter, T, value);
        }

        inline for (0..DefinedCommand.input_static_buffers) |i| {
            buffer.static_buffers[i * 2] = @bitCast(TranslationDescriptor.StaticBuffer{
                .index = i,
                .size = @intCast(static_buffers[i].len),
            });
            buffer.static_buffers[i * 2 + 1] = @intFromPtr(static_buffers[i].ptr);
        }
    }

    fn packType(buffer: *Buffer, current_parameter: *u6, comptime T: type, value: T) void {
        const parameters: []u32 = &buffer.packed_command.parameters;

        // NOTE: We don't need to do any checking as calculateParameters has already done some
        // XXX: This is recursive as we cannot use switch loops with runtime flow at comptime :(
        return switch (@typeInfo(T)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool => {
                parameters[current_parameter.*] = @intFromBool(value);
                current_parameter.* += 1;
            },
            .int, .float => {
                if (@bitSizeOf(T) < @bitSizeOf(u32)) {
                    parameters[current_parameter.*] = value;
                    current_parameter.* += 1;
                    return;
                }

                const parameters_size = (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
                std.mem.sliceAsBytes(parameters[current_parameter.*..])[0..@sizeOf(T)].* = std.mem.asBytes(&value)[0..@sizeOf(T)].*;
                current_parameter.* += parameters_size;
            },
            .@"enum" => |e| {
                if (T == horizon.Object or T == ReplaceByProcessId) {
                    parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                        .replace_by_process_id = (T == ReplaceByProcessId),
                    });
                    parameters[current_parameter.* + 1] = @intFromEnum(value);

                    current_parameter.* += 2;
                    return;
                }

                return packType(buffer, current_parameter, e.tag_type, @intFromEnum(value));
            },
            .array => |a| switch (a.child) {
                else => |at| switch (@typeInfo(at)) {
                    .undefined, .void, .noreturn, .@"opaque" => {},
                    .@"struct" => |s| {
                        if (s.fields.len == 1) {
                            if (@hasDecl(T, "Handle") and @bitSizeOf(@field(T, "Handle")) == @bitSizeOf(u32) and T == MoveHandle(@field(T, "Handle"))) {
                                parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                                    .extra_handles = (a.len - 1),
                                    .close_handles = true,
                                });
                                current_parameter.* += 1;

                                inline for (0..a.len) |i| {
                                    parameters[current_parameter.*] = @bitCast(value[i]);
                                    current_parameter.* += 1;
                                }
                            }

                            return packType(buffer, current_parameter, [a.len]s.fields[0].type, @bitCast(value));
                        }

                        return packType(buffer, current_parameter, [a.len]std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value));
                    },
                    .@"union", .bool, .int, .float => {
                        const total_byte_size = a.len * @sizeOf(at);
                        const param_size = ((a.len * @sizeOf(at)) + (@sizeOf(u32) - 1)) / 4;

                        std.mem.sliceAsBytes(parameters[current_parameter.*..])[0..total_byte_size].* = @bitCast(value);
                        current_parameter.* += param_size;
                    },
                    .@"enum" => |e| {
                        if (at == horizon.Object or at == ReplaceByProcessId) {
                            parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                                .extra_handles = (a.len - 1),
                                .replace_by_process_id = (at == ReplaceByProcessId),
                            });

                            current_parameter.* += 1;

                            inline for (0..a.len) |i| {
                                parameters[current_parameter] = @intFromEnum(value[i]);
                                current_parameter.* += 1;
                            }

                            return;
                        }

                        return packType(buffer, current_parameter, [a.len]e.tag_type, @bitCast(value));
                    },
                    else => unreachable,
                },
            },
            .@"union" => packType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value)),
            .@"struct" => |s| {
                if (s.layout == .@"packed" or s.layout == .@"extern") {
                    if (@hasDecl(T, "Handle") and @bitSizeOf(@field(T, "Handle")) == @bitSizeOf(u32) and T == MoveHandle(@field(T, "Handle"))) {
                        parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                            .extra_handles = 0,
                            .close_handles = true,
                        });
                        parameters[current_parameter.* + 1] = @bitCast(value);
                        current_parameter.* += 2;
                    }

                    if (s.fields.len == 1) {
                        return packType(buffer, current_parameter, s.fields[0].type, @field(value, s.fields[0].name));
                    }

                    return packType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value));
                }

                const slice = value.slice;

                parameters[current_parameter.*] = if (@hasDecl(T, "static_buffer_index")) sb: {
                    break :sb @bitCast(TranslationDescriptor.StaticBuffer{
                        .index = @field(T, "static_buffer_index"),
                        .size = @intCast(slice.len),
                    });
                } else @bitCast(TranslationDescriptor.BufferMapping{
                    .read = T.modifier.read_only,
                    .write = T.modifier.write_only,
                    .size = @intCast(slice.len),
                });
                parameters[current_parameter.* + 1] = @intFromPtr(slice.ptr);
                current_parameter.* += 2;
            },
            else => unreachable,
        };
    }

    fn unpack(buffer: *Buffer, comptime DefinedCommand: type, comptime target: Target) (if (target == .request) DefinedCommand.Request else Result(Response(target.Type(DefinedCommand), DefinedCommand.output_static_buffers))) {
        const T: type, const params: PackedCommand.Header.Parameters = switch (target) {
            .request => .{ DefinedCommand.Request, DefinedCommand.request },
            .response => .{ DefinedCommand.Response, DefinedCommand.response },
        };

        const result: ResultCode = if (target == .request) .success else @bitCast(buffer.packed_command.parameters[0]);

        if (!result.isSuccess()) {
            return .{ .failure = result };
        }

        std.debug.assert(buffer.packed_command.header == PackedCommand.Header{
            .parameters = params,
            .command_id = @intFromEnum(DefinedCommand.id),
        });

        var current_parameter: u6 = 1;

        const t_info = @typeInfo(T).@"struct";

        const out: T = if (t_info.layout == .auto) auto: {
            const fields = @typeInfo(T).@"struct".fields;

            var out: T = undefined;

            inline for (fields) |f| {
                @field(out, f.name) = unpackType(buffer, &current_parameter, f.type);
            }

            break :auto out;
        } else unpackType(buffer, &current_parameter, T);

        var static_buffers: [DefinedCommand.output_static_buffers][]const u8 = undefined;
        inline for (0..DefinedCommand.output_static_buffers) |i| {
            const translation_descriptor: TranslationDescriptor.StaticBuffer = @bitCast(buffer.static_buffers[i * 2]);
            std.debug.assert(translation_descriptor.type == .static_buffer);

            const ptr: [*]u8 = @ptrFromInt(buffer.static_buffers[i * 2 + 1]);

            static_buffers[i] = ptr[0..translation_descriptor.size];
        }

        return switch (target) {
            .request => out,
            .response => .{ .success = .{ .code = result, .value = .{ .response = out, .static_buffers = static_buffers } } },
        };
    }

    fn unpackType(buffer: *Buffer, current_parameter: *u6, comptime T: type) T {
        const parameters: []u32 = &buffer.packed_command.parameters;

        return switch (@typeInfo(T)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool => b: {
                defer current_parameter.* += 1;
                break :b parameters[current_parameter.*] != 0;
            },
            .int, .float => fi: {
                if (@bitSizeOf(T) < @bitSizeOf(u32)) {
                    defer current_parameter.* += 1;
                    break :fi @truncate(parameters[current_parameter.*]);
                }

                defer current_parameter.* += (@sizeOf(T) + (@sizeOf(u32) - 1)) / 4;
                break :fi std.mem.bytesAsValue(T, std.mem.sliceAsBytes(parameters[current_parameter.*..])).*;
            },
            .@"enum" => |e| en: {
                if (T == horizon.Object or T == ReplaceByProcessId) {
                    defer current_parameter.* += 2;

                    const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);

                    std.debug.assert(handle_translation_descriptor.type == .handle);
                    std.debug.assert(handle_translation_descriptor.extra_handles == 0);
                    std.debug.assert(handle_translation_descriptor.replace_by_process_id == (T == ReplaceByProcessId));
                    // std.debug.assert(handle_translation_descriptor.close_handles == false);

                    break :en @enumFromInt(parameters[current_parameter.* + 1]);
                }

                break :en @enumFromInt(unpackType(buffer, current_parameter, e.tag_type));
            },
            .array => |a| switch (a.child) {
                else => |at| switch (@typeInfo(at)) {
                    .undefined, .void, .noreturn, .@"opaque" => {},
                    .@"struct" => |s| st: {
                        if (@hasDecl(at, "Handle") and @bitSizeOf(@field(at, "Handle")) == @bitSizeOf(u32) and at == MoveHandle(@field(at, "Handle"))) {
                            const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                            current_parameter.* += 1;

                            std.debug.assert(handle_translation_descriptor.type == .handle);
                            std.debug.assert(handle_translation_descriptor.extra_handles == (a.len - 1));
                            std.debug.assert(handle_translation_descriptor.replace_by_process_id == false);
                            // std.debug.assert(handle_translation_descriptor.close_handles == true);

                            defer current_parameter.* += a.len;
                            break :st @bitCast(unpackType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T))));
                        }

                        if (s.fields.len == 1) {
                            break :st @bitCast(unpackType(buffer, current_parameter, [a.len]s.fields[0].type));
                        }

                        break :st @bitCast(unpackType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T))));
                    },
                    .@"union", .bool, .int, .float => g: {
                        const total_byte_size = a.len * @sizeOf(at);
                        const param_size = ((a.len * @sizeOf(at)) + (@sizeOf(u32) - 1)) / 4;

                        defer current_parameter.* += param_size;
                        break :g @bitCast(std.mem.sliceAsBytes(parameters[current_parameter.*..])[0..total_byte_size].*);
                    },
                    .@"enum" => |e| e: {
                        if (at == horizon.Object or at == ReplaceByProcessId) {
                            const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                            current_parameter.* += 1;

                            std.debug.assert(handle_translation_descriptor.type == .handle);
                            std.debug.assert(handle_translation_descriptor.extra_handles == (a.len - 1));
                            std.debug.assert(handle_translation_descriptor.replace_by_process_id == (T == ReplaceByProcessId));
                            // std.debug.assert(handle_translation_descriptor.close_handles == false);

                            defer current_parameter.* += a.len;
                            break :e @bitCast(parameters[current_parameter.*..][0..a.len].*);
                        }

                        break :e @bitCast(unpackType(buffer, current_parameter, [a.len]e.tag_type));
                    },
                    else => unreachable,
                },
            },
            .@"union" => @bitCast(unpackType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T)))),
            .@"struct" => |s| s: {
                if (@hasDecl(T, "Handle") and @bitSizeOf(@field(T, "Handle")) == @bitSizeOf(u32) and T == MoveHandle(@field(T, "Handle"))) {
                    const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                    current_parameter.* += 1;

                    std.debug.assert(handle_translation_descriptor.type == .handle);
                    std.debug.assert(handle_translation_descriptor.extra_handles == 0);
                    std.debug.assert(handle_translation_descriptor.replace_by_process_id == false);
                    // FIXME: remove when azahar fixes apt GlanceParameter
                    // std.debug.assert(handle_translation_descriptor.close_handles == true);

                    defer current_parameter.* += 1;
                    break :s @bitCast(parameters[current_parameter.*]);
                }

                if (s.layout == .@"packed" or s.layout == .@"extern") {
                    if (s.fields.len == 1) {
                        const out = unpackType(buffer, current_parameter, s.fields[0].type);

                        break :s @bitCast(if (@typeInfo(s.fields[0].type) == .@"enum") @intFromEnum(out) else out);
                    }

                    break :s @bitCast(unpackType(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T))));
                }

                const translation_descriptor: TranslationDescriptor = @bitCast(parameters[current_parameter.*]);
                const ptr: [*]u8 = @ptrFromInt(parameters[current_parameter.* + 1]);
                current_parameter.* += 2;

                if (@hasDecl(T, "static_buffer_index")) {
                    std.debug.assert(translation_descriptor.static_buffer.type == .static_buffer);
                    break :s .init(ptr[0..translation_descriptor.static_buffer.size]);
                } else {
                    std.debug.assert(translation_descriptor.buffer_mapping.type == 1);
                    break :s .init(ptr[0..translation_descriptor.buffer_mapping.size]);
                }
            },
            else => unreachable,
        };
    }
};

const testing = std.testing;
comptime {
    // TODO: These should be tests
    testing.expectEqual(Buffer.PackedCommand.Header.Parameters{ .normal = 2, .translate = 2 }, calculateParameters(struct {
        first_param: u8,
        second_param: u32,
        test_handle: horizon.Synchronization,
    })) catch unreachable;
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ClientSession = horizon.ClientSession;
const ResultCode = horizon.ResultCode;
const Result = horizon.Result;
