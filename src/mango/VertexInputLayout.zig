pub const Handle = enum(u32) {
    null = 0,
    _,
};

pub const CompileError = validation.Error;

const GpuAttributeConfig = pica.Graphics.PrimitiveEngine.Attribute.Config;
const GpuAttributeBufferConfig = pica.Graphics.PrimitiveEngine.Attribute.VertexBuffer.Config;
const GpuArrayComponent = GpuAttributeBufferConfig.ArrayComponent;
const GpuAttributePermutation = pica.Graphics.Shader.AttributePermutation;

const gpu_array_paddings: []const GpuArrayComponent = &.{ GpuArrayComponent.padding_16, GpuArrayComponent.padding_12, GpuArrayComponent.padding_8, GpuArrayComponent.padding_4 };

config: GpuAttributeConfig,
buffer_config: [12]GpuAttributeBufferConfig,
permutation: GpuAttributePermutation,
buffers_len: u8,
// TODO: we're missing fixed attributes

const BindingAttributeInfo = struct {
    offset: u8,
    index_format: packed struct(u8) {
        index: u4,
        format: pica.Graphics.PrimitiveEngine.Attribute.Format,
    },

    pub fn lessThan(_: void, lhs: BindingAttributeInfo, rhs: BindingAttributeInfo) bool {
        return lhs.offset < rhs.offset;
    }
};

