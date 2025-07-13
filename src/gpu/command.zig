// https://www.3dbrew.org/wiki/GPU/Internal_Registers

pub const Header = packed struct(u32) {
    id: Id,
    mask: u4,
    extra: u8,
    _unused0: u3 = 0,
    consecutive_writing: bool,
};

pub const Id = enum(u16) {
    _,

    pub fn fromRegister(comptime internal_regs: *gpu.Registers.Internal, comptime register: *anyopaque) Id {
        if (@intFromPtr(register) < @intFromPtr(internal_regs) or @intFromPtr(register) >= (@intFromPtr(internal_regs) + @sizeOf(gpu.Registers.Internal)))
            @compileError("invalid internal register, pointer is not within the valid range");

        const offset = @intFromPtr(register) - @intFromPtr(internal_regs);

        if ((offset % @alignOf(u32)) != 0)
            @compileError("invalid internal register, an ID must be aligned to 4 bytes");

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

    pub fn addCommand(queue: *Queue, id: Id, value: u32) void {
        queue.buffer[queue.current_index] = value;
        queue.buffer[queue.current_index + 1] = @bitCast(Header{
            .id = id,
            .mask = 0b1111,
            .extra = 0,
            .consecutive_writing = false,
        });
        queue.current_index += 2;
    }

    pub fn finalize(queue: *Queue) void {
        const internal = &zitrus.memory.arm11.gpu.internal;
        const finalize_id: Id = .fromRegister(internal, &internal.irq.req[0]);

        queue.addCommand(finalize_id, 0x12345678);

        if (!std.mem.isAligned(queue.current_index, 4)) {
            queue.addCommand(finalize_id, 0x12345678);
        }
    }
};

const std = @import("std");

const zitrus = @import("zitrus");
const gpu = zitrus.gpu;
