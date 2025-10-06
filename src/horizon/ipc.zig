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
        pub const Handle = T;

        const MovHandle = @This();

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
        pub const modifier = mapping_modifier;
        pub const Slice = if (modifier.write_only) []u8 else []const u8;

        const Mapped = @This();

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

    inline for (fields) |f| {
        comptime calculateParametersType(f.type, &normal, &translate);
    }

    return .{ .normal = normal, .translate = translate };
}

fn isHandleOrProcessId(comptime T: type) bool {
    return T == horizon.Object or T == ReplaceByProcessId;
}

fn isMoveHandle(comptime T: type) bool {
    return @hasDecl(T, "Handle") and @bitSizeOf(@field(T, "Handle")) == @bitSizeOf(u32) and T == MoveHandle(@field(T, "Handle"));
}

fn isStaticSlice(comptime T: type) bool {
    return @hasDecl(T, "static_buffer_index") and @TypeOf(@field(T, "static_buffer_index")) == u4 and T == StaticSlice(@field(T, "static_buffer_index"));
}

fn isMappedSlice(comptime T: type) bool {
    return @hasDecl(T, "modifier") and @TypeOf(@field(T, "modifier")) == MappingModifier and T == MappedSlice(@field(T, "modifier"));
}

fn isWrappedHandle(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| s.fields.len == 1 and isWrappedHandle(s.fields[0].type),
        .@"enum" => T == horizon.Object,
        else => false,
    };
}

