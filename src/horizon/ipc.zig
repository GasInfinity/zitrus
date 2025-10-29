//! Horizon's IPC abstraction, see `Codec` which is what serializes / deserializes types.
//!
//! Based on the documentation found in 3dbrew:
//! * https://www.3dbrew.org/wiki/IPC
//! * https://www.3dbrew.org/wiki/Services_API
//! * https://www.3dbrew.org/wiki/Services

pub const ReplaceByProcessId = enum(u32) { replace, _ };

/// The handle(s) will be closed after the IPC call.
///
/// Can either be an `horizon.Object` (or derived), an array of them, or a `HandleArray`.
pub fn MoveHandles(comptime T: type) type {
    return struct {
        pub const Wrapped = T;

        wrapped: T,

        pub fn move(value: T) MoveHandlesSelf {
            return .{ .wrapped = value };
        }

        const MoveHandlesSelf = @This();
    };
}

/// Allows you to have different handle types within a single array,
/// also allowing you to name them.
pub fn HandleArray(comptime T: type) type {
    return struct {
        pub const Wrapped = T;
        
        wrapped: T,

        pub fn array(value: T) HandleArraySelf {
            return .{ .wrapped = value };
        }

        const HandleArraySelf = @This();
    };
}

pub fn Static(comptime buffer_index: u4) type {
    return struct {
        pub const index = buffer_index;

        slice: []const u8,

        pub fn static(slice: []const u8) StaticSliceSelf {
            return .{ .slice = slice };
        }

        const StaticSliceSelf = @This();
    };
}

pub const Permissions = packed struct(u2) {
    pub const r: Permissions = .{ .read = true };
    pub const w: Permissions = .{ .write = true };
    pub const rw: Permissions = .{ .read = true, .write = true };

    read: bool = false,
    write: bool = false,
};

pub fn Mapped(comptime mapping_permissions: Permissions) type {
    return struct {
        pub const permissions = mapping_permissions;
        pub const Slice = if (permissions.write) []u8 else []const u8;

        slice: Slice,

        pub fn mapped(slice: Slice) MappedSliceSelf {
            return .{ .slice = slice };
        }
        
        const MappedSliceSelf = @This();
    };
}

