pub const empty: TextureCombinerState = .{
    .config = std.mem.zeroes(pica.Graphics.TextureCombiners.Config),
    .units = undefined,
    .configured = 0,
};

config: PicaCombiners.Config,
units: [6]PicaCombiners.Unit,
configured: u8,

pub fn compile(combiners: []const mango.TextureCombinerUnit, combiner_buffer_sources: []const mango.TextureCombinerUnit.BufferSources) TextureCombinerState {
    std.debug.assert(combiners.len > 0 and combiners.len <= 6);
    std.debug.assert((combiner_buffer_sources.len == 0 and combiners.len == 1) or (combiner_buffer_sources.len == 4 and combiners.len > 4) or combiner_buffer_sources.len == (combiners.len - 1));

    var combiner_state: TextureCombinerState = .{
        .config = std.mem.zeroes(PicaCombiners.Config),
        .units = undefined,
        .configured = @intCast(combiners.len),
    };

    for (combiner_buffer_sources, 0..) |buffer_sources, index| {
        combiner_state.config.setColorBufferSource(@enumFromInt(index), buffer_sources.color_buffer_src.native());
        combiner_state.config.setAlphaBufferSource(@enumFromInt(index), buffer_sources.alpha_buffer_src.native());
    }

    for (combiners, 0..) |combiner, i| {
        combiner_state.units[i] = combiner.native();
    }

    for (combiners.len..combiner_state.units.len) |i| {
        combiner_state.units[i] = mango.TextureCombinerUnit.previous.native();
    }

    return combiner_state;
}

const TextureCombinerState = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const mango = zitrus.mango;
const pica = zitrus.hardware.pica;

const PicaCombiners = pica.Graphics.TextureCombiners;
