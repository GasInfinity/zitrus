//! Type-safe PICA200 command queue

pub const Header = packed struct(u32) {
    id: Id,
    mask: u4,
    extra: u8,
    _unused0: u3 = 0,
    incremental_writing: bool,
};

pub const Id = enum(u16) {
    _,

    pub fn fromRegister(comptime base: *pica.Registers.Internal, register: *anyopaque) Id {
        std.debug.assert(@intFromPtr(register) >= @intFromPtr(base) and @intFromPtr(register) < (@intFromPtr(base) + @sizeOf(pica.Registers.Internal))); // invalid internal register, pointer is not within the valid range

        const offset = @intFromPtr(register) - @intFromPtr(base);

        std.debug.assert((offset % @alignOf(u32)) == 0); // invalid internal register, it must be aligned to 4 bytes

        return @enumFromInt(@divExact(offset, @alignOf(u32)));
    }
};

pub const Queue = struct {
    buffer: []align(8) u32,
    current_index: usize,

    pub fn initBuffer(buffer: []align(8) u32) Queue {
        return .{
            .buffer = buffer,
            .current_index = 0,
        };
    }

    pub fn remaining(queue: Queue) []u32 {
        return queue.buffer[queue.current_index..];
    }

    pub fn reset(queue: *Queue) void {
        queue.current_index = 0;
    }

    pub fn add(queue: *Queue, comptime base: *pica.Registers.Internal, register: anytype, value: std.meta.Child(@TypeOf(register))) void {
        return queue.addMasked(base, register, value, 0xF);
    }

    pub fn addMasked(queue: *Queue, comptime base: *pica.Registers.Internal, register: anytype, value: std.meta.Child(@TypeOf(register)), mask: u4) void {
        comptime std.debug.assert(@typeInfo(@TypeOf(register)) == .pointer);

        const Child = std.meta.Child(@TypeOf(register));
        const child_info = @typeInfo(Child);

        const id: Id = .fromRegister(base, register);

        switch (comptime std.math.order(@bitSizeOf(Child), @bitSizeOf(u32))) {
            .eq => {
                queue.buffer[queue.current_index] = switch (child_info) {
                    .@"enum" => @intFromEnum(value),
                    else => @bitCast(value),
                };
                queue.buffer[queue.current_index + 1] = @bitCast(Header{
                    .id = id,
                    .mask = mask,
                    .extra = 0,
                    .incremental_writing = false,
                });

                queue.current_index += 2;
            },
            .gt => {
                const as_u32_array = switch (child_info) {
                    .array => |a| if (@bitSizeOf(a.child) != @bitSizeOf(u32))
                        @compileError("only arrays of 32-bit types are supported for incremental writes")
                    else
                        @as([a.len]u32, @bitCast(value)),
                    .@"struct" => |s| if (s.layout == .auto or (@bitSizeOf(Child) % @bitSizeOf(u32)) != 0)
                        @compileError("only non-auto structs with a bitSize multiple of 32 are supported")
                    else
                        @as([@divExact(@bitSizeOf(Child), @bitSizeOf(u32))]u32, @bitCast(value)),
                    else => @compileError("unsupported type for incremental write"),
                };

                queue.buffer[queue.current_index] = as_u32_array[0];
                queue.buffer[queue.current_index + 1] = @bitCast(Header{
                    .id = id,
                    .mask = mask,
                    .extra = (as_u32_array.len - 1),
                    .incremental_writing = true,
                });
                queue.current_index += 2;

                inline for (1..as_u32_array.len) |i| {
                    queue.buffer[queue.current_index] = as_u32_array[i];
                    queue.current_index += 1;
                }

                // add padding as commands must be aligned to 8 bytes
                if (!std.mem.isAligned(as_u32_array.len - 1, 2)) {
                    queue.buffer[queue.current_index] = 0;
                    queue.current_index += 1;
                }
            },
            .lt => @compileError("commands only support writing full 32-bit values (which you can mask!)"),
        }
    }

    fn IncrementalWritesTuple(comptime base: *pica.Registers.Internal, comptime registers: anytype) type {
        const RegistersType = @TypeOf(registers);

        std.debug.assert(@typeInfo(RegistersType) == .@"struct");
        const st_ty = @typeInfo(RegistersType).@"struct";

        std.debug.assert(st_ty.is_tuple);

        var needed_fields: [st_ty.fields.len]std.builtin.Type.StructField = undefined;

        @setEvalBranchQuota(st_ty.fields.len * 2000);
        for (st_ty.fields, 0..) |field, i| {
            std.debug.assert(@typeInfo(field.type) == .pointer);

            const f_ty = @typeInfo(field.type).pointer;
            const current = registers[i];
            const current_id: Id = .fromRegister(base, current);

            if (@bitSizeOf(f_ty.child) != @bitSizeOf(u32)) @compileLog("only values with a @bitSizeOf(u32) are supported.");

            if (i > 0) {
                const last_id: Id = .fromRegister(base, registers[i - 1]);

                std.debug.assert(std.math.order(@intFromEnum(current_id), @intFromEnum(last_id)) == .gt);
                std.debug.assert((@intFromEnum(current_id) - @intFromEnum(last_id)) == 1);
            }

            needed_fields[i] = .{
                .name = std.fmt.comptimePrint("{}", .{i}),
                .type = f_ty.child,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(f_ty.child),
            };
        }

        return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &needed_fields, .decls = &.{}, .is_tuple = true } });
    }

    pub fn addIncremental(queue: *Queue, comptime base: *pica.Registers.Internal, comptime registers: anytype, values: IncrementalWritesTuple(base, registers)) void {
        return queue.addIncrementalMasked(base, registers, values, 0b1111);
    }

    pub fn addIncrementalMasked(queue: *Queue, comptime base: *pica.Registers.Internal, comptime registers: anytype, values: IncrementalWritesTuple(base, registers), mask: u4) void {
        if (registers.len == 0) return;

        const first_id: Id = .fromRegister(base, registers[0]);

        // NOTE: I do the ptrCast instead of a bitCast because enums cannot be bitcasted, its just a shortcut.
        queue.buffer[queue.current_index] = @as(*const u32, @ptrCast(@alignCast(&values[0]))).*;
        queue.buffer[queue.current_index + 1] = @bitCast(Header{
            .id = first_id,
            .mask = mask,
            .extra = (values.len - 1),
            .incremental_writing = true,
        });
        queue.current_index += 2;

        inline for (1..values.len) |i| {
            queue.buffer[queue.current_index] = @as(*const u32, @ptrCast(@alignCast(&values[i]))).*;
            queue.current_index += 1;
        }

        // add padding as commands must be aligned to 8 bytes
        if (!std.mem.isAligned(values.len - 1, 2)) {
            queue.buffer[queue.current_index] = 0;
            queue.current_index += 1;
        }
    }

    pub fn addConsecutive(queue: *Queue, comptime base: *pica.Registers.Internal, comptime register: anytype, values: []const std.meta.Child(@TypeOf(register))) void {
        return queue.addConsecutiveMasked(base, register, values, 0b1111);
    }

    pub fn addConsecutiveMasked(queue: *Queue, comptime base: *pica.Registers.Internal, comptime register: anytype, values: []const std.meta.Child(@TypeOf(register)), mask: u4) void {
        comptime std.debug.assert(@typeInfo(@TypeOf(register)) == .pointer);

        if (values.len == 0) {
            return;
        }

        const Child = std.meta.Child(@TypeOf(register));
        const id: Id = .fromRegister(base, register);

        std.debug.assert(@bitSizeOf(Child) == @bitSizeOf(u32));
        std.debug.assert(values.len <= std.math.maxInt(u8));

        queue.buffer[queue.current_index] = @as(*const u32, @ptrCast(@alignCast(&values[0]))).*;
        queue.buffer[queue.current_index + 1] = @bitCast(Header{
            .id = id,
            .mask = mask,
            .extra = @intCast(values.len - 1),
            .incremental_writing = false,
        });
        queue.current_index += 2;

        for (1..values.len) |i| {
            queue.buffer[queue.current_index] = @as(*const u32, @ptrCast(@alignCast(&values[i]))).*;
            queue.current_index += 1;
        }

        // add padding as commands must be aligned to 8 bytes
        if (!std.mem.isAligned(values.len - 1, 2)) {
            queue.buffer[queue.current_index] = 0;
            queue.current_index += 1;
        }
    }

    pub fn finalize(queue: *Queue) void {
        const internal = &zitrus.memory.arm11.gpu.internal;

        queue.add(internal, &internal.irq.req[0..4].*, @bitCast(@as(u32, 0x12345678)));

        if (!std.mem.isAligned(queue.current_index, 4)) {
            queue.add(internal, &internal.irq.req[0..4].*, @bitCast(@as(u32, 0x12345678)));
        }
    }
};

const std = @import("std");

const zitrus = @import("zitrus");
const pica = zitrus.pica;
