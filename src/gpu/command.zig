// https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const Header = packed struct(u32) {
    id: Id,
    mask: u4,
    extra: u8,
    _unused0: u3 = 0,
    incremental_writing: bool,
};

pub const Id = enum(u16) {
    _,

    pub fn fromRegister(comptime base: *gpu.Registers.Internal, comptime register: *anyopaque) Id {
        if (@intFromPtr(register) < @intFromPtr(base) or @intFromPtr(register) >= (@intFromPtr(base) + @sizeOf(gpu.Registers.Internal)))
            @compileError("invalid internal register, pointer is not within the valid range");

        const offset = @intFromPtr(register) - @intFromPtr(base);

        if ((offset % @alignOf(u32)) != 0)
            @compileError("invalid internal register, it must be aligned to 4 bytes");

        return @enumFromInt(@divExact(offset, @alignOf(u32)));
    }
};

// TODO: Do we want a real queue, don't we?
pub const Queue = struct {
    buffer: []align(8) u32,
    current_index: usize,

    pub fn initBuffer(buffer: []align(8) u32) Queue {
        std.debug.assert(std.mem.isAligned(buffer.len, 4));

        return .{
            .buffer = buffer,
            .current_index = 0,
        };
    }

    pub fn reset(queue: *Queue) void {
        queue.current_index = 0;
    }

    // TODO: addConsecutive/Masked(queue: *Queue, comptime base: *gpu.Registers.Internal, comptime register: anytype, values: []std.meta.Child(@TypeOf(register)))
    // TODO: addIncremental/Masked(queue: *Queue, comptime base: *gpu.Registers.Internal, comptime register: anytype)
    // to add incrementally registers that do NOT have same type (cannot be used in add/Masked as they're neither arrays nor an extern/packed struct)

    pub fn add(queue: *Queue, comptime base: *gpu.Registers.Internal, comptime register: anytype, value: std.meta.Child(@TypeOf(register))) void {
        return queue.addMasked(base, register, value, 0xF);
    }

    pub fn addMasked(queue: *Queue, comptime base: *gpu.Registers.Internal, comptime register: anytype, value: std.meta.Child(@TypeOf(register)), mask: u4) void {
        comptime std.debug.assert(@typeInfo(@TypeOf(register)) == .pointer);

        const Child = std.meta.Child(@TypeOf(register));
        const child_info = @typeInfo(Child);

        const id: Id = .fromRegister(base, register);

        switch (comptime std.math.order(@bitSizeOf(Child), @bitSizeOf(u32))) {
            .eq => {
                queue.buffer[queue.current_index] = switch(child_info) {
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
                const as_u32_array = switch(child_info) {
                    .array => |a| if(@bitSizeOf(a.child) != @bitSizeOf(u32))
                        @compileError("only arrays of 32-bit types are supported for incremental writes")
                    else @as([a.len]u32, @bitCast(value)),
                    .@"struct" => |s| if(s.layout == .auto or (@bitSizeOf(Child) % @bitSizeOf(u32)) != 0)
                        @compileError("only non-auto structs with a bitSize multiple of 32 are supported")
                    else @as([@divExact(@bitSizeOf(Child), @bitSizeOf(u32))]u32, @bitCast(value)),
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
                if(!std.mem.isAligned(as_u32_array.len - 1, 2)) {
                    queue.buffer[queue.current_index] = 0;
                    queue.current_index += 1;
                }
            },
            .lt => @compileError("commands only support writing full 32-bit values (which you can mask!)"),
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
const gpu = zitrus.gpu;
