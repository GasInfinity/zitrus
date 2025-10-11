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

data: [256]Data,

pub fn init(create_info: mango.LightLookupTableCreateInfo) LightLookupTable {
    return .{
        .data = if (create_info.map) |map|
            Data.initContext(ExternAdapterContext{
                .map = map,
                .ctx = create_info.context,
            }, create_info.absolute)
        else
            @panic("TODO"),
    };
}

pub fn toHandle(lut: *LightLookupTable) Handle {
    return @enumFromInt(@intFromPtr(lut));
}

pub fn fromHandleMutable(handle: Handle) *LightLookupTable {
    return @as(*LightLookupTable, @ptrFromInt(@intFromEnum(handle)));
}

const LightLookupTable = @This();
const Data = pica.Graphics.FragmentLighting.LookupTable.Data;

const backend = @import("backend.zig");

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;

const pica = zitrus.hardware.pica;