/// IPC Serializer / Deserializer for a type.
pub const Codec = union(enum) {
    /// Represents a raw type, written as-is.
    /// Takes `@divExact(std.mem.alignForward(u32, size, 4), 4)` normal slots.
    ///
    /// It is forbidden to serialize a `raw` Codec after beginning to write translate slots.
    raw: u32,
    /// Represents a `StaticSlice`, always takes 2 translate slots.
    static_slice,
    /// Represents a `MappedSlice`, always takes 2 translate slots.
    mapped_slice,
    /// Represents a `ReplaceByProcessId` handle, theres literally no reason to have arrays of this, always takes 2 translate slots.
    replace_by_process_id,
    /// Represents an arbitrary amount of handles, can either be a single handle or an array of them.
    ///
    /// Either way all handles have the same type and can be copied with a single `@bitCast`.
    handles: u6,
    /// Represents an arbitrary amount of handles, can either be a single handle or an array of them.
    ///
    /// Either way all handles have the same type and can be copied with a single `@bitCast`.
    ///
    /// Unlike `handles`, the handles will be closed and transferred to the other process.
    move_handles: u6,
    /// Represents a typed and possibly named array of handles, allowing them to have differently-typed handles as an array.
    ///
    /// They're allowed to have both single handles and arrays of them.
    handle_array: []const u6,
    /// Represents a typed and possibly named array of handles, allowing them to have differently-typed handles as an array.
    ///
    /// They're allowed to have both single handles and arrays of them.
    ///
    /// Unlike `handle_array`, the handles will be closed and transferred to the other process.
    move_handle_array: []const u6,
    /// Represents a collection of `Codec`s for `auto` struct serialization.
    /// Each field maps 1:1 to the index of the `std.builtin.Type.StructField` it represents.
    ///
    /// All `raw` parameters must appear first (if any)
    fields: []const Codec,

    pub fn of(comptime T: type) Codec {
        return switch (@typeInfo(T)) {
            .int, .float, .bool => .{ .raw = @sizeOf(T) },
            .@"enum" => if(T == horizon.Object)
                .{ .handles = 1 }
            else if(T == ReplaceByProcessId)
                .replace_by_process_id
            else
                .{ .raw = @sizeOf(T) },
            .@"union" => |un| if(un.layout == .auto)
                @compileError("cannot serialize / deserialize auto unions")
            else .{ .raw = @sizeOf(T) },
            .array => |arr| if(arr.len == 0) 
                @compileError("cannot serialize 0-bit arrays")
            else switch (comptime Codec.of(arr.child)) {
                .raw => |_| .{ .raw = @sizeOf(T) },
                .handles => |_| .{ .handles = arr.len },
                else => @compileError("cannot serialize array of " ++ @typeName(arr.child)),
            },
            .@"struct" => |st| if(comptime isWrappedHandle(T))
                .{ .handles = 1 }
            else switch (st.layout) {
                .@"extern", .@"packed" => .{ .raw = @sizeOf(T) },
                .auto => blk: {
                    if(comptime isStatic(T)) break :blk .static_slice;
                    if(comptime isMapped(T)) break :blk .mapped_slice;
                    if(comptime isMoveHandles(T)) {
                        if(comptime !isValidMoveHandlesType(T.Wrapped)) @compileError("a `MoveHandles` must be wrapping a handle, an array of them or a `HandleArray`");

                        break :blk switch (comptime Codec.of(T.Wrapped)) {
                            .handles => |amount| .{ .move_handles = amount },
                            .handle_array => |flds| .{ .move_handle_array = flds },
                            else => comptime unreachable,
                        };
                    }
                    if(comptime isHandleArray(T)) {
                        if(comptime !isValidHandleArrayType(T.Wrapped)) @compileError("a `HandleArray` must be wrapping a struct / tuple of handles");
                        const wrapped_ty = @typeInfo(T.Wrapped).@"struct";

                        comptime var flds: [wrapped_ty.fields.len]u6 = undefined;

                        inline for (wrapped_ty.fields, 0..) |f, i| {
                            flds[i] = @divExact(@sizeOf(f.type), 4); // No need to check as HandleArray already does.
                        }

                        const runtime_flds = comptime flds; // NOTE: required to not get "runtime value contains reference to comptime var"
                        break :blk .{ .handle_array = &runtime_flds };
                    }
                    
                    comptime var flds: [st.fields.len]Codec = undefined;
                    comptime var params: Buffer.PackedCommand.Parameters = .parameters(0, 0); 

                    inline for (st.fields, 0..) |f, i| {
                        flds[i] = comptime .of(f.type);

                        const fld_params = comptime flds[i].parameters();

                        if(flds[i] == .fields) @compileError("struct cannot contain `auto` nested structs");
                        if(params.translate > 0 and fld_params.normal > 0) @compileError("struct cannot fill 'normal' slots (u8, u16, etc...) after filling 'translate' slots (Handles, StaticSlice, etc...)");

                        params.normal += fld_params.normal;
                        params.translate += fld_params.translate;
                    }

                    const runtime_flds = comptime flds; // NOTE: required to not get "runtime value contains reference to comptime var"
                    break :blk .{ .fields = &runtime_flds };
                },
            },
            else => @compileError("cannot serialize / deserialize " ++ @typeName(T)),
        };
    }

    pub fn write(comptime codec: Codec, comptime T: type, value: T) [codec.size()]u32 {
        return switch (codec) {
            .raw => |sz| @bitCast(@as(*const [sz]u8, @ptrCast(&value)).* ++ @as([std.mem.alignForward(u32, sz, @sizeOf(u32)) - sz]u8, @splat(0))),
            .static_slice => [2]u32{@bitCast(Buffer.TranslationDescriptor.StaticBuffer.init(@intCast(value.slice.len), T.index)), @intCast(@intFromPtr(value.slice.ptr))},
            .mapped_slice => [2]u32{@bitCast(Buffer.TranslationDescriptor.MappedBuffer.init(@intCast(value.slice.len), T.permissions.read, T.permissions.write)), @intCast(@intFromPtr(value.slice.ptr))},
            .replace_by_process_id => [2]u32{@bitCast(Buffer.TranslationDescriptor.Handle.replace_by_proccess_id), 0x00},
            .handles, .move_handles => |amount| [1]u32{@bitCast(Buffer.TranslationDescriptor.Handle.init(amount, codec == .move_handles))} ++ @as(*const [amount]u32, @ptrCast(&value)).*,
            .handle_array, .move_handle_array => |flds| blk: {
                const WrappedType = @TypeOf(value.wrapped);

                const sz = comptime codec.size();
                var raw: [sz]u32 = [1]u32{@bitCast(Buffer.TranslationDescriptor.Handle.init((sz-1), codec == .move_handle_array))} ++ @as([sz-1]u32, @splat(0));

                var curr: usize = 1;
                inline for(flds, @typeInfo(WrappedType).@"struct".fields) |fld, info| {
                    // NOTE: We don't do a @bitCast to avoid having to check if its an enum and having to do @intFromEnum :p
                    raw[curr..][0..fld].* = @as(*const [fld]u32, @ptrCast(&@field(value.wrapped, info.name))).*;
                    curr += fld;
                }

                break :blk raw;
            },
            .fields => |flds| blk: {
                var current: [codec.size()]u32 = undefined; 

                var i: usize = 0;
                inline for (flds, @typeInfo(T).@"struct".fields) |fld, info| {
                    const sz = comptime fld.size();
                    defer i += sz;

                    current[i..][0..sz].* = fld.write(info.type, @field(value, info.name));
                }

                break :blk current;
            },
        };
    }

    pub const ReadError = error{BadTranslationHeader};
    pub fn bufRead(comptime codec: Codec, comptime T: type, buffer: []const u32) !T {
        return switch (codec) {
            .raw => |_| @as(*align(@sizeOf(u32)) const T, @ptrCast(buffer)).*,
            .static_slice => blk: {
                const header: Buffer.TranslationDescriptor.StaticBuffer = @bitCast(buffer[0]);
                
                if(header.type != .static_buffer) return error.BadTranslationHeader;
                if(header.index != T.index) return error.BadTranslationHeader;

                break :blk .static(@as([*]u8, @ptrFromInt(buffer[1]))[0..header.size]);
            },
            .mapped_slice => blk: {
                const header: Buffer.TranslationDescriptor.MappedBuffer = @bitCast(buffer[0]);
                
                if(header.type != 1) return error.BadTranslationHeader;
                if(header.read != T.permissions.read) return error.BadTranslationHeader;
                if(header.write != T.permissions.write) return error.BadTranslationHeader;

                break :blk .mapped(@as([*]u8, @ptrFromInt(buffer[1]))[0..header.size]);
            },
            .replace_by_process_id => blk: {
                const header: Buffer.TranslationDescriptor.Handle = @bitCast(buffer[0]);

                if(header.type != .handle) return error.BadTranslationHeader;
                if(header.extra_handles > 0) return error.BadTranslationHeader;
                if(!header.replace_by_process_id) return error.BadTranslationHeader;

                break :blk @enumFromInt(buffer[1]);
            },
            .handles, .move_handles => |amount| blk: {
                const header: Buffer.TranslationDescriptor.Handle = @bitCast(buffer[0]);

                if(header.type != .handle) return error.BadTranslationHeader;
                if(header.extra_handles != amount-1) return error.BadTranslationHeader;
                if(header.move_handles != (codec == .move_handles)) return error.BadTranslationHeader;

                var result: T = undefined;
                @as(*[amount]u32, @ptrCast(&result)).* = buffer[1..][0..amount].*; 
                break :blk result;
            },
            .handle_array, .move_handle_array => |flds| blk: {
                const sz = codec.size();
                const header: Buffer.TranslationDescriptor.Handle = @bitCast(buffer[0]);

                if(header.type != .handle) return error.BadTranslationHeader;
                if(header.extra_handles != (sz-2)) return error.BadTranslationHeader;
                if(header.move_handles != (codec == .move_handle_array)) return error.BadTranslationHeader;

                const WrappedType = T.Wrapped;
                var result: WrappedType = undefined;
                
                var i: usize = 1;
                inline for (flds, @typeInfo(WrappedType).@"struct".fields) |fld, info| {
                    defer i += fld;
                    
                    @as(*[fld]u32, @ptrCast(&@field(result, info.name))).* = buffer[i..][0..fld].*;
                }

                break :blk .array(result);
            },
            .fields => |flds| blk: {
                var result: T = undefined;
                
                var i: usize = 0;
                inline for (flds, @typeInfo(T).@"struct".fields) |fld, info| {
                    defer i += fld.size();

                    @field(result, info.name) = try fld.bufRead(info.type, buffer[i..]);
                }

                break :blk result;
            },
        };
    }

    /// Total size taken in the `Buffer` in `u32`s
    pub fn size(codec: Codec) usize {
        const params = codec.parameters();
        return params.normal + @as(usize, params.translate);
    }

    pub fn parameters(codec: Codec) Buffer.PackedCommand.Parameters {
        return switch (codec) {
            .raw => |sz| .parameters(@intCast(@divExact(std.mem.alignForward(u32, sz, 4), @sizeOf(u32))), 0),
            .static_slice, .mapped_slice, .replace_by_process_id => .parameters(0, 2),
            .move_handles, .handles => |amount| .parameters(0, amount + 1),
            .move_handle_array, .handle_array => |flds| blk: {
                var sum: u6 = 1;
                
                for (flds) |fld| {
                    sum += fld;
                }

                break :blk .parameters(0, sum);
            },

            .fields => |flds| blk: {
                var params: Buffer.PackedCommand.Parameters = .parameters(0, 0);

                for (flds) |fld| {
                    const fld_parameters = fld.parameters(); 

                    std.debug.assert(params.translate == 0 or (params.translate > 0 and fld_parameters.normal == 0)); // Must not happen, this means somehow we DID accept a normal parameter after a translate one. Tripping this means there's a bug!

                    params.normal += fld_parameters.normal;
                    params.translate += fld_parameters.translate;
                }

                break :blk params;
            },
        };
    }

    fn testExpect(expected: Codec, actual: Codec) !void {
        try testing.expectEqualDeep(expected, actual);
    }

    test of {
        try testExpect(.{ .raw = 1 }, .of(u8));
        try testExpect(.{ .raw = 2 }, .of(u16));
        try testExpect(.{ .raw = 4 }, .of(u32));
        try testExpect(.{ .raw = 8 }, .of(u64));

        try testExpect(.{ .handles = 1 }, .of(horizon.Object));
        try testExpect(.{ .handles = 5 }, .of([5]horizon.Object));
        try testExpect(.{ .handles = 10 }, .of([10]horizon.ClientSession));
        try testExpect(.{ .move_handles = 1 }, .of(MoveHandles(horizon.Object)));
        try testExpect(.{ .move_handles = 4 }, .of(MoveHandles([4]horizon.Object)));
        try testExpect(.{ .move_handles = 2 }, .of(MoveHandles([2]horizon.Process)));
        try testExpect(.static_slice, .of(Static(0)));
        try testExpect(.static_slice, .of(Static(10)));
        try testExpect(.mapped_slice, .of(Mapped(.r)));
        try testExpect(.mapped_slice, .of(Mapped(.w)));

        try testExpect(.{ .handle_array = &.{2, 1, 1} }, .of(HandleArray(struct {
            pads: [2]horizon.Event,
            debug: horizon.Event,
            yeah: horizon.Event,
        })));
        try testExpect(.{ .handle_array = &.{1, 1, 1, 4} }, .of(HandleArray(struct {
            pads: [1]horizon.Event,
            debug: horizon.Event,
            yeah: horizon.Event,
            more: [4]horizon.Synchronization,
        })));
        try testExpect(.{ .move_handle_array = &.{1, 1, 1, 4} }, .of(MoveHandles(HandleArray(struct {
            pads: [1]horizon.Event,
            debug: horizon.Event,
            yeah: horizon.Event,
            more: [4]horizon.Synchronization,
        }))));

        try testExpect(.{ .fields = &.{.of(u8), .of(u16), .of(horizon.Process)} }, .of(struct {
            u8: u8,
            u16: u16,
            hnd: horizon.Process,
        }));

        const Foo = extern struct { u8: u8, u16: u16 };
        try testExpect(.{ .raw = @sizeOf(Foo) }, .of(Foo));
    }

    fn testExpectParameters(params: Buffer.PackedCommand.Parameters, codec: Codec) !void {
        try testing.expectEqual(params, codec.parameters());
    }

    test parameters {
        try testExpectParameters(.parameters(1, 0), .of(u8));
        try testExpectParameters(.parameters(1, 0), .of(u16));
        try testExpectParameters(.parameters(1, 0), .of(u32));
        try testExpectParameters(.parameters(2, 0), .of(u64));
        try testExpectParameters(.parameters(1, 0), .of(extern struct { a: u8, b: u8 }));
        try testExpectParameters(.parameters(4, 0), .of(extern struct { a: [12]u8, b: u8 }));

        try testExpectParameters(.parameters(0, 2), .of(Static(0)));
        try testExpectParameters(.parameters(0, 2), .of(Mapped(.r)));

        try testExpectParameters(.parameters(0, 2), .of(ReplaceByProcessId));
        try testExpectParameters(.parameters(0, 2), .of(horizon.Object));

        try testExpectParameters(.parameters(1, 2), .of(struct {
            u16: u16,
            proc: horizon.Process,
        }));

        try testExpectParameters(.parameters(4, 3), Codec.of(struct {
            u16: u16,
            u32: u32,
            u64: u64,
            handles: HandleArray(struct {
                pad: horizon.Event,
                debug: horizon.Event,
            }),
        }));
    }

    fn testExpectSize(sz: usize, codec: Codec) !void {
        try testing.expectEqual(sz, codec.size());
    }

    test size {
        try testExpectSize(4, .of(struct {
            u8: u8,
            u32: u32,
            ev: horizon.Event,
        }));
    }

    fn testExpectWritten(written: []const u32, comptime T: type, value: T) !void {
        const codec: Codec = comptime .of(T);
        try testing.expectEqualSlices(u32, written, &codec.write(T, value));
    }

    test write {
        const Foo = struct {
            u8: u8 = 42,
            u16: u16 = 69,
            oh: HandleArray(struct {
                no: horizon.Event = @bitCast(@as(u32, 200)),
                yes: horizon.Event = @bitCast(@as(u32, 500)),
            }) = .array(.{}),
        };

        try testExpectWritten(&.{42, 69, @bitCast(Buffer.TranslationDescriptor.Handle.initCopy(2)), 200, 500}, Foo, .{});

        const Bar= extern struct {
            u8: [2]u8 = @splat(42),
            u16: u16 = 69,
        };

        try testExpectWritten(&.{42, 69, @bitCast(Buffer.TranslationDescriptor.Handle.initCopy(2)), 200, 500}, Foo, .{});

        if(builtin.target.cpu.arch.endian() == .little) try testExpectWritten(&@as([1]u32, @bitCast([_]u8{42, 42, 69, 0})), Bar, .{});

        // NOTE: We cannot test `MappedSlice`s and `StaticSlice`s on >64-bit platforms as we do an `@intFromPtr`
    }

    fn testExpectRead(comptime T: type, expected: T, read: []const u32) !void {
        const codec: Codec = comptime .of(T);
        try testing.expectEqualDeep(expected, try codec.bufRead(T, read));
    }

    test bufRead {
        const Foo = struct { u8: u8, u16: u16, obj: horizon.Object }; 
        
        try testExpectRead(Foo, .{ .u8 = 42, .u16 = 69, .obj = @enumFromInt(0x200) }, &.{42, 69, @bitCast(Buffer.TranslationDescriptor.Handle.initCopy(1)), 0x200});
    }
};

