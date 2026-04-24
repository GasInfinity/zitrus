//! Ericsson Texture Compression Decoder & Encoder/Compressor
//!
//! Only supports ETC1 currently but ETC2 decoding shouldn't
//! be too difficult to implement.
//!
//! Based on:
//! - https://registry.khronos.org/OpenGL/extensions/OES/OES_compressed_ETC1_RGB8_texture.txt
//! - The ETC1 encoder/compressor (`Block.pack`) is based on Rich Geldreich's rg_etc1, licensed under ZLib.
//!
//! Useful links:
//! - https://nicjohnson6790.github.io/etc2-primer/
//!
//! TODO: Move this into its own library

pub const pixels_per_block = 4;

/// All fields should be read as big endian.
pub const Pkm = extern struct {
    pub const Format = enum(u16) {
        etc1_rgb,
        etc2_rgb,
        etc2_rgba_old,
        etc2_rgba,
        etc2_rgba1,
        etc2_r,
        etc2_rg,
        etc2_r_signed,
        etc2_rg_signed,
        _,
    };

    pub const magic_value = "PKM ";

    magic: [magic_value.len]u8 = magic_value.*,
    /// "10" for ETC1, "20" for ETC2
    version: [2]u8 = "10".*,
    format: Format,
    width: u16,
    height: u16,
    real_width: u16,
    real_height: u16,
};

pub const Intensity = enum(u3) {
    pub const Selector = enum(u2) {
        // order matters!
        large_negative,
        small_negative,
        small,
        large,

        pub fn isNegative(sel: Selector) bool {
            return switch (sel) {
                .large_negative, .small_negative => true,
                .small, .large => false,
            };
        }

        pub fn isLarge(sel: Selector) bool {
            return switch (sel) {
                .large_negative, .large => true,
                .small_negative, .small => false,
            };
        }
    };

    pub const table: [8][2]u8 = .{
        .{ 2, 8 },
        .{ 5, 17 },
        .{ 9, 29 },
        .{ 13, 42 },
        .{ 18, 60 },
        .{ 24, 80 },
        .{ 33, 106 },
        .{ 47, 183 },
    };

    @"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7",

    pub fn values(intensity: Intensity) *const [2]u8 {
        return &table[@intFromEnum(intensity)];
    }

    pub fn allSelectors(intensity: Intensity, color: @Vector(3, u8)) std.EnumArray(Selector, @Vector(3, u8)) {
        const vals = intensity.values();
        var all: std.EnumArray(Selector, @Vector(3, u8)) = undefined;
        for (std.enums.values(Selector)) |sel| {
            const splatted: @Vector(3, u8) = @splat(vals[@intFromBool(sel.isLarge())]);
            all.set(sel, if (sel.isNegative()) color -| splatted else color +| splatted);
        }
        return all;
    }
    
    pub const ColorsWithLuma = struct {
        colors: std.EnumArray(Selector, @Vector(3, u8)),
        lumas: std.EnumArray(Selector, u16),
    };

    pub fn allSelectorsWithLuma(intensity: Intensity, color: @Vector(3, u8)) ColorsWithLuma {
        const vals = intensity.values();
        var colors: std.EnumArray(Selector, @Vector(3, u8)) = undefined;
        var lumas: std.EnumArray(Selector, u16) = undefined;
        for (std.enums.values(Selector)) |sel| {
            const splatted: @Vector(3, u8) = @splat(vals[@intFromBool(sel.isLarge())]);
            colors.set(sel, if (sel.isNegative()) color -| splatted else color +| splatted);
            lumas.set(sel, @reduce(.Add, @as(@Vector(3, u16), colors.get(sel))));
        }
        return .{ .colors = colors, .lumas = lumas };
    }
};