pub fn compile(bindings: []const mango.VertexInputBindingDescription, attributes: []const mango.VertexInputAttributeDescription, fixed_attributes: []const mango.VertexInputFixedAttributeDescription) CompileError!VertexInputLayout {
    var layout: VertexInputLayout = .{
        .config = .{
            .low = .{},
            .high = .{ .attributes_end = @intCast((attributes.len + fixed_attributes.len) - 1) },
        },
        .buffer_config = undefined,
        .permutation = .{},
        .buffers_len = @intCast(bindings.len),
    };

    var binding_attributes_end: [12]u8 = @splat(0);
    var binding_attributes: [12][12]BindingAttributeInfo = undefined;

    for (attributes, 0..) |attribute, i| {
        const native_format = attribute.format.nativeVertexFormat();
        const binding_index = @intFromEnum(attribute.binding);
        const offset = attribute.offset;

        layout.permutation.setAttribute(@enumFromInt(i), @enumFromInt(@intFromEnum(attribute.location)));
        layout.config.setAttribute(@enumFromInt(i), native_format);
        layout.config.setFlag(@enumFromInt(i), .array);

        const end = &binding_attributes_end[binding_index];

        binding_attributes[binding_index][end.*] = .{
            .index_format = .{
                .index = @intCast(i),
                .format = native_format,
            },
            .offset = offset,
        };

        end.* += 1;
    }

    for (fixed_attributes, attributes.len..) |attribute, i| {
        layout.config.setFlag(@enumFromInt(i), .fixed);
        layout.permutation.setAttribute(@enumFromInt(i), @enumFromInt(@intFromEnum(attribute.location)));
    }

    if (fixed_attributes.len > 0) @panic("TODO: fixed attributes");

    for (bindings, 0..) |binding, binding_index| {
        layout.buffer_config[binding_index] = .{
            .low = .{},
            .high = .{
                .bytes_per_vertex = binding.stride,
                .num_components = 0, // Will be set later
            },
        };
    }

    for (&binding_attributes, &binding_attributes_end, 0..) |*binding_attributes_array, attributes_end, binding_i| {
        const binding = &layout.buffer_config[binding_i];
        const sorted_attributes = binding_attributes_array[0..attributes_end];

        if (sorted_attributes.len == 0) {
            binding.high.num_components = 0;
            break;
        }

        std.sort.insertion(BindingAttributeInfo, sorted_attributes, {}, BindingAttributeInfo.lessThan);

        const first_format = sorted_attributes[0].index_format.format;

        try validation.assert(
            sorted_attributes[0].offset == 0,
            validation.vertex_input_layout.non_zero_initial_offset,
            .{binding_i},
        );

        var current_alignment: usize = first_format.type.byteSize();
        var current_offset: usize = first_format.type.byteSize() * (@as(usize, @intFromEnum(first_format.size)) + 1);
        var current_attribute: u4 = 1;

        binding.setComponent(.@"0", @enumFromInt(sorted_attributes[0].index_format.index));

        for (sorted_attributes[1..], sorted_attributes[0 .. sorted_attributes.len - 1]) |attribute, last_attribute| {
            const last_attribute_i = last_attribute.index_format.index;

            const attribute_i = attribute.index_format.index;
            const format = attribute.index_format.format;
            const format_type_size = format.type.byteSize();
            const format_size = format_type_size * (@as(usize, @intFromEnum(format.size)) + 1);
            const assigned_offset = attribute.offset;
            const next_natural_offset = std.mem.alignForward(usize, current_offset, format_type_size);

            try validation.assert(
                std.mem.isAligned(assigned_offset, format_type_size),
                validation.vertex_input_layout.unaligned_offset,
                .{ attribute_i, layout.permutation.getAttribute(@enumFromInt(attribute_i)), binding_i, format_type_size, assigned_offset },
            );

            try validation.assert(
                assigned_offset >= next_natural_offset,
                validation.vertex_input_layout.not_sequential,
                .{
                    last_attribute_i,
                    layout.permutation.getAttribute(@enumFromInt(last_attribute_i)),
                    attribute_i,
                    layout.permutation.getAttribute(@enumFromInt(attribute_i)),
                    binding_i,
                    last_attribute.offset,
                    last_attribute.offset + last_attribute.index_format.format.byteSize(),
                    assigned_offset,
                    assigned_offset + format_size,
                },
            );

            const padding = assigned_offset - next_natural_offset;

            if (padding > 0) {
                @branchHint(.unlikely);

                try validation.assert(
                    std.mem.isAligned(padding, @sizeOf(f32)),
                    validation.vertex_input_layout.attribute_gap,
                    .{ attribute_i, layout.permutation.getAttribute(@enumFromInt(attribute_i)), binding_i, current_offset, assigned_offset, padding },
                );

                var remaining_padding = padding;
                for (gpu_array_paddings) |pad_attrib| {
                    appendPadAttributes(binding, &current_attribute, &remaining_padding, pad_attrib);
                }
            }

            binding.setComponent(@enumFromInt(current_attribute), @enumFromInt(attribute.index_format.index));
            current_attribute += 1;
            current_offset = assigned_offset + format_size;
            current_alignment = @max(current_alignment, format_type_size);
        }

        const end_attribute_offset = std.mem.alignForward(usize, current_offset, current_alignment);
        const end_padding = binding.high.bytes_per_vertex - end_attribute_offset;

        try validation.assert(
            std.mem.isAligned(binding.high.bytes_per_vertex, current_alignment),
            validation.vertex_input_layout.unaligned_stride,
            .{ binding_i, current_alignment, binding.high.bytes_per_vertex },
        );

        try validation.assert(
            binding.high.bytes_per_vertex >= current_offset,
            validation.vertex_input_layout.small_stride,
            .{ binding_i, current_offset, binding.high.bytes_per_vertex },
        );

        try validation.assert(
            std.mem.isAligned(end_padding, @sizeOf(f32)),
            validation.vertex_input_layout.end_gap,
            .{ binding_i, end_padding },
        );

        var remaining_end_padding = end_padding;
        for (gpu_array_paddings) |padding| {
            appendPadAttributes(binding, &current_attribute, &remaining_end_padding, padding);
        }

        binding.high.num_components = current_attribute;
    }

    return layout;
}

fn appendPadAttributes(current_binding: *GpuAttributeBufferConfig, current_binding_attribute: *u4, remaining_padding: *usize, padding: GpuArrayComponent) void {
    std.debug.assert(@intFromEnum(padding) >= @intFromEnum(GpuArrayComponent.padding_4));

    const components: usize = (@intFromEnum(padding) - @intFromEnum(GpuArrayComponent.padding_4)) + 1;
    while (remaining_padding.* >= @sizeOf(f32) * components) : (remaining_padding.* -= @sizeOf(f32) * components) {
        current_binding.setComponent(@enumFromInt(current_binding_attribute.*), padding);
        current_binding_attribute.* += 1;
    }
}

pub fn toHandle(layout: *VertexInputLayout) Handle {
    return @enumFromInt(@intFromPtr(layout));
}

pub fn fromHandleMutable(handle: Handle) *VertexInputLayout {
    return @as(*VertexInputLayout, @ptrFromInt(@intFromEnum(handle)));
}