fn calculateParametersType(comptime T: type, comptime normal: *comptime_int, comptime translate: *comptime_int) void {
    switch (@typeInfo(T)) {
        .undefined, .void, .noreturn, .@"opaque" => {},
        .bool, .int, .float => if (translate.* == 0) {
            normal.* += (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
        } else @compileError("normal parameters cannot be added after adding translate parameters"),
        .@"enum" => |e| if (comptime isHandleOrProcessId(T)) {
            translate.* += 2;
        } else return calculateParametersType(e.tag_type, normal, translate),
        .array => |a| switch (@typeInfo(a.child)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool, .int, .float => if (translate.* == 0) {
                normal.* += (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
            } else @compileError("normal parameters cannot be added after adding translate parameters"),
            .@"enum" => |e| if (comptime isHandleOrProcessId(a.child)) {
                translate.* += 1 + a.len;
            } else return calculateParametersType([a.len]e.tag_type, normal, translate),
            .@"struct" => |s| if (comptime isWrappedHandle(a.child)) {
                translate.* += 1 + a.len;
            } else if (s.layout == .@"packed" or s.layout == .@"extern") {
                return calculateParametersType(std.meta.Int(.unsigned, @bitSizeOf(a.child)), normal, translate);
            } else @compileError("cannot serialize struct with non-defined layout"),
            .@"union" => |u| if (u.layout == .@"packed" or u.layout == .@"extern") {
                return calculateParametersType(std.meta.Int(.unsigned, @bitSizeOf(a.child)), normal, translate);
            } else @compileError("cannot serialize union with non-defined layout"),
            .@"fn" => @compileError("cannot serialize fn"),
            .optional => @compileError("cannot serialize optional as it doesn't have a defined layout"),
            .error_union, .error_set => @compileError("cannot serialize errors as they are obviously not supported"),
            .array => @compileError("nested arrays are not supported"),
            .pointer => @compileError("pointers/slices are not supported, please use mapped and static slice types"),
            else => @compileError("cannot serialize " ++ @typeName(a.child) ++ " (in array)"),
        },
        .@"struct" => |s| if (comptime (isWrappedHandle(T) or isStaticSlice(T) or isMappedSlice(T))) {
            translate.* += 2;
        } else if (s.layout == .@"packed" or s.layout == .@"extern") {
            return calculateParametersType(std.meta.Int(.unsigned, @bitSizeOf(T)), normal, translate);
        } else @compileError("cannot serialize struct with non-defined layout"),
        .@"union" => |u| if (u.layout == .@"packed" or u.layout == .@"extern") {
            return calculateParametersType(std.meta.Int(.unsigned, @bitSizeOf(T)), normal, translate);
        } else @compileError("cannot serialize union with non-defined layout"),
        .@"fn" => @compileError("cannot serialize fn"),
        .optional => @compileError("cannot serialize optional as it doesn't have a defined layout"),
        .error_union, .error_set => @compileError("cannot serialize errors as they are obviously not supported"),
        else => @compileError("cannot serialize " ++ @typeName(T)),
    }
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
        return buffer.packCommand(DefinedCommand, .request, request, static_buffers);
    }

    pub fn unpackResponse(buffer: *Buffer, comptime DefinedCommand: type) Result(Response(DefinedCommand.Response, DefinedCommand.output_static_buffers)) {
        return buffer.unpackCommand(DefinedCommand, .response);
    }

    fn packCommand(buffer: *Buffer, comptime DefinedCommand: type, comptime target: Target, value: target.Type(DefinedCommand), static_buffers: [DefinedCommand.input_static_buffers][]u8) void {
        std.debug.assert(@typeInfo(DefinedCommand) == .@"struct");

        const T: type, const params: PackedCommand.Header.Parameters = switch (target) {
            .request => .{ DefinedCommand.Request, DefinedCommand.request },
            .response => .{ DefinedCommand.Response, DefinedCommand.response },
        };

        buffer.packed_command.header = .{
            .parameters = params,
            .command_id = @intFromEnum(DefinedCommand.id),
        };

        buffer.packType(T, value);

        inline for (0..DefinedCommand.input_static_buffers) |i| {
            buffer.static_buffers[i * 2] = @bitCast(TranslationDescriptor.StaticBuffer{
                .index = i,
                .size = @intCast(static_buffers[i].len),
            });
            buffer.static_buffers[i * 2 + 1] = @intFromPtr(static_buffers[i].ptr);
        }
    }

    fn packType(buffer: *Buffer, comptime T: type, value: T) void {
        const t_info = @typeInfo(T).@"struct";

        var current_parameter: u6 = 0;

        if (t_info.layout == .auto) {
            const fields = @typeInfo(T).@"struct".fields;

            inline for (fields) |f| {
                packMember(buffer, &current_parameter, f.type, @field(value, f.name));
            }
        } else {
            packMember(buffer, &current_parameter, T, value);
        }
    }

    fn packMember(buffer: *Buffer, current_parameter: *u6, comptime T: type, value: T) void {
        const parameters: []u32 = &buffer.packed_command.parameters;

        // NOTE: We don't need to do any checking as calculateParameters has already done some
        return switch (@typeInfo(T)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool => {
                parameters[current_parameter.*] = @intFromBool(value);
                current_parameter.* += 1;
            },
            .int, .float => {
                const parameters_size = (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
                std.mem.sliceAsBytes(parameters[current_parameter.*..])[0..@sizeOf(T)].* = std.mem.asBytes(&value)[0..@sizeOf(T)].*;
                current_parameter.* += parameters_size;
            },
            .@"enum" => |e| {
                if (comptime isHandleOrProcessId(T)) {
                    parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{ .replace_by_process_id = (T == ReplaceByProcessId) });
                    parameters[current_parameter.* + 1] = @intFromEnum(value);
                    current_parameter.* += 2;
                    return;
                }

                return packMember(buffer, current_parameter, e.tag_type, @intFromEnum(value));
            },
            .array => |a| switch (a.child) {
                else => |AT| switch (@typeInfo(AT)) {
                    .undefined, .void, .noreturn, .@"opaque" => {},
                    .@"struct" => {
                        if (comptime isWrappedHandle(a.child)) {
                            parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                                .extra_handles = (a.len - 1),
                                .close_handles = isMoveHandle(a.child),
                            });
                            current_parameter.* += 1;

                            inline for (0..a.len) |i| {
                                parameters[current_parameter.*] = @bitCast(value[i]);
                                current_parameter.* += 1;
                            }
                        }

                        return packMember(buffer, current_parameter, [a.len]std.meta.Int(.unsigned, @bitSizeOf(AT)), @bitCast(value));
                    },
                    .@"union", .bool, .int, .float => {
                        const total_byte_size = a.len * @sizeOf(AT);
                        const param_size = ((a.len * @sizeOf(AT)) + (@sizeOf(u32) - 1)) / 4;

                        const remaining_bytes = std.mem.sliceAsBytes(parameters[current_parameter.*..]);

                        @memcpy(remaining_bytes[0..total_byte_size], @as([]const u8, @ptrCast(&value)));
                        current_parameter.* += param_size;
                    },
                    .@"enum" => |e| {
                        if (comptime isHandleOrProcessId(AT)) {
                            parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                                .extra_handles = (a.len - 1),
                                .replace_by_process_id = (AT == ReplaceByProcessId),
                            });

                            current_parameter.* += 1;

                            inline for (0..a.len) |i| {
                                parameters[current_parameter] = @intFromEnum(value[i]);
                                current_parameter.* += 1;
                            }

                            return;
                        }

                        return packMember(buffer, current_parameter, [a.len]e.tag_type, @bitCast(value));
                    },
                    else => unreachable,
                },
            },
            .@"union" => packMember(buffer, current_parameter, [@divExact(@bitSizeOf(T), @bitSizeOf(u8))]u8, @bitCast(value)),
            .@"struct" => |s| {
                if (comptime isWrappedHandle(T)) {
                    parameters[current_parameter.*] = @bitCast(TranslationDescriptor.Handle{
                        .extra_handles = 0,
                        .close_handles = isMoveHandle(T),
                    });
                    parameters[current_parameter.* + 1] = @bitCast(value);
                    current_parameter.* += 2;
                    return;
                }

                if (s.layout == .@"packed" or s.layout == .@"extern") {
                    return packMember(buffer, current_parameter, [@divExact(@bitSizeOf(T), @bitSizeOf(u8))]u8, @bitCast(value));
                }

                const slice = value.slice;

                parameters[current_parameter.*] = if (comptime isStaticSlice(T))
                    @bitCast(TranslationDescriptor.StaticBuffer{
                        .index = @field(T, "static_buffer_index"),
                        .size = @intCast(slice.len),
                    })
                else if (comptime isMappedSlice(T))
                    @bitCast(TranslationDescriptor.BufferMapping{
                        .read = T.modifier.read_only,
                        .write = T.modifier.write_only,
                        .size = @intCast(slice.len),
                    })
                else
                    comptime unreachable;

                parameters[current_parameter.* + 1] = @intFromPtr(slice.ptr);
                current_parameter.* += 2;
            },
            else => unreachable,
        };
    }

    fn unpackCommand(buffer: *Buffer, comptime DefinedCommand: type, comptime target: Target) (if (target == .request) DefinedCommand.Request else Result(Response(target.Type(DefinedCommand), DefinedCommand.output_static_buffers))) {
        const T: type, const params: PackedCommand.Header.Parameters = switch (target) {
            .request => .{ DefinedCommand.Request, DefinedCommand.request },
            .response => .{ DefinedCommand.Response, DefinedCommand.response },
        };

        const out: T, const result: ResultCode = switch (target) {
            .request => .{ buffer.unpackType(0, T), .success },
            .response => out: {
                const result: ResultCode = @bitCast(buffer.packed_command.parameters[0]);

                if (!result.isSuccess()) {
                    break :out .{ undefined, result };
                }

                expectReply(.{
                    .parameters = params,
                    .command_id = @intFromEnum(DefinedCommand.id),
                }, buffer.packed_command.header);

                break :out .{ buffer.unpackType(1, T), result };
            },
        };

        var static_buffers: [DefinedCommand.output_static_buffers][]const u8 = undefined;
        inline for (0..DefinedCommand.output_static_buffers) |i| {
            const translation_descriptor: TranslationDescriptor.StaticBuffer = @bitCast(buffer.static_buffers[i * 2]);
            std.debug.assert(translation_descriptor.type == .static_buffer);

            const ptr: [*]u8 = @ptrFromInt(buffer.static_buffers[i * 2 + 1]);

            static_buffers[i] = ptr[0..translation_descriptor.size];
        }

        return switch (target) {
            .request => out,
            .response => .of(result, .{ .response = out, .static_buffers = static_buffers }),
        };
    }

    fn unpackType(buffer: *Buffer, start: u6, comptime T: type) T {
        const t_info = @typeInfo(T).@"struct";

        var current_parameter: u6 = start;

        return if (t_info.layout == .auto) auto: {
            const fields = @typeInfo(T).@"struct".fields;

            var out: T = undefined;

            inline for (fields) |f| {
                @field(out, f.name) = unpackMember(buffer, &current_parameter, f.type);
            }

            break :auto out;
        } else unpackMember(buffer, &current_parameter, T);
    }

    fn unpackMember(buffer: *Buffer, current_parameter: *u6, comptime T: type) T {
        const parameters: []u32 = &buffer.packed_command.parameters;

        return switch (@typeInfo(T)) {
            .undefined, .void, .noreturn, .@"opaque" => {},
            .bool, .int, .float => fi: {
                defer current_parameter.* += (@sizeOf(T) + (@sizeOf(u32) - 1)) / @sizeOf(u32);
                break :fi std.mem.bytesAsValue(T, std.mem.sliceAsBytes(parameters[current_parameter.*..])).*;
            },
            .@"enum" => |e| en: {
                if (comptime isHandleOrProcessId(T)) {
                    defer current_parameter.* += 2;
                    const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);

                    expectHandle(.{
                        .type = .handle,
                        .extra_handles = 0,
                        .replace_by_process_id = (T == ReplaceByProcessId),
                        .close_handles = false,
                    }, handle_translation_descriptor);

                    break :en @enumFromInt(parameters[current_parameter.* + 1]);
                }

                break :en @enumFromInt(unpackMember(buffer, current_parameter, e.tag_type));
            },
            .array => |a| switch (a.child) {
                else => |AT| switch (@typeInfo(AT)) {
                    .undefined, .void, .noreturn, .@"opaque" => {},
                    .@"struct" => st: {
                        if (comptime isWrappedHandle(AT)) {
                            const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                            current_parameter.* += 1;

                            expectHandle(.{
                                .type = .handle,
                                .extra_handles = (a.len - 1),
                                .replace_by_process_id = false,
                                .close_handles = isMoveHandle(AT),
                            }, handle_translation_descriptor);

                            defer current_parameter.* += a.len;
                            break :st @bitCast(unpackMember(buffer, current_parameter, [@divExact(@bitSizeOf(T), @bitSizeOf(u8))]u8));
                        }

                        break :st @bitCast(unpackMember(buffer, current_parameter, [@divExact(@bitSizeOf(T), @bitSizeOf(u8))]u8));
                    },
                    .@"union", .bool, .int, .float => g: {
                        const total_byte_size = a.len * @sizeOf(AT);
                        const param_size = ((a.len * @sizeOf(AT)) + (@sizeOf(u32) - 1)) / 4;

                        defer current_parameter.* += param_size;
                        break :g @bitCast(std.mem.sliceAsBytes(parameters[current_parameter.*..])[0..total_byte_size].*);
                    },
                    .@"enum" => |e| e: {
                        if (comptime isHandleOrProcessId(AT)) {
                            const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                            current_parameter.* += 1;

                            expectHandle(.{
                                .type = .handle,
                                .extra_handles = (a.len - 1),
                                .replace_by_process_id = (AT == ReplaceByProcessId),
                                .close_handles = false,
                            }, handle_translation_descriptor);

                            defer current_parameter.* += a.len;
                            break :e @bitCast(parameters[current_parameter.*..][0..a.len].*);
                        }

                        break :e @bitCast(unpackMember(buffer, current_parameter, [a.len]e.tag_type));
                    },
                    else => unreachable,
                },
            },
            .@"union" => @bitCast(unpackMember(buffer, current_parameter, std.meta.Int(.unsigned, @bitSizeOf(T)))),
            .@"struct" => |s| s: {
                if (comptime isWrappedHandle(T)) {
                    const handle_translation_descriptor: TranslationDescriptor.Handle = @bitCast(parameters[current_parameter.*]);
                    current_parameter.* += 1;

                    expectHandle(.{
                        .type = .handle,
                        .extra_handles = 0,
                        .replace_by_process_id = false,
                        .close_handles = isMoveHandle(T),
                    }, handle_translation_descriptor);

                    defer current_parameter.* += 1;
                    break :s @bitCast(parameters[current_parameter.*]);
                }

                if (s.layout == .@"packed" or s.layout == .@"extern") {
                    break :s @bitCast(unpackMember(buffer, current_parameter, [@divExact(@bitSizeOf(T), @bitSizeOf(u8))]u8));
                }

                const translation_descriptor: TranslationDescriptor = @bitCast(parameters[current_parameter.*]);
                const ptr: [*]u8 = @ptrFromInt(parameters[current_parameter.* + 1]);
                current_parameter.* += 2;

                if (comptime isStaticSlice(T)) {
                    std.debug.assert(translation_descriptor.static_buffer.type == .static_buffer);
                    break :s .init(ptr[0..translation_descriptor.static_buffer.size]);
                } else if (comptime isMappedSlice(T)) {
                    std.debug.assert(translation_descriptor.buffer_mapping.type == 1);
                    break :s .init(ptr[0..translation_descriptor.buffer_mapping.size]);
                } else comptime unreachable;
            },
            else => unreachable,
        };
    }
};