pub const Block = packed struct(u64) {
    pub const Direction = enum(u1) {
        /// Two 2x4 blocks, side by side
        ///
        /// XXOO
        /// XXOO
        /// XXOO
        /// XXOO
        vertical,
        /// Two 4x2 blocks
        ///
        /// XXXX
        /// XXXX
        /// OOOO
        /// OOOO
        horizontal,
    };

    pub const Selectors = packed struct(u32) {
        pub const SubSet = std.bit_set.IntegerBitSet(8);
        pub const Set = std.bit_set.IntegerBitSet(16);

        large: Set,
        negative: Set,

        /// Merges sub-block selectors with left->right format rearranging them into 
        /// top->bottom (ETC) format.
        pub fn merge(direction: Direction, sub_large: [2]SubSet, sub_negative: [2]SubSet) Selectors {
            var large: Set = .empty;
            var negative: Set = .empty;

            // these look like magic values but it's pretty simple:
            // when we're in a vertical orientation, the index rearrangement looks like this:
            //
            // 0b000 -> 0b000
            // 0b001 -> 0b100
            // 0b010 -> 0b001
            // 0b011 -> 0b101
            // 0b100 -> 0b010
            // 0b101 -> 0b110
            // 0b110 -> 0b011
            // 0b111 -> 0b111
            //
            // which if you know a lil bit about bit-tricks™ you see that it is a simple rotr; the 
            // horizontal case is almost the same
            const rotr_mask: u3, const rotr_shift: u3, const rearranged_second_offset: usize = switch (direction) {
                // XX OO
                // XX OO
                // XX OO
                // XX OO
                .vertical => .{ 0b001, 1, 8 },
                // XXXX
                // XXXX
                //
                // OOOO
                // OOOO
                .horizontal => .{ 0b011, 2, 2 },
            };

            for (0..8) |i| {
                const stored_idx = ((i & rotr_mask) << 2) | (i >> rotr_shift);

                negative.setValue(stored_idx, sub_negative[0].isSet(i));
                negative.setValue(stored_idx + rearranged_second_offset, sub_negative[1].isSet(i));
                large.setValue(stored_idx, sub_large[0].isSet(i));
                large.setValue(stored_idx + rearranged_second_offset, sub_large[1].isSet(i));
            }

            return .{
                .large = large,
                .negative = negative,
            };
        }
    };

    pub const Type = enum(u1) { individual, differential };
    pub const Storage = packed union(u30) {
        pub const Either = packed struct(u30) {
            c2: Intensity,
            c1: Intensity,
            _: u24,
        };

        pub const Individual = packed struct(u30) {
            c2: Intensity,
            c1: Intensity,

            b2: u4,
            b1: u4,
            g2: u4,
            g1: u4,
            r2: u4,
            r1: u4,

            pub fn pack(c1: Intensity, c2: Intensity, both: [2]@Vector(3, u4)) Individual {
                const first: [3]u4 = both[0];
                const second: [3]u4 = both[1];

                return .{
                    .c1 = c1,
                    .c2 = c2,

                    .r1 = first[0],
                    .g1 = first[1],
                    .b1 = first[2],
                    .r2 = second[0],
                    .g2 = second[1],
                    .b2 = second[2],
                };
            }

            pub fn unpack(individual: Individual) [2]@Vector(4, u8) {
                const factor: u8 = @divExact(std.math.maxInt(u8), std.math.maxInt(u4));

                return .{
                    .{ individual.r1 * factor, individual.g1 * factor, individual.b1 * factor, 0 },
                    .{ individual.r2 * factor, individual.g2 * factor, individual.b2 * factor, 0 },
                };
            }
        };

        pub const Differential = packed struct(u30) {
            c2: Intensity,
            c1: Intensity,

            diff_b2: i3,
            b1: u5,
            diff_g2: i3,
            g1: u5,
            diff_r2: i3,
            r1: u5,

            /// Asserts that `both[1] - both[0]` fits in an `i3`
            pub fn pack(c1: Intensity, c2: Intensity, both: [2]@Vector(3, u5)) Differential {
                const first: [3]u5 = both[0];
                const diff: [3]i3 = @as(@Vector(3, i3), @intCast(@as(@Vector(3, i8), both[1]) - both[0]));

                return .{
                    .c1 = c1,
                    .c2 = c2,

                    .r1 = first[0],
                    .g1 = first[1],
                    .b1 = first[2],
                    .diff_r2 = diff[0],
                    .diff_g2 = diff[1],
                    .diff_b2 = diff[2],
                };
            }

            pub fn unpack(differential: Differential) [2]@Vector(4, u8) {
                const uS = unpackScale;
                const r2: u5 = @bitCast(@as(i5, @bitCast(differential.r1)) +| differential.diff_r2);
                const g2: u5 = @bitCast(@as(i5, @bitCast(differential.g1)) +| differential.diff_g2);
                const b2: u5 = @bitCast(@as(i5, @bitCast(differential.b1)) +| differential.diff_b2);

                return .{
                    .{ uS(differential.r1), uS(differential.g1), uS(differential.b1), 0 },
                    .{ uS(r2), uS(g2), uS(b2), 0 },
                };
            }

            fn unpackScale(value: u5) u8 {
                return @intCast((value * @as(u16, std.math.maxInt(u8))) / std.math.maxInt(u5));
            }
        };

        either: Either,
        individual: Individual,
        differential: Differential,

        pub fn initIndividual(c1: Intensity, c2: Intensity, both: [2]@Vector(3, u4)) Storage {
            return .{ .individual = .pack(c1, c2, both) };
        }

        pub fn initDifferential(c1: Intensity, c2: Intensity, both: [2]@Vector(3, u5)) Storage {
            return .{ .differential = .pack(c1, c2, both) };
        }
    };

    pub const Packed = struct {
        pub const Quality = enum { low, medium, high };
        pub const Options = struct {
            quality: Quality,
        };

        /// Sum of the squared error of all pixels within the encoded block,
        /// higher values mean lower quality blocks. A value of 0 means the
        /// block has a perfect encoding (a.k.a not lossy)
        squared_error: u32,
        block: Block,
    };

    selectors: Selectors,
    direction: Direction,
    type: Type,
    storage: Storage,

    pub fn bufUnpack(block: Block, buffer: *[16][4]u8) void {
        const sub_intensity: [2]Intensity = .{ block.storage.either.c1, block.storage.either.c2 };
        const sub_colors: [2]@Vector(4, u8) = switch (block.type) {
            .individual => block.storage.individual.unpack(),
            .differential => block.storage.differential.unpack(),
        };

        const sub_index_pixel_shift: u2 = switch (block.direction) {
            .vertical => 0,
            .horizontal => 2,
        };

        for (0..16) |index_u| {
            const index: u4 = @intCast(index_u);
            const sub_index = ((index >> sub_index_pixel_shift) & 0b11) >> 1;
            const pixel: u4 = @intCast(std.math.rotr(u4, index, 2));

            const color = sub_colors[sub_index];
            const intensity = sub_intensity[sub_index];
            const factor: @Vector(4, u8) = @splat(intensity.values()[@intFromBool(block.selectors.large.isSet(pixel))]);
            buffer[index] = if (block.selectors.negative.isSet(pixel)) color -| factor else color +| factor;
        }
    }

    pub fn pack(pixels: *const [16][4]u8, opts: Packed.Options) Packed {
        var best_total_error: u32 = std.math.maxInt(u32);
        var best_optimized: [2]Optimizer.Result = undefined;
        var best_direction: Block.Direction = undefined;
        var best_type: Block.Type = undefined;

        // TODO: optimize solid colors with precomputed tables

        for (std.enums.values(Block.Direction)) |bdirection| {
            next_try: for (std.enums.values(Block.Type)) |btype| {
                const sub_colors: [2][8][4]u8 = switch (bdirection) {
                    .vertical => .{
                        pixels[0..2].* ++ pixels[4..6].* ++ pixels[8..10].* ++ pixels[12..14].*,
                        pixels[2..4].* ++ pixels[6..8].* ++ pixels[10..12].* ++ pixels[14..16].*,
                    },
                    .horizontal => .{ pixels[0..8].*, pixels[8..16].* },
                };

                const max: u8 = switch (btype) {
                    .individual => std.math.maxInt(u4),
                    .differential => std.math.maxInt(u5),
                };

                var optimized: [2]Optimizer.Result = undefined;
                var total_error: u32 = 0;

                for (&sub_colors, &optimized, 0..) |*sub_color, *opt, sub_color_idx| {
                    const optimizer_opts: Optimizer.Options = .{
                        .base_color = switch (btype) {
                            .individual => null,
                            .differential => if (sub_color_idx == 1)
                                @intCast(optimized[0].scaled_block_color)
                            else
                                null,
                        },
                        .quality = opts.quality,
                        .max = max,
                    };

                    const initial_scan_delta = initial_scan_deltas.get(opts.quality);
                    const optimizer: Optimizer = .init(sub_color, optimizer_opts);
                    opt.* = optimizer.compute(optimizer_opts, initial_scan_delta) orelse continue :next_try;

                    switch (opts.quality) {
                        .low => {},
                        .medium, .high => {
                            if (opt.squared_error > 3000) refined: {
                                const new_scan_deltas = switch (opts.quality) {
                                    .low => unreachable,
                                    .medium => refined_scan_deltas.get(.medium),
                                    .high => if (opt.squared_error > 6000)
                                        highly_refined_scan_delta
                                    else
                                        refined_scan_deltas.get(.high),
                                };

                                const refined_optimized = optimizer.compute(optimizer_opts, new_scan_deltas) orelse break :refined;
                                if (refined_optimized.squared_error < opt.squared_error) opt.* = refined_optimized;
                            }
                        },
                    }

                    total_error += opt.squared_error;
                    if (total_error >= best_total_error) continue :next_try;
                }

                if (total_error < best_total_error) {
                    best_total_error = total_error;
                    best_optimized = optimized;
                    best_direction = bdirection;
                    best_type = btype;
                }
            }
        }

        return .{
            .squared_error = best_total_error,
            .block = .{
                .selectors = .merge(
                    best_direction,
                    .{best_optimized[0].large, best_optimized[1].large},
                    .{best_optimized[0].negative, best_optimized[1].negative}, 
                ),
                .direction = best_direction,
                .type = best_type,
                .storage = switch (best_type) {
                    .individual => .initIndividual(
                        best_optimized[0].intensity,
                        best_optimized[1].intensity,
                        .{@intCast(best_optimized[0].scaled_block_color), @intCast(best_optimized[1].scaled_block_color)},
                    ),
                    .differential => .initDifferential(
                        best_optimized[0].intensity,
                        best_optimized[1].intensity,
                        .{@intCast(best_optimized[0].scaled_block_color), @intCast(best_optimized[1].scaled_block_color)},
                    ),
                },
            },
        };
    }

    const initial_scan_deltas: std.EnumArray(Packed.Quality, []const i8) = .init(.{
        .low = &.{0},
        .medium = &.{ -1, 0, -1 },
        .high = &.{ -4, -3, -2, -1, 0, 1, 2, 3, 4 },
    });

    const refined_scan_deltas: std.EnumArray(Packed.Quality, []const i8) = .init(.{
        .low = &.{},
        .medium = &.{ -3, -2, 2, 3 },
        .high = &.{ -5, 5 },
    });

    const highly_refined_scan_delta: []const i8 = &.{ -8, -7, -6, -5, 5, 6, 7, 8 };
};

