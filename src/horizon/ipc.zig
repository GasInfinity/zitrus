// https://www.3dbrew.org/wiki/IPC
// https://www.3dbrew.org/wiki/Services_API
// https://www.3dbrew.org/wiki/Services

pub const Header = packed struct(u32) {
    translate_parameters: u6,
    normal_parameters: u6,
    _unused: u4 = 0,
    command_id: u16,
};

pub const HandleTranslationDescriptor = packed struct(u32) {
    pub const replace_by_proccess_id = HandleTranslationDescriptor{ .replace_by_process_id = true };

    _reserved0: u1 = 0,
    type: u3 = 0,
    close_handles: bool = false,
    replace_by_process_id: bool = false,
    _reserved1: u20 = 0,
    extra_handles: u6 = 0,

    pub fn init(extra: u6) HandleTranslationDescriptor {
        return HandleTranslationDescriptor{ .extra_handles = extra };
    }

    pub fn closed(extra: u6) HandleTranslationDescriptor {
        return HandleTranslationDescriptor{ .close_handles = true, .extra_handles = extra };
    }
};

pub const StaticBufferTranslationDescriptor = packed struct(u32) {
    _reserved0: u1 = 0,
    type: u3 = 1,
    _reserved1: u6 = 0,
    index: u4,
    size: u18,

    pub fn init(size: usize, buffer_id: u4) StaticBufferTranslationDescriptor {
        return StaticBufferTranslationDescriptor{
            .index = buffer_id,
            .size = @intCast(size),
        };
    }
};

pub const BufferMappingTranslationDescriptor = packed struct(u32) {
    _reserved0: u1 = 0,
    read: bool,
    write: bool,
    type: u1 = 1,
    size: u28,

    pub fn init(size: usize, read: bool, write: bool) BufferMappingTranslationDescriptor {
        return BufferMappingTranslationDescriptor{
            .read = read,
            .write = write,
            .size = @intCast(size),
        };
    }
};

pub const CommandBuffer = extern struct {
    header: Header,
    parameters: [63]u32,

    pub inline fn getLastResult(buffer: CommandBuffer) ResultCode {
        return @as(ResultCode, @bitCast(buffer.parameters[0]));
    }

    // TODO: Rewrite this mess one day
    pub inline fn fillCommand(buffer: *CommandBuffer, comptime command: anytype, normal: anytype, translate: anytype) void {
        const CommandType = @TypeOf(command);

        switch (@typeInfo(CommandType)) {
            .@"enum" => |e| switch (@typeInfo(e.tag_type)) {
                .int => |i| if (i.signedness != .unsigned or i.bits != 16) @compileError("command id must be an u16 enum"),
                else => unreachable,
            },
            else => @compileError("command id must be an enum"),
        }

        if (!@hasDecl(CommandType, "normalParameters") or !@hasDecl(CommandType, "translateParameters"))
            @compileError("command enum must have parameter length methods");

        const needed_normal_parameters = command.normalParameters();
        const needed_translate_parameters = command.translateParameters();

        checkValidArgumentTuple(normal, needed_normal_parameters);
        checkValidArgumentTuple(translate, needed_translate_parameters);

        buffer.header = Header{
            .translate_parameters = needed_translate_parameters,
            .normal_parameters = needed_normal_parameters,
            .command_id = @intFromEnum(command),
        };

        const normal_end = buffer.writeParameters(normal, 0);
        _ = buffer.writeParameters(translate, normal_end);
    }

    inline fn checkValidArgumentTuple(value: anytype, comptime needed_arguments: usize) void {
        switch (@typeInfo(@TypeOf(value))) {
            .@"struct" => |s| if (s.fields.len < needed_arguments)
                @compileError("parameter list must have at least the size of the needed arguments (" ++ std.fmt.comptimePrint("{}", .{needed_arguments}) ++ ")")
            else inline for (s.fields) |field| {
                const field_info = @typeInfo(field.type);

                switch (field_info) {
                    .@"enum", .int, .float => if (@sizeOf(field.type) != @sizeOf(u32))
                        @compileError("cannot use parameter" ++ field.name ++ " with type " ++ @typeName(field.type) ++ " as it does not have @sizeOf(u32)"),
                    .@"struct" => |is| if (is.layout != .@"extern" and is.layout != .@"packed" and @sizeOf(field.type) != @sizeOf(u32))
                        @compileError("cannot bitcast struct " ++ @typeName(field.type) ++ " to an u32, it does not have explicit size"),
                    else => @compileError("cannot bitcast type " ++ @typeName(field.type) ++ ", it cannot be bitcasted to u32"),
                }
            },
            .pointer => |p| {
                if (p.size != .slice or (p.child != u32 and p.child != i32)) {
                    @compileError("parameter list must be a slice of u32/i32");
                }
            },
            else => @compileError("parameter list must be a struct, tuple or slice of u32/i32 (it is a " ++ @tagName(@typeInfo(@TypeOf(value))) ++ ")"),
        }
    }

    inline fn writeParameters(buffer: *CommandBuffer, value: anytype, start: usize) usize {
        const params_info = @typeInfo(@TypeOf(value));
        var i: usize = start;
        switch (params_info) {
            .@"struct" => |s| {
                inline for (s.fields) |field| {
                    const field_info = @typeInfo(field.type);
                    const field_value = @field(value, field.name);
                    buffer.parameters[i] = switch (field_info) {
                        .@"enum" => @intFromEnum(field_value),
                        else => @bitCast(field_value),
                    };
                    i += 1;
                }
                return i;
            },
            .pointer => {
                for (value) |v| {
                    buffer.parameters[i] = @bitCast(v);
                    i += 1;
                }
            },
            else => unreachable,
        }
        return i;
    }
};

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ResultCode = horizon.ResultCode;