pub fn Command(comptime CommandId: type, comptime command_id: CommandId, comptime CommandRequest: type, comptime CommandResponse: type) type {
    std.debug.assert(@typeInfo(CommandRequest) == .@"struct");
    std.debug.assert(@typeInfo(CommandResponse) == .@"struct");

    const StaticOutput = if(@hasDecl(CommandRequest, "StaticOutput")) @field(CommandRequest, "StaticOutput") else struct {};

    if(@typeInfo(StaticOutput) != .@"struct") @compileError("StaticOutput must only contain output `[]u8`s for the Command");

    for (@typeInfo(StaticOutput).@"struct".fields) |f| {
        const f_ty = @typeInfo(f.type);

        if(f_ty != .pointer) @compileError("StaticOutput field '" ++ f.name ++ "' must be a slice or pointer to one item");

        switch (f_ty.pointer.size) {
            .c, .many => @compileError("StaticOutput field '" ++ f.name ++ "' must be a slice or pointer to one item"),
            .slice, .one => {},
        }
    }

    return struct {
        pub const Id = CommandId;
        pub const id = command_id;

        pub const Request = CommandRequest;
        pub const Response = CommandResponse;

        pub const RequestStaticOutput = StaticOutput;

        pub const request: Codec = .of(CommandRequest);
        pub const response: Codec = .of(CommandResponse);

        pub const request_parameters: Buffer.PackedCommand.Parameters = request.parameters();
        pub const response_parameters: Buffer.PackedCommand.Parameters = response.parameters();
    };
}

