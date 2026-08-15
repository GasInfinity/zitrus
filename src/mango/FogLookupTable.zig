pub const Handle = enum(u32) {
    null = 0,
    _,
};

const ExternAdapterContext = struct {
    map: *const fn (?*anyopaque, f32) callconv(.c) f32,
    ctx: ?*anyopaque,

    pub fn value(ctx: ExternAdapterContext, x: f32) f32 {
        return ctx.map(ctx.ctx, x);
    }
};

data: [128]Data,

pub fn init(create_info: mango.FogLookupTableCreateInfo) FogLookupTable {
    return .{
        .data = if (create_info.map) |map|
            Data.initContext(ExternAdapterContext{
                .map = map,
                .ctx = create_info.context,
            })
        else if (create_info.context) |_|
            @panic("TODO")
        else
            undefined,
    };
}

pub fn toHandle(lut: *FogLookupTable) Handle {
    return @enumFromInt(@intFromPtr(lut));
}

pub fn fromHandleMutable(handle: Handle) *FogLookupTable {
    return @as(*FogLookupTable, @ptrFromInt(@intFromEnum(handle)));
}

const FogLookupTable = @This();
const Data = pica.Graphics.TextureCombiners.FogData;

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const pica = zitrus.hardware.pica;
