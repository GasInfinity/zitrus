pub const Usage = packed struct(u8) {
    /// Specifies that the buffer can be used as the source of a transfer operation.
    transfer_src: bool = false,
    /// Specifies that the buffer can be used as the destination of a transfer operation.
    transfer_dst: bool = false,
    /// Specifies that the buffer can be used as an index buffer.
    index_buffer: bool = false,
    /// Specifies that the buffer can be used as a vertex buffer.
    vertex_buffer: bool = false,
    _: u4 = 0,
};

pub const CreateInfo = extern struct {
    size: usize,
    usage: Usage,
};

// NOTE: Buffers are not mapped directly so we don't need their virtual address.
address: zitrus.PhysicalAddress,
size: usize,
usage: Usage,

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const internal_regs = &zitrus.memory.arm11.gpu.internal;