pub fn expectReply(expected: Buffer.PackedCommand.Header, actual: Buffer.PackedCommand.Header) void {
    if (expected != actual) {
        horizon.debug.print("Unexpected reply, expecting {} and got {}", .{ expected, actual });
        std.debug.assert(false);
    }
}

pub fn expectHandle(expected: TranslationDescriptor.Handle, actual: TranslationDescriptor.Handle) void {
    if (expected != actual) {
        horizon.debug.print("Unexpected handle, expecting {} and got {}", .{ expected, actual });
        std.debug.assert(false);
    }
}

pub fn expectStaticBuffer(expected: TranslationDescriptor.StaticBuffer, actual: TranslationDescriptor.StaticBuffer) void {
    if (expected != actual) {
        horizon.debug.print("Unexpected static buffer, expecting {} and got {}", .{ expected, actual });
        std.debug.assert(false);
    }
}

pub fn expectMappedBuffer(expected: TranslationDescriptor.BufferMapping, actual: TranslationDescriptor.BufferMapping) void {
    if (expected != actual) {
        horizon.debug.print("Unexpected mapped buffer, expecting {} and got {}", .{ expected, actual });
        std.debug.assert(false);
    }
}

const testing = std.testing;

test calculateParameters {
    const Params = Buffer.PackedCommand.Header.Parameters;

    // NOTE: When a struct is not extern, each parameter will (at minimum) span 4-bytes as each field is independent.
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(struct { x: u8 }));
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(struct { x: u16 }));
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(struct { x: u32 }));

    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u32, y: u8 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u32, y: u16 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u32, y: u32 }));

    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u8, y: u32 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u16, y: u32 }));

    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u8, y: u8 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(struct { x: u16, y: u16 }));

    // NOTE: Otherwise, it is basically written as-is.
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(extern struct { x: u8, y: u8 }));
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(extern struct { x: u16, y: u16 }));
    try testing.expect(Params{ .normal = 1, .translate = 0 } == calculateParameters(extern struct { x: u8, y: u8, z: u8, w: u8 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(extern struct { x: u16, y: u16, z: u16 }));
    try testing.expect(Params{ .normal = 2, .translate = 0 } == calculateParameters(extern struct { x: u16, y: u16, z: u16, w: u16 }));
}

test "packType and unpackType are idempotent for extern or packed structs" {
    const TestStruct = extern struct {
        a: bool,
        b: u32,
        c: bool,
        d: u64,
        x: extern struct { r: u16, s: u16 },
        y: u16,
        z: [4]u8,
        w: [2]u16,
    };

    // bogus data, doesn't mean anything
    const test_value: TestStruct = .{
        .a = false,
        .b = 0xCAFEBABE,
        .c = true,
        .d = 0xFFAADDBBEE,
        .x = .{ .r = 42, .s = 69 },
        .y = 0xEEBB,
        .z = .{ 4, 3, 2, 1 },
        .w = .{ 64, 32 },
    };

    var buf: Buffer = undefined;

    buf.packType(TestStruct, test_value);
    const unpacked_value = buf.unpackType(0, TestStruct);

    try testing.expect(std.meta.eql(test_value, unpacked_value));
}

test "packType and unpackType are idempotent for auto structs" {
    const TestStruct = struct {
        a: bool,
        b: u32,
        c: bool,
        d: u64,
        x: extern struct { r: u16, s: u16 },
        y: u16,
        z: [4]u8,
        w: [2]u16,
    };

    // bogus data, doesn't mean anything
    const test_value: TestStruct = .{
        .a = false,
        .b = 0xCAFEBABE,
        .c = true,
        .d = 0xFFAADDBBEE,
        .x = .{ .r = 42, .s = 69 },
        .y = 0xEEBB,
        .z = .{ 4, 3, 2, 1 },
        .w = .{ 64, 32 },
    };

    var buf: Buffer = undefined;

    buf.packType(TestStruct, test_value);
    const unpacked_value = buf.unpackType(0, TestStruct);

    try testing.expect(std.meta.eql(test_value, unpacked_value));
}

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ClientSession = horizon.ClientSession;
const ResultCode = horizon.result.Code;
const Result = horizon.Result;
