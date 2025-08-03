// XXX: This is not that great, the hardware can do MUCH more (coherent memory and persistently mapped buffers, hi?).
// We could store one physical address only and map it but the kernel doesnt support that :(((

virtual: *anyopaque,
physical: PhysicalAddress,
size: usize,

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
