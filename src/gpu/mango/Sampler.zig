//! Sampler parameters of a PICA200 texture unit.
//!
//! Samplers just configure the behaviour of the PICA200 when sampling it like projections

pub const AddressMode = enum(u8) {
    clamp_to_edge,
    clamp_to_border,
    repeat,
    mirrored_repeat,

    pub fn native(address_mode: AddressMode) gpu.TextureUnitAddressMode {
        return switch (address_mode) {
            .clamp_to_edge => .clamp_to_edge,
            .clamp_to_border => .clamp_to_border,
            .repeat => .repeat,
            .mirrored_repeat => .mirrored_repeat,
        };
    }
};

pub const Filter = enum(u8) {
    nearest,
    linear,

    pub fn native(filter: Filter) gpu.TextureUnitFilter {
        return switch (filter) {
            .nearest => .nearest,
            .linear => .linear,
        };
    }
};

pub const CreateInfo = extern struct {
    pub const Flags = packed struct(u8) {
        /// The sampled texture (u, v) coordinates will be projected by its w component.
        /// The associated `ImageView` type must not be `cube`.
        projected: bool,
        _: u7 = 0,
    };

    mag_filter: Filter,
    min_filter: Filter,
    address_mode_u: AddressMode,
    address_mode_v: AddressMode,
    lod_bias: f32,
    flags: Flags,
    min_lod: u8,
    max_lod: u8,
    border_color: [4]u8,
};

pub const Data = packed struct(u32) {
};

const std = @import("std");
const zitrus = @import("zitrus");
const gpu = zitrus.gpu;

const mango = gpu.mango;
const cmd3d = gpu.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
