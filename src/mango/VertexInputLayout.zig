pub const Handle = enum(u64) {
    null = 0,
    _,
};

const GpuAttributeConfig = pica.Registers.Internal.GeometryPipeline.AttributeConfig;
const GpuAttributeBufferConfig = pica.Registers.Internal.GeometryPipeline.AttributeBuffer.Config;
const GpuArrayComponent = GpuAttributeBufferConfig.ArrayComponent;
const GpuAttributePermutation = pica.Registers.Internal.Shader.AttributePermutation;

config: GpuAttributeConfig,
buffer_config: [12]GpuAttributeBufferConfig,
permutation: GpuAttributePermutation,
buffers_len: u8,

const BindingAttributeInfo = struct {
    offset: u8,
    index_format: packed struct(u8) {
        index: u4,
        format: pica.AttributeFormat, 
    },

    pub fn lessThan(_: void, lhs: BindingAttributeInfo, rhs: BindingAttributeInfo) bool {
        return lhs.offset < rhs.offset;
    }
};

pub fn compile(bindings: []const mango.VertexInputBindingDescription, attributes: []const mango.VertexInputAttributeDescription, fixed_attributes: []const mango.VertexInputFixedAttributeDescription) VertexInputLayout {
    var layout: VertexInputLayout = .{
        .config = .{
            .low = .{},
            .high = .{
                .attributes_end = @intCast((attributes.len + fixed_attributes.len) - 1)
            },
        },
        .buffer_config = undefined, 
        .permutation = undefined,
        .buffers_len = @intCast(bindings.len),
    };

    for (bindings, 0..) |binding, binding_index| {
        layout.buffer_config[binding_index].high.bytes_per_vertex = binding.stride;
    }

    var sorted_binding_attributes_end: [12]u8 = @splat(0);
    var sorted_binding_attributes: [12][12]BindingAttributeInfo = undefined;

    for (attributes, 0..) |attribute, attribute_index| {
        const native_format = attribute.format.nativeVertexFormat();

        layout.permutation.setAttribute(@enumFromInt(attribute_index), @enumFromInt(@intFromEnum(attribute.location)));
        layout.config.setAttribute(@enumFromInt(attribute_index), native_format);

        const attrib_binding_index = @intFromEnum(attribute.binding);
        const offset = attribute.offset;

        const current_end = &sorted_binding_attributes_end[attrib_binding_index];
        sorted_binding_attributes[attrib_binding_index][current_end.*] = .{
            .index_format = .{
                .index = @intCast(attribute_index),
                .format = native_format
            },
            .offset = offset
        };
        current_end.* += 1;
    }

    for (&sorted_binding_attributes, &sorted_binding_attributes_end, 0..) |*binding_attributes_array, binding_end, binding_index| {
        const current_binding = &layout.buffer_config[binding_index];
        const sorted_bound_attributes = binding_attributes_array[0..binding_end];

        if(sorted_bound_attributes.len == 0) {
            current_binding.high.num_components = 0;
            break;
        }

        std.sort.insertion(BindingAttributeInfo, sorted_bound_attributes, {}, BindingAttributeInfo.lessThan);
        
        const first_format = sorted_bound_attributes[0].index_format.format;

        // Offsets must start at 0 (no padding in the start of the attribute buffer)
        std.debug.assert(sorted_bound_attributes[0].offset == 0);
        
        var current_binding_alignment: usize = first_format.type.byteSize();
        var current_attribute_offset: usize = current_binding_alignment * (@as(usize, @intFromEnum(first_format.size)) + 1);
        var current_binding_attribute: u4 = 1;

        current_binding.setComponent(.@"0", @enumFromInt(sorted_bound_attributes[0].index_format.index));

        for (sorted_bound_attributes[1..]) |binding_attribute| {
            const new_format = binding_attribute.index_format.format;
            const new_format_type_size = new_format.type.byteSize();
            const new_format_size = new_format_type_size * (@as(usize, @intFromEnum(new_format.size)) + 1);

            current_binding_alignment = @max(current_binding_alignment, new_format_type_size);

            const new_offset = binding_attribute.offset;

            // Offsets must be aligned to the format type size
            std.debug.assert(std.mem.isAligned(new_offset, new_format_type_size));

            // Offsets must be sequential and not overlap
            std.debug.assert(new_offset >= current_attribute_offset);
            const extra_offset = new_offset - current_attribute_offset;

            if(extra_offset > 0) {
                @branchHint(.unlikely);
                
                // If extra offset is needed, it must be aligned to 4-bytes (+ remaining padding if last value didn't have @sizeOf(f32))
                const needed_padding = if(!std.mem.isAligned(current_attribute_offset, @sizeOf(f32))) offset: {
                    const padding_start_offset = std.mem.alignForward(usize, current_attribute_offset, @sizeOf(f32)) - current_attribute_offset;
                    const needed_padding = extra_offset - padding_start_offset;
                    std.debug.assert(std.mem.isAligned(needed_padding, @sizeOf(f32)));
                    
                    break :offset needed_padding;
                } else extra_offset;

                var remaining_padding = needed_padding;
                inline for (&.{ GpuAttributeBufferConfig.ArrayComponent.padding_16, GpuAttributeBufferConfig.ArrayComponent.padding_12, GpuAttributeBufferConfig.ArrayComponent.padding_8, GpuAttributeBufferConfig.ArrayComponent.padding_4 }) |padding| {
                    appendPadAttributes(current_binding, &current_binding_attribute, &remaining_padding, padding);
                }
            }

            current_binding.setComponent(@enumFromInt(current_binding_attribute), @enumFromInt(binding_attribute.index_format.index));
            current_binding_attribute += 1;
            current_attribute_offset = new_offset + new_format_size;
        }

        // Stride must be aligned. 
        std.debug.assert(std.mem.isAligned(current_binding.high.bytes_per_vertex, current_binding_alignment));

        // Stride must not be less than the recorded size of all attributes.
        std.debug.assert(current_binding.high.bytes_per_vertex >= current_attribute_offset);

        const end_attribute_offset = std.mem.alignForward(usize, current_attribute_offset, current_binding_alignment);
        const needed_end_padding = current_binding.high.bytes_per_vertex - end_attribute_offset; 

        // If padding at the end is needed, it must be aligned to 4-bytes
        std.debug.assert(std.mem.isAligned(needed_end_padding, @sizeOf(f32)));

        var remaining_end_padding = needed_end_padding;
        inline for (&.{ GpuArrayComponent.padding_16, GpuArrayComponent.padding_12, GpuArrayComponent.padding_8, GpuArrayComponent.padding_4 }) |padding| {
            appendPadAttributes(current_binding, &current_binding_attribute, &remaining_end_padding, padding);
        }

        current_binding.high.num_components = current_binding_attribute;
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

const VertexInputLayout = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;

const PhysicalAddress = zitrus.PhysicalAddress;