pub const Buffer = extern struct {
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
            move_handles: bool = false,
            replace_by_process_id: bool = false,
            _reserved1: u20 = 0,
            extra_handles: u6 = 0,

            pub fn init(len: u6, move: bool) Handle {
                std.debug.assert(len > 0);
                return .{ .extra_handles = (len - 1), .move_handles = move };
            }

            pub fn initCopy(len: u6) Handle {
                std.debug.assert(len > 0);
                return .{ .extra_handles = (len - 1) };
            }

            pub fn initMove(len: u6) Handle {
                std.debug.assert(len > 0);
                return .{ .move_handles = true, .extra_handles = len - 1 };
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

        pub const MappedBuffer = packed struct(u32) {
            _reserved0: u1 = 0,
            read: bool,
            write: bool,
            type: u1 = 1,
            size: u28,

            pub fn init(size: u28, read: bool, write: bool) MappedBuffer {
                return .{
                    .read = read,
                    .write = write,
                    .size = size,
                };
            }
        };

        handle: Handle,
        static_buffer: StaticBuffer,
        buffer_mapping: MappedBuffer,
    };

    pub const PackedCommand = extern struct {
        pub const Parameters = packed struct(u12) {
            translate: u6,
            normal: u6,

            pub fn parameters(normal: u6, translate: u6) Parameters {
                return .{ .normal = normal, .translate = translate };
            }
        };

        pub const Header = packed struct(u32) {
            parameters: Parameters,
            _unused: u4 = 0,
            command_id: u16,
        };

        header: Header,
        parameters: [63]u32,
    };

    packed_command: PackedCommand,
    static_buffers: [32]u32,

    pub fn sendRequest(buffer: *Buffer, session: ClientSession, comptime DefinedCommand: type, request: DefinedCommand.Request, static_output: DefinedCommand.RequestStaticOutput) !Result(DefinedCommand.Response) {
        buffer.writeRequest(DefinedCommand, request, static_output);
        try session.sendRequest();
        return try buffer.readResponse(DefinedCommand);
    }

    pub fn writeRequest(buffer: *Buffer, comptime DefinedCommand: type, request: DefinedCommand.Request, static_output: DefinedCommand.RequestStaticOutput) void {
        buffer.packed_command.header = .{
            .command_id = @intFromEnum(DefinedCommand.id),
            .parameters = DefinedCommand.request_parameters,
        };
        const written = DefinedCommand.request.write(DefinedCommand.Request, request);
        comptime std.debug.assert(written.len <= buffer.packed_command.parameters.len); 

        @memcpy(buffer.packed_command.parameters[0..written.len], &written);

        inline for(@typeInfo(DefinedCommand.RequestStaticOutput).@"struct".fields, 0..) |f, i| {
            const static_buffer: []u8 = @ptrCast(@field(static_output, f.name));

            buffer.static_buffers[i << 1] = @bitCast(TranslationDescriptor.StaticBuffer.init(@intCast(static_buffer.len), @intCast(i)));
            buffer.static_buffers[i << 1 + 1] = @intCast(@intFromPtr(static_buffer.ptr));
        }
    }

    pub fn writeResponse(buffer: *Buffer, comptime DefinedCommand: type, result: Result(DefinedCommand.Response)) void {
        if(!result.code.isSuccess()) {
            buffer.packed_command.header = .{
                .command_id = @intFromEnum(DefinedCommand.id),
                .parameters = .parameters(1, 0),
            };
            
            buffer.packed_command.parameters[0] = @bitCast(result.code);
            return;
        }

        buffer.packed_command.header = .{
            .command_id = @intFromEnum(DefinedCommand.id),
            .parameters = .parameters(DefinedCommand.response_parameters.normal + 1, DefinedCommand.response_parameters.translate),
        };

        const written = DefinedCommand.response.write(DefinedCommand.Response, result.value);
        comptime std.debug.assert(written.len <= buffer.packed_command.parameters.len); 

        buffer.packed_command.parameters[0] = @bitCast(result.code);
        @memcpy(buffer.packed_command.parameters[1..][0..written.len], &written);
    }

    pub const ReadError = error{
        BadIpcHeader,
    } || Codec.ReadError;

    pub fn readResponse(buffer: *Buffer, comptime DefinedCommand: type) ReadError!Result(DefinedCommand.Response) {
        if(buffer.packed_command.header.command_id != @intFromEnum(DefinedCommand.id)) return error.BadIpcHeader;

        const code: horizon.result.Code = @bitCast(buffer.packed_command.parameters[0]);

        if(!code.isSuccess()) return .of(code, undefined);

        if(buffer.packed_command.header.parameters.normal != DefinedCommand.response_parameters.normal + 1) return error.BadIpcHeader;
        if(buffer.packed_command.header.parameters.translate != DefinedCommand.response_parameters.translate) return error.BadIpcHeader;

        return .of(code, try DefinedCommand.response.bufRead(DefinedCommand.Response, buffer.packed_command.parameters[1..]));
    }

    pub fn readRequest(buffer: *Buffer, comptime DefinedCommand: type) ReadError!DefinedCommand.Request {
        if(buffer.packed_command.header.command_id != @intFromEnum(DefinedCommand.id)) return error.BadIpcHeader;
        if(buffer.packed_command.header.parameters != DefinedCommand.request_parameters) return error.BadIpcHeader;
        
        return DefinedCommand.request.bufRead(DefinedCommand.Request, &buffer.packed_command.parameters);
    }
};

