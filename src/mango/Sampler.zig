//! Sampler parameters of a PICA200 texture unit.
//!
//! Samplers just configure the behaviour of the PICA200 when sampling it like projections

pub const Handle = enum(u64) {
    null = 0,
    _,
};

pub const Data = packed struct(u64) {
    valid: bool = true,
    mag_filter: pica.TextureUnitFilter,
    min_filter: pica.TextureUnitFilter,
    mip_filter: pica.TextureUnitFilter,
    address_mode_u: pica.TextureUnitAddressMode,
    address_mode_v: pica.TextureUnitAddressMode,
    min_lod: u4,
    max_lod: u4,
    lod_bias: u13,
    border_color_r: u8,
    border_color_g: u8,
    border_color_b: u8,
    border_color_a: u8,
    _: u1 = 0,

    pub fn init(create_info: mango.SamplerCreateInfo) Data {
        return .{
            .mag_filter = create_info.mag_filter.native(),
            .min_filter = create_info.min_filter.native(),
            .mip_filter = create_info.mip_filter.native(),
            .address_mode_u = create_info.address_mode_u.native(),
            .address_mode_v = create_info.address_mode_v.native(),
            .min_lod = @intCast(create_info.min_lod),
            .max_lod = @intCast(create_info.max_lod),
            .lod_bias = 0, // TODO: Fixed point
            .border_color_r = create_info.border_color[0],
            .border_color_g = create_info.border_color[1],
            .border_color_b = create_info.border_color[2],
            .border_color_a = create_info.border_color[3],
        };
    }
};

data: Data,

pub fn toHandle(sampler: Sampler) Handle {
    return @enumFromInt(@as(u64, @bitCast(sampler.data)));
}

pub fn fromHandle(handle: Handle) Sampler {
    // TODO: With runtime safety the handle is a real pointer with some metadata
    return .{
        .data = @bitCast(@intFromEnum(handle)),
    };
}

const Sampler = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PhysicalAddress = zitrus.hardware.PhysicalAddress;