const Optimizer = struct {
    pub const Options = struct {
        base_color: ?@Vector(3, u5),
        quality: Block.Packed.Quality,
        max: u8,
    };

    pub const Result = struct {
        block_color: @Vector(3, u8),
        scaled_block_color: @Vector(3, u8),
        intensity: Intensity,
        large: std.bit_set.IntegerBitSet(8),
        negative: std.bit_set.IntegerBitSet(8),
        squared_error: u32,
    };

    pixels: *const [8][4]u8,
    average_color: @Vector(4, u8),
    scaled_average_color: @Vector(4, u8),
    /// Sorted if needed
    luma: [8]u16,
    /// When sorted, this will contain the true pixel index of each luma value.
    luma_indices: [8]u8,

    const LumaSortContext = struct {
        luma: *[8]u16,
        luma_indices: *[8]u8,

        pub fn lessThan(ctx: LumaSortContext, a: usize, b: usize) bool {
            return ctx.luma[a] < ctx.luma[b]; 
        }

        pub fn swap(ctx: LumaSortContext, a: usize, b: usize) void {
            std.mem.swap(u8, &ctx.luma_indices[a], &ctx.luma_indices[b]);
            std.mem.swap(u16, &ctx.luma[a], &ctx.luma[b]);
        }
    };

    pub fn init(pixels: *const [8][4]u8, opts: Optimizer.Options) Optimizer {
        const luma: [8]u16, const luma_indices: [8]u8, const average_color: @Vector(4, u16) = blk: {
            var luma: [8]u16 = undefined;
            var luma_indices: [8]u8 = undefined;
            var average_color: @Vector(4, u16) = @splat(0.0);

            for (pixels, &luma, &luma_indices, 0..) |pixel, *l, *l_i, i| {
                average_color += pixel;

                const pixel_rgb: @Vector(3, u16) = pixel[0..3].*;
                l.* = @reduce(.Add, pixel_rgb);
                l_i.* = @intCast(i);
            }

            average_color /= @splat(pixels.len);

            const sort_ctx: LumaSortContext = .{ .luma = &luma, .luma_indices = &luma_indices };
            std.mem.sortUnstableContext(0, luma.len, sort_ctx);

            break :blk .{ luma, luma_indices, average_color };
        };

        const max_u8: @Vector(4, u16) = @splat(std.math.maxInt(u8));
        const max: @Vector(4, u16) = @splat(opts.max);
        const scaled_average_color: @Vector(4, u8) = @intCast((average_color * max) / max_u8);

        return .{
            .pixels = pixels,
            .average_color = @as(@Vector(4, u8), @intCast(average_color)),
            .luma = luma,
            .luma_indices = luma_indices,
            .scaled_average_color = scaled_average_color,
        };
    }

    pub fn compute(optimizer: Optimizer, opts: Optimizer.Options, scan_delta: []const i8) ?Optimizer.Result {
        var maybe_best: ?Solution.Result = null;
        var best_scaled_block_color: @Vector(3, u8) = undefined;
        var best_block_color: @Vector(3, u8) = undefined;

        const zero: @Vector(3, u8) = @splat(0);
        const max_u8: @Vector(3, u8) = @splat(std.math.maxInt(u8));
        const max: @Vector(3, u8) = @splat(opts.max);
        const scaled_avg_color_rgb: @Vector(3, u8) = .{optimizer.scaled_average_color[0], optimizer.scaled_average_color[1], optimizer.scaled_average_color[2]};
        const avg_color_rgb: @Vector(3, u8) = .{optimizer.average_color[0], optimizer.average_color[1], optimizer.average_color[2]};

        find_best: for (scan_delta) |db| {
            const bb = @as(i16, optimizer.scaled_average_color[2]) + db;

            if (bb < 0) continue;
            if (bb > opts.max) break;

            for (scan_delta) |dg| {
                const bg = @as(i16, optimizer.scaled_average_color[1]) + dg;

                if (bg < 0) continue;
                if (bg > opts.max) break;

                for (scan_delta) |dr| {
                    const br = @as(i16, optimizer.scaled_average_color[0]) + dr;
                    
                    if (br < 0) continue;
                    if (br > opts.max) break;

                    const scaled_block_color: @Vector(3, u8) = .{@intCast(br), @intCast(bg), @intCast(bb)};
                    const block_color: @Vector(3, u8) = @intCast((@as(@Vector(3, u16), scaled_block_color) * max_u8) / max);

                    if (opts.base_color) |base| {
                        const diff = @as(@Vector(3, i8), @bitCast(scaled_block_color)) - base;
                        const diff_min = @reduce(.Min, diff);
                        const diff_max = @reduce(.Max, diff);

                        if (diff_min < std.math.minInt(i3) or diff_max > std.math.maxInt(i3)) continue;
                    }

                    const solution: Solution = .init(block_color, scaled_block_color); 
                    const result = switch (opts.quality) {
                        .low, .medium => solution.evaluateFast(&optimizer),
                        .high => solution.evaluate(&optimizer),
                    };

                    if(maybe_best) |*best| {
                        if (result.squared_error <= best.squared_error) {
                            best_scaled_block_color = scaled_block_color;
                            best_block_color = block_color;
                            best.* = result;
                        } else continue;
                    } else {
                        best_scaled_block_color = scaled_block_color;
                        best_block_color = block_color;
                        maybe_best = result;
                    }
                    
                    if (maybe_best.?.squared_error == 0) break :find_best;

                    const max_refinement_trials: u8 = switch (opts.quality) {
                        .low => 2,
                        .medium, .high => if ((dr | dg | db) == 0) 4 else 2,
                    };

                    for (0..max_refinement_trials) |_| {
                        const best = maybe_best.?;
                        const intensities = best.intensity.values();

                        var delta_sum: @Vector(3, i16) = @splat(0);
                        
                        for (0..optimizer.pixels.len) |pidx| {
                            const intensity: @Vector(3, u8) = @splat(intensities[@intFromBool(best.large.isSet(pidx))]);
                            delta_sum += @as(@Vector(3, i16), if (best.negative.isSet(pidx)) block_color -| intensity else block_color +| intensity) - block_color;
                        }

                        if (@reduce(.And, delta_sum == zero)) break;

                        const avg_delta: @Vector(3, i16) = delta_sum / @as(@Vector(3, i16), @splat(optimizer.pixels.len));

                        const refined_block_color: @Vector(3, u8) = @intCast(std.math.clamp(avg_color_rgb -| avg_delta, zero, max_u8));
                        const refined_scaled_block_color: @Vector(3, u8) = @intCast((@as(@Vector(3, u16), refined_block_color) * max) / max_u8);

                        if (opts.base_color) |base| {
                            const diff = @as(@Vector(3, i8), @bitCast(refined_scaled_block_color)) - base;
                            const diff_min = @reduce(.Min, diff);
                            const diff_max = @reduce(.Max, diff);

                            if (diff_min < std.math.minInt(i3) or diff_max > std.math.maxInt(i3)) break;
                        }

                        if (@reduce(.And, refined_scaled_block_color == scaled_block_color)) break;
                        if (@reduce(.And, refined_scaled_block_color == best_scaled_block_color)) break;
                        if (@reduce(.And, refined_scaled_block_color == scaled_avg_color_rgb)) break;

                        const refined_solution: Solution = .init(refined_block_color, refined_scaled_block_color); 
                        const refined_result = switch (opts.quality) {
                            .low, .medium => refined_solution.evaluateFast(&optimizer),
                            .high => refined_solution.evaluate(&optimizer),
                        };

                        if (refined_result.squared_error < best.squared_error) {
                            best_scaled_block_color = refined_scaled_block_color;
                            best_block_color = refined_block_color;
                            maybe_best = refined_result;
                        }
                    }
                }
            }
        }

        return if (maybe_best) |best| .{
            .intensity = best.intensity,
            .block_color = best_block_color,
            .scaled_block_color = best_scaled_block_color,
            .large = best.large,
            .negative = best.negative,
            .squared_error = best.squared_error,
        } else null;
    }

    pub const Solution = struct {
        pub const Result = struct {
            pub const Set = std.bit_set.IntegerBitSet(8);

            squared_error: u32,
            intensity: Intensity,
            large: Set,
            negative: Set,
        };

        scaled_block_color: @Vector(3, u8),
        block_color: @Vector(3, u8),

        pub fn init(block_color: @Vector(3, u8), scaled_block_color: @Vector(3, u8)) Solution {
            return .{
                .block_color = block_color,
                .scaled_block_color = scaled_block_color,
            };
        }

        pub fn evaluate(solution: Solution, optimizer: *const Optimizer) Solution.Result {
            var best_error: u32 = std.math.maxInt(u32);
            var best_intensity: Intensity = undefined;
            // NOTE: not in ETC layout (top->bottom)
            var best_large: std.bit_set.IntegerBitSet(8) = undefined;
            var best_negative: std.bit_set.IntegerBitSet(8) = undefined;

            next_intensity: for (std.enums.values(Intensity)) |intensity| {
                const colors = intensity.allSelectors(solution.block_color);

                var total_error: u32 = 0;
                var large: std.bit_set.IntegerBitSet(8) = .empty;
                var negative: std.bit_set.IntegerBitSet(8) = .empty;
                
                for (optimizer.pixels, 0..) |*pixel, i| {
                    const pixel_rgb: @Vector(3, u8) = pixel[0..3].*;
                    const best_err: Intensity.Selector, const best_selector_err: u32 = blk: {
                        var best_selector_err: u32 = std.math.maxInt(u32);
                        var best: Intensity.Selector = .small;

                        for (std.enums.values(Intensity.Selector)) |sel| {
                            const selector_color: @Vector(3, i32) = colors.get(sel);
                            const diff = selector_color - pixel_rgb;
                            const selector_err: u32 = @bitCast(@reduce(.Add, diff * diff));
                            
                            if (selector_err < best_selector_err) {
                                best_selector_err = selector_err;
                                best = sel;
                            }
                        }

                        break :blk .{ best, best_selector_err };
                    };

                    total_error += best_selector_err;
                    if (total_error >= best_error) continue :next_intensity;
                    
                    large.setValue(i, best_err.isLarge());
                    negative.setValue(i, best_err.isNegative());
                }

                if (total_error < best_error) {
                    best_negative = negative;
                    best_large = large;
                    best_error = total_error;
                    best_intensity = intensity;
                }
            }

            return .{
                .squared_error = best_error,
                .intensity = best_intensity,
                .large = best_large,
                .negative = best_negative,
            };
        }

        pub fn evaluateFast(solution: Solution, optimizer: *const Optimizer) Solution.Result {
            var best_error: u32 = std.math.maxInt(u32);
            var best_intensity: Intensity = undefined;
            // NOTE: not in ETC layout (top->bottom)
            var best_large: std.bit_set.IntegerBitSet(8) = undefined;
            var best_negative: std.bit_set.IntegerBitSet(8) = undefined;

            for (std.enums.values(Intensity)) |intensity| {
                const cl = intensity.allSelectorsWithLuma(solution.block_color);
                const intensity_luma_midpoints: [3]u16 = .{ cl.lumas.values[0] + cl.lumas.values[1], cl.lumas.values[1] + cl.lumas.values[2], cl.lumas.values[2] + cl.lumas.values[3] };
                const large: std.bit_set.IntegerBitSet(8), const negative: std.bit_set.IntegerBitSet(8), const total_error: u32 = if ((optimizer.luma[7] * 2) < intensity_luma_midpoints[0]) i: {
                    if (intensity_luma_midpoints[0] > optimizer.luma[7]) {
                        const min_error = @abs(@as(i16, @bitCast(intensity_luma_midpoints[0])) - @as(i16, @bitCast(optimizer.luma[7])));
                        if (min_error >= best_error) continue;
                    }
                    
                    var total_error: u32 = 0;
                    for (optimizer.pixels) |pixel| {
                        const diff = @as(@Vector(3, i32), cl.colors.get(.large_negative)) - @as(@Vector(3, u8), pixel[0..3].*);
                        total_error += @intCast(@reduce(.Add, diff * diff));
                    }

                    break :i.{ .full, .full, total_error };
                } else if ((optimizer.luma[0] * 2) >= intensity_luma_midpoints[2]) i: {
                    if (intensity_luma_midpoints[2] < optimizer.luma[0]) {
                        const min_error = @abs(@as(i16, @bitCast(intensity_luma_midpoints[2])) - @as(i16, @bitCast(optimizer.luma[0])));
                        if (min_error >= best_error) continue;
                    }
                    
                    var total_error: u32 = 0;
                    for (optimizer.pixels) |pixel| {
                        const diff = @as(@Vector(3, i32), cl.colors.get(.large)) - @as(@Vector(3, u8), pixel[0..3].*);
                        total_error += @intCast(@reduce(.Add, diff * diff));
                    }
                    break :i .{ .full, .empty, total_error };
                } else i: {
                    var large: std.bit_set.IntegerBitSet(8) = .empty;
                    var negative: std.bit_set.IntegerBitSet(8) = .empty;
                    var total_error: u32 = 0;

                    var intensity_selector: usize = 0;
                    var i: usize = 0;
                    best_intensity: for (&optimizer.luma) |luma| {
                        while (luma * 2 >= intensity_luma_midpoints[intensity_selector]) {
                            intensity_selector += 1;
                            if (intensity_selector > 2) break :best_intensity;
                        }

                        const pixel_idx = optimizer.luma_indices[i];

                        negative.setValue(pixel_idx, intensity_selector < 2);
                        large.setValue(pixel_idx, intensity_selector == 0); // non-negative large handled below

                        const pixel: @Vector(3, u8) = optimizer.pixels[pixel_idx][0..3].*;
                        const diff = @as(@Vector(3, i32), cl.colors.values[intensity_selector]) - pixel;
                        total_error += @intCast(@reduce(.Add, diff * diff));
                        i += 1;
                    }

                    for (optimizer.luma_indices[i..]) |pixel_idx| {
                        negative.setValue(pixel_idx, false);
                        large.setValue(pixel_idx, true);

                        const pixel: @Vector(3, u8) = optimizer.pixels[pixel_idx][0..3].*;
                        const diff = @as(@Vector(3, i32), cl.colors.get(.large)) - pixel;
                        total_error += @intCast(@reduce(.Add, diff * diff));
                    }

                    break :i .{ large, negative, total_error };
                };

                if (total_error < best_error) {
                    best_error = total_error;
                    best_intensity = intensity;
                    best_negative = negative;
                    best_large = large;
                }
            }

            return .{
                .squared_error = best_error,
                .intensity = best_intensity,
                .large = best_large,
                .negative = best_negative,
            };
        }
    };
};

comptime {
    _ = Block;
    _ = Optimizer;
    _ = Optimizer.Solution;
}

const std = @import("std");