const command_testing = struct {
    const Id = enum(u16) {
        foo = 0x0001,
        bar,
        foobar,
    };

    const Foo = Command(Id, .foo, struct {
        size: u32,
        my_process: ReplaceByProcessId = .replace,
    }, struct {
        newly_standard: u32,
        // Fully typed `HandleArray`, yay!
        newly_handles: HandleArray(struct {
            shared: horizon.MemoryBlock,
            pad: [2]horizon.Event,
        }),
    });
};

test Buffer {
    var buf: Buffer = undefined;

    const request: command_testing.Foo.Request = .{ .size = 20 };
    buf.writeRequest(command_testing.Foo, request, .{});

    try testing.expectEqual(@intFromEnum(command_testing.Id.foo), buf.packed_command.header.command_id);
    try testing.expectEqual(command_testing.Foo.request_parameters, buf.packed_command.header.parameters);

    try testing.expectEqualSlices(u32, &.{20}, buf.packed_command.parameters[0..1]);
    try testing.expectEqual(request, try buf.readRequest(command_testing.Foo));
    
    const response: command_testing.Foo.Response = .{
        .newly_standard = 0x4269,
        .newly_handles = .array(.{
            .shared = @bitCast(@as(u32, 0x800)),
            .pad = .{@bitCast(@as(u32, 0x42)), @bitCast(@as(u32, 0x7958))},
        }),
    };

    const result: horizon.Result(command_testing.Foo.Response) = .of(.success, response);
    buf.writeResponse(command_testing.Foo, result);

    try testing.expectEqual(0, buf.packed_command.parameters[0]);
    try testing.expectEqualSlices(u32, &.{0x4269, @bitCast(Buffer.TranslationDescriptor.Handle.initCopy(3)), 0x800, 0x42, 0x7958}, buf.packed_command.parameters[1..][0..5]);
    try testing.expectEqual(result, try buf.readResponse(command_testing.Foo));
}

