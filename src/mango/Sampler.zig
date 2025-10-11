//! Sampler parameters of a PICA200 texture unit.
//!
//! Samplers just configure the behaviour of the PICA200 when sampling it like projections

pub const Handle = enum(u64) {
    null = 0,
    _,
};

pub const Data = packed struct(u64) {
    // NOTE: This is to make a possibly valid `Handle` null.
    valid: bool = true,
    mag_filter: pica.TextureUnitFilter,
    min_filter: pica.TextureUnitFilter,
    mip_filter: pica.TextureUnitFilter,
    address_mode_u: pica.TextureUnitAddressMode,
    address_mode_v: pica.TextureUnitAddressMode,
    min_lod: u4,
    max_lod: u4,
    lod_bias: pica.Q4_8,
    projected: bool = false,
    // NOTE: Don't move this, it IS like this to get the border color with just one bit shift.
    border_color_r: u8,
    border_color_g: u8,
    border_color_b: u8,
    border_color_a: u8,

    pub fn init(create_info: mango.SamplerCreateInfo) Data {
        return .{
            .mag_filter = create_info.mag_filter.native(),
            .min_filter = create_info.min_filter.native(),
            .mip_filter = create_info.mip_filter.native(),
            .address_mode_u = create_info.address_mode_u.native(),
            .address_mode_v = create_info.address_mode_v.native(),
            .min_lod = @intCast(create_info.min_lod),
            .max_lod = @intCast(create_info.max_lod),
            .lod_bias = .ofSaturating(create_info.lod_bias),
            .border_color_r = create_info.border_color[0],
            .border_color_g = create_info.border_color[1],
            .border_color_b = create_info.border_color[2],
            .border_color_a = create_info.border_color[3],
        };
    }

    pub fn borderColor(data: Data) [4]u8 {
        return @bitCast(@as(u32, @truncate(@as(u64, @bitCast(data)) >> 32)));
    }
};

data: Data,

pub fn toHandle(sampler: Sampler) Handle {
    return @enumFromInt(@as(u64, @bitCast(sampler.data)));
}

pub fn fromHandle(handle: Handle) Sampler {
    return .{ .data = @bitCast(@intFromEnum(handle)) };
}

const Sampler = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