test "smoke test" {
    const layout: VertexInputLayout = try .compile(&.{
        .{
            .stride = 12,
        },
    }, &.{ .{
        .offset = 0,
        .binding = .@"0",
        .location = .v0,
        .format = .r32_sfloat,
    }, .{
        .offset = @sizeOf(f32) * 2,
        .binding = .@"0",
        .location = .v1,
        .format = .r8_uscaled,
    }, .{
        .offset = @sizeOf(f32) * 2 + @sizeOf(u16),
        .binding = .@"0",
        .location = .v2,
        .format = .r16_sscaled,
    } }, &.{});

    const u8x1: AttributeFormat = .u8x1;
    const i16x1: AttributeFormat = .i16x1;
    const f32x1: AttributeFormat = .f32x1;

    try expectEqual(.array, layout.config.getFlag(.@"0"));
    try expectEqual(f32x1, layout.config.getAttribute(.@"0"));
    try expectEqual(u8x1, layout.config.getAttribute(.@"1"));
    try expectEqual(i16x1, layout.config.getAttribute(.@"2"));
    try expectEqual(.attribute_0, layout.buffer_config[0].getComponent(.@"0"));
    try expectEqual(.padding_4, layout.buffer_config[0].getComponent(.@"1"));
    try expectEqual(.attribute_1, layout.buffer_config[0].getComponent(.@"2"));
    try expectEqual(.attribute_2, layout.buffer_config[0].getComponent(.@"3"));
    try expectEqual(4, layout.buffer_config[0].high.num_components);
    try expectEqual(12, layout.buffer_config[0].high.bytes_per_vertex);
}

test "gaps are filled with padding" {
    const layout: VertexInputLayout = try .compile(&.{
        .{
            .stride = 44,
        },
    }, &.{
        .{
            .offset = 0,
            .binding = .@"0",
            .location = .v0,
            .format = .r32_sfloat,
        },
        .{
            .offset = 32,
            .binding = .@"0",
            .location = .v1,
            .format = .r32_sfloat,
        },
        .{
            .offset = 40,
            .binding = .@"0",
            .location = .v2,
            .format = .r32_sfloat,
        },
    }, &.{});

    const f32x1: AttributeFormat = .f32x1;
    try expectEqual(.array, layout.config.getFlag(.@"0"));
    try expectEqual(.array, layout.config.getFlag(.@"1"));
    try expectEqual(f32x1, layout.config.getAttribute(.@"0"));
    try expectEqual(f32x1, layout.config.getAttribute(.@"1"));
    try expectEqual(.attribute_0, layout.buffer_config[0].getComponent(.@"0"));
    try expectEqual(.padding_16, layout.buffer_config[0].getComponent(.@"1"));
    try expectEqual(.padding_12, layout.buffer_config[0].getComponent(.@"2"));
    try expectEqual(.attribute_1, layout.buffer_config[0].getComponent(.@"3"));
    try expectEqual(.padding_4, layout.buffer_config[0].getComponent(.@"4"));
    try expectEqual(.attribute_2, layout.buffer_config[0].getComponent(.@"5"));
    try expectEqual(6, layout.buffer_config[0].high.num_components);
    try expectEqual(44, layout.buffer_config[0].high.bytes_per_vertex);
}

test "gap at the end is filled with padding" {
    const layout: VertexInputLayout = try .compile(&.{
        .{
            .stride = 36,
        },
    }, &.{
        .{
            .offset = 0,
            .binding = .@"0",
            .location = .v0,
            .format = .r32_sfloat,
        },
    }, &.{});

    const f32x1: AttributeFormat = .f32x1;
    try expectEqual(.array, layout.config.getFlag(.@"0"));
    try expectEqual(f32x1, layout.config.getAttribute(.@"0"));
    try expectEqual(.attribute_0, layout.buffer_config[0].getComponent(.@"0"));
    try expectEqual(.padding_16, layout.buffer_config[0].getComponent(.@"1"));
    try expectEqual(.padding_16, layout.buffer_config[0].getComponent(.@"2"));
    try expectEqual(3, layout.buffer_config[0].high.num_components);
    try expectEqual(36, layout.buffer_config[0].high.bytes_per_vertex);
}

const testing = std.testing;
const expectEqual = testing.expectEqual;

const VertexInputLayout = @This();

const validation = backend.validation;

const std = @import("std");
const zitrus = @import("zitrus");
const backend = @import("backend.zig");

const mango = zitrus.mango;
const hardware = zitrus.hardware;
const pica = hardware.pica;

const AttributeFormat = pica.Graphics.PrimitiveEngine.Attribute.Format;