fn isHandleOrProcessId(comptime T: type) bool {
    return T == horizon.Object or T == ReplaceByProcessId;
}

fn isMoveHandles(comptime T: type) bool {
    return @hasDecl(T, "Wrapped") and T == MoveHandles(@field(T, "Wrapped"));
}

fn isValidMoveHandlesType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => isWrappedHandle(T) or isHandleArray(T),
        .array => |a| isWrappedHandle(a.child),
        .@"enum" => T == horizon.Object,
        else => false,
    };
}

fn isHandleArray(comptime T: type) bool {
    return @hasDecl(T, "Wrapped") and T == HandleArray(@field(T, "Wrapped"));
}

fn isValidHandleArrayType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |st| for (st.fields) |f| switch (@typeInfo(f.type)) {
            .@"struct" => if(!isWrappedHandle(f.type)) return false,
            .array => |arr| if(!isWrappedHandle(arr.child)) return false,
            .@"enum" => if(f.type != horizon.Object) return false,
            else => return false,
        } else true,
        else => false,
    };
}

fn isStatic(comptime T: type) bool {
    return @hasDecl(T, "index") and @TypeOf(@field(T, "index")) == u4 and T == Static(@field(T, "index"));
}

fn isMapped(comptime T: type) bool {
    return @hasDecl(T, "permissions") and @TypeOf(@field(T, "permissions")) == Permissions and T == Mapped(@field(T, "permissions"));
}

fn isWrappedHandle(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| s.layout == .@"packed" and s.fields.len == 1 and isWrappedHandle(s.fields[0].type),
        .@"enum" => T == horizon.Object,
        else => false,
    };
}

comptime {
    _ = Codec;
}

const testing = std.testing;

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ClientSession = horizon.ClientSession;
const ResultCode = horizon.result.Code;
const Result = horizon.Result;
