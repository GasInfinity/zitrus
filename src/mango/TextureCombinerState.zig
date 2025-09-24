combiner: [6]NativeCombiner,
update_buffer: NativeState,

pub fn compile(previous_state: NativeState, combiners: []const mango.TextureCombiner, combiner_buffer_sources: []const mango.TextureCombiner.BufferSources) TextureCombinerState {
    std.debug.assert(combiners.len > 0 and combiners.len <= 6);
    // TODO: Test this assertion? Do buffer sources apply to combiners 0-3, 1-4 or 2-5?
    std.debug.assert((combiner_buffer_sources.len == 0 and combiners.len == 1) or (combiner_buffer_sources.len == 4 and combiners.len > 4) or combiner_buffer_sources.len == combiners.len);

    var combiner_state: TextureCombinerState = .{
        .combiner = undefined,
        .update_buffer = previous_state,
    };

    for (combiner_buffer_sources, 0..) |buffer_sources, index| {
        combiner_state.update_buffer.setColorBufferSource(@enumFromInt(index), buffer_sources.color_buffer_src.native());
        combiner_state.update_buffer.setAlphaBufferSource(@enumFromInt(index), buffer_sources.alpha_buffer_src.native());
    }

    for (combiners, 0..) |combiner, i| {
        combiner_state.combiner[i] = combiner.native();
    }

    for (combiners.len..combiner_state.combiner.len) |i| {
        combiner_state.combiner[i] = mango.TextureCombiner.previous.native();
    }

    return combiner_state;
}

const TextureCombinerState = @This();

const NativeState = pica.Registers.Internal.TextureCombiners.UpdateBuffer;
const NativeCombiner = pica.Registers.Internal.TextureCombiners.Combiner;

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.pica;

const cmd3d = pica.cmd3d;
