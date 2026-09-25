//! Common Compression / Decompression of LZ-like formats because we never run out of them
//! and they are literally the same.
//!
//! Assumes all of them encode the control byte from MSb to LSb, minimum match length is 3 and maximum offset is 4099.
//!
//! Heavily based on zig's 0.16.0 flate de/compressor as the documentation to make `Reader`s and `Writer`s is lacking a lil bit.
//! I'd have liked to directly reuse a lot `std.compress.flate` but nothing is pub so those things are just imported with some minor edits.
//!
//! Note that compression cannot be flushed; it's either all or nothing as the control byte must be outputted unlike flate.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const Block = enum(u1) { literal, match };
pub const Match = struct {
    offset: u13,
    len: u17,
};

pub fn Decompress(comptime context: type) type {
    return struct {
        pub const State = union(enum) {
            header,
            main_blocks,
            match: Match,
            end,
        };

        input: *Reader,
        reader: Reader,

        state: State,
        blocks: u8,
        remaining_block_bits: std.math.Log2Int(u8),
        remaining_uncompressed: u32,
        err: ?Error,

        pub const Error = Reader.StreamError || context.Header.CheckError || error{
            InvalidMatch,
        };

        const direct_vtable: Reader.VTable = .{
            .stream = streamDirect,
            .rebase = rebaseFallible,
            .discard = discardDirect,
            .readVec = readVec,
        };

        const indirect_vtable: Reader.VTable = .{
            .stream = streamIndirect,
            .rebase = rebaseFallible,
            .discard = discardIndirect,
            .readVec = readVec,
        };

        pub fn init(input: *Reader, buffer: []u8) DecompressSelf {
            if (buffer.len != 0) std.debug.assert(buffer.len >= context.max_window_len);

            return .{
                .input = input,
                .reader = .{
                    .vtable = if (buffer.len == 0) &direct_vtable else &indirect_vtable,
                    .buffer = buffer,
                    .seek = 0,
                    .end = 0,
                },
                .state = .header,
                .blocks = 0,
                .remaining_block_bits = 0,
                .remaining_uncompressed = 0,
                .err = null,
            };
        }

        fn rebaseFallible(r: *Reader, capacity: usize) Reader.RebaseError!void {
            rebase(r, capacity);
        }

        fn rebase(r: *Reader, capacity: usize) void {
            std.debug.assert(capacity <= r.buffer.len - context.history_len);
            std.debug.assert(r.end + capacity > r.buffer.len);

            const discarded = @min(r.seek, r.end - context.history_len);
            const keep = r.buffer[discarded..r.end];
            @memmove(r.buffer[0..keep.len], keep);
            r.end = keep.len;
            r.seek -= discarded;
        }

        fn discardIndirect(r: *Reader, limit: std.Io.Limit) Reader.Error!usize {
            const d: *DecompressSelf = @alignCast(@fieldParentPtr("reader", r));
            if (r.end + context.history_len > r.buffer.len) rebase(r, context.history_len);
            var writer: Writer = .{
                .buffer = r.buffer,
                .end = r.end,
                .vtable = &.{
                    .drain = Writer.unreachableDrain,
                },
            };
            {
                defer r.end = writer.end;
                _ = d.streamFallible(&writer, .limited(writer.buffer.len - writer.end)) catch |err| switch (err) {
                    error.WriteFailed => unreachable,
                    else => |e| return e,
                };
            }
            const n = limit.minInt(r.end - r.seek);
            r.seek += n;
            return n;
        }

        fn streamIndirect(r: *Reader, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
            _ = limit;
            _ = w;
            const d: *DecompressSelf = @alignCast(@fieldParentPtr("reader", r));
            return d.streamIndirectInner();
        }

        fn discardDirect(r: *Reader, limit: std.Io.Limit) Reader.Error!usize {
            if (r.end + context.history_len > r.buffer.len) rebase(r, context.history_len);
            var writer: Writer = .{
                .buffer = r.buffer,
                .end = r.end,
                .vtable = &.{
                    .drain = Writer.Discarding.drain,
                    .sendFile = Writer.Discarding.sendFile,
                },
            };
            defer {
                std.debug.assert(writer.end != 0);
                r.end = writer.end;
                r.seek = r.end;
            }
            const n = r.stream(&writer, limit) catch |err| switch (err) {
                error.WriteFailed => unreachable,
                else => |e| return e,
            };
            std.debug.assert(n <= @intFromEnum(limit));
            return n;
        }

        fn streamDirect(r: *Reader, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
            const d: *DecompressSelf = @alignCast(@fieldParentPtr("reader", r));
            return d.streamFallible(w, limit);
        }

        fn readVec(r: *Reader, data: [][]u8) Reader.Error!usize {
            _ = data;
            const d: *DecompressSelf = @alignCast(@fieldParentPtr("reader", r));
            return d.streamIndirectInner();
        }

        fn streamIndirectInner(d: *DecompressSelf) Reader.Error!usize {
            const r = &d.reader;
            if (r.buffer.len - r.end < context.history_len) rebase(r, context.history_len);
            var writer: Writer = .{
                .buffer = r.buffer,
                .end = r.end,
                .vtable = &.{
                    .drain = Writer.unreachableDrain,
                    .rebase = Writer.unreachableRebase,
                },
            };
            defer r.end = writer.end;
            _ = streamFallible(d, &writer, .limited(writer.buffer.len - writer.end)) catch |err| switch (err) {
                error.WriteFailed => unreachable,
                else => |e| return e,
            };
            return 0;
        }

        fn streamFallible(d: *DecompressSelf, w: *Writer, limit: std.Io.Limit) Reader.StreamError!usize {
            return d.streamInner(w, limit) catch |err| switch (err) {
                error.EndOfStream => if (d.state == .end)
                    return error.EndOfStream
                else {
                    d.err = error.EndOfStream;
                    return error.EndOfStream;
                },
                error.WriteFailed => return error.WriteFailed,
                else => {
                    d.err = err;
                    return error.ReadFailed;
                },
            };
        }

        fn streamInner(d: *DecompressSelf, w: *Writer, limit: std.Io.Limit) (Error || Reader.StreamError)!usize {
            const in = d.input;
            var remaining: usize = @intFromEnum(limit);

            st: switch (d.state) {
                .header => {
                    const hdr = try context.Header.take(in);
                    try hdr.check();
                    d.remaining_uncompressed = hdr.uncompressed_len;
                    d.state = .main_blocks;
                    continue :st d.state;
                },
                .main_blocks => {
                    while (remaining > 0 and d.remaining_uncompressed > 0) {
                        switch (try d.takeBlock()) {
                            .literal => {
                                try w.writeBytePreserve(context.history_len, try in.takeByte());
                                d.remaining_uncompressed -= 1;
                                remaining -= 1;
                            },
                            .match => {
                                const match = try context.Match.take(in);

                                if (match.offset > w.end or match.len > d.remaining_uncompressed) return error.InvalidMatch;
                                if (match.len > remaining) {
                                    @branchHint(.unlikely);
                                    d.state = .{ .match = match };
                                    return @intFromEnum(limit) - remaining;
                                }

                                try writeMatch(w, match);
                                d.remaining_uncompressed -= match.len;
                                remaining -= match.len;
                            },
                        }
                    }

                    if (d.remaining_uncompressed == 0) d.state = .end;
                    return @intFromEnum(limit) - remaining;
                },
                .match => |match| {
                    try writeMatch(w, match);
                    d.remaining_uncompressed -= match.len;
                    remaining -= match.len;
                    d.state = .main_blocks;
                    continue :st d.state;
                },
                .end => return error.EndOfStream,
            }
        }

        fn takeBlock(d: *DecompressSelf) !Block {
            switch (d.remaining_block_bits) {
                0 => {
                    d.blocks = try d.input.takeByte();
                    d.remaining_block_bits = 7;
                },
                else => d.remaining_block_bits -= 1,
            }

            defer d.blocks <<= 1;
            return context.blockKind(@intFromBool((d.blocks & 0x80) != 0));
        }

        fn writeMatch(w: *Writer, match: Match) Writer.Error!void {
            const dest = try w.writableSlicePreserve(context.history_len, match.len);
            const end = dest.ptr - w.buffer.ptr;
            const src = w.buffer[end - match.offset ..][0..match.len];

            // We must iterate byte by byte as we may read data previously written to. That's why
            // @memmove is not used
            for (src, dest) |s, *dst| dst.* = s;
        }

        const DecompressSelf = @This();
    };
}

pub const Lookup = struct {
    pub const hash_bits = 12;
    pub const seq_len = 3;
    pub const Seq = @Int(.unsigned, seq_len * 8);
    pub const Hash = u12;

    pub const init: Lookup = .{
        .head = @splat(.{ .value = std.math.maxInt(u12), .is_null = true }),
        .chain = undefined,
        .chain_pos = 0,
    };

    pub const OptionalIndex = packed struct(u13) {
        pub const null_bit: OptionalIndex = .{ .value = 0, .is_null = true };

        value: u12,
        is_null: bool,

        pub fn int(idx: OptionalIndex) u13 {
            return @bitCast(idx);
        }
    };

    head: [1 << hash_bits]OptionalIndex,
    chain: [4096]OptionalIndex,
    chain_pos: u12,

    pub fn hash(seq: Seq) Hash {
        // taken literally from zig's 0.16.0 `std.compress.flate`
        return @truncate((@as(u32, seq) *% 0x9E3779B1) >> (32 - hash_bits));
    }
};

const CompressOptions = struct {
    /// Perform less lookups when a match of at least this length has been found.
    good: u16,
    /// Stop when a match of at least this length has been found.
    nice: u16,
    /// Don't attempt a lazy match find when a match of at least this length has been found.
    lazy: u16,
    /// Check this many previous locations with the same hash for longer matches.
    chain: u16,

    // zig fmt: off
    pub const level_1: CompressOptions = .{ .good =  4, .nice =   8, .lazy =   0, .chain =    4 };
    pub const level_2: CompressOptions = .{ .good =  4, .nice =  16, .lazy =   0, .chain =    8 };
    pub const level_3: CompressOptions = .{ .good =  4, .nice =  32, .lazy =   0, .chain =   32 };
    pub const level_4: CompressOptions = .{ .good =  4, .nice =  16, .lazy =   4, .chain =   16 };
    pub const level_5: CompressOptions = .{ .good =  8, .nice =  32, .lazy =  16, .chain =   32 };
    pub const level_6: CompressOptions = .{ .good =  8, .nice = 128, .lazy =  16, .chain =  128 };
    pub const level_7: CompressOptions = .{ .good =  8, .nice = 128, .lazy =  32, .chain =  256 };
    pub const level_8: CompressOptions = .{ .good = 32, .nice = 258, .lazy = 128, .chain = 1024 };
    pub const level_9: CompressOptions = .{ .good = 32, .nice = 258, .lazy = 258, .chain = 4096 };
    // zig fmt: on
    pub const fastest = level_1;
    pub const default = level_6;
    pub const best = level_9;
};

pub fn Compress(comptime context: type) type {
    return struct {
        pub const Options = CompressOptions;

        const Buffered = struct {
            pub const init: Buffered = .{
                .control = 0,
                .control_rem = @bitSizeOf(u8),
                .blocks = undefined,
                .blocks_len = 0,
            };

            control: u8,
            control_rem: u8,
            blocks: [@bitSizeOf(u8) * context.Match.max_size]u8,
            blocks_len: u32,
        };

        const rebase_min_preserved = context.history_len;
        const rebase_reserved_capacity = context.Match.max_len + Lookup.seq_len;

        output: *Writer,
        writer: Writer,
        buffer: []u8,

        opts: Options,
        buffered: Buffered,
        lookup: Lookup,
        history_len: u16,

        /// It is asserted that `buffer` is at least `max_window_len` bytes.
        pub fn init(output: *Writer, buffer: []u8, opts: Options) Comp {
            std.debug.assert(buffer.len >= context.max_window_len);

            return .{
                .output = output,
                .writer = .{
                    .vtable = &.{
                        .drain = &Comp.drain,
                        .rebase = &Comp.rebase,
                        .flush = &Comp.flush,
                    },
                    .buffer = buffer,
                    .end = 0,
                },
                .buffer = buffer,

                .opts = opts,
                .buffered = .init,
                .lookup = .init,
                .history_len = 0,
            };
        }

        pub fn finish(c: *Comp) !void {
            defer c.writer = .failing;

            try c.rebaseInner(0, 1, true);
        }

        fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
            errdefer w.* = .failing;

            const c_w: *Comp = @alignCast(@fieldParentPtr("writer", w));
            const unfilled_len = w.buffer.len - w.end;
            _ = w.fixedDrain(data, splat) catch {};
            try c_w.rebaseInner(0, 1, false);
            return unfilled_len;
        }

        fn flush(w: *Writer) Writer.Error!void {
            errdefer w.* = .failing;

            const c_w: *Comp = @alignCast(@fieldParentPtr("writer", w));
            try c_w.rebaseInner(0, w.buffer.len - context.history_len, false);
        }

        fn rebase(w: *Writer, preserve: usize, capacity: usize) Writer.Error!void {
            errdefer w.* = .failing;

            const c_w: *Comp = @alignCast(@fieldParentPtr("writer", w));
            try c_w.rebaseInner(preserve, capacity, false);
        }

        fn rebaseInner(c: *Comp, preserve: usize, capacity: usize, is_finish: bool) Writer.Error!void {
            std.debug.assert(@max(preserve, rebase_min_preserved) + capacity <= c.buffer.len);

            const w = &c.writer;
            const buffered = w.buffered();

            const start: usize = c.history_len;
            const hashable_len = buffered.len -| (Lookup.seq_len - 1);
            const matching_end = if (!is_finish)
                buffered.len - rebase_reserved_capacity - (preserve -| context.history_len)
            else
                hashable_len;

            var i = start;
            var last_unmatched = i;

            var seq: Lookup.Seq = initial_seq: {
                if (i >= hashable_len) {
                    @branchHint(.unlikely);
                    std.debug.assert(i >= matching_end);
                    break :initial_seq undefined; // Unused
                }

                break :initial_seq std.mem.readInt(
                    @Int(.unsigned, (Lookup.seq_len - 1) * 8),
                    buffered[start..][0..(Lookup.seq_len - 1)],
                    .big,
                );
            };

            while (i < matching_end) {
                var match_start = i;
                seq <<= 8;
                seq |= buffered[i + (Lookup.seq_len - 1)];

                var match = c.matchAndAddHash(i, Lookup.hash(seq), 2, c.opts.chain, c.opts.good);
                i += 1;

                if (match.len < 3) continue;

                var match_unadded = match.len - 1;
                lazy: {
                    if (match.len >= c.opts.lazy) break :lazy;
                    if (match.len >= c.writer.buffered()[i..].len) {
                        @branchHint(.unlikely); // Only end of stream
                        break :lazy;
                    }

                    var chain = c.opts.chain;
                    var good = c.opts.good;
                    if (match.offset >= context.Match.min_offset and match.len >= good) {
                        chain >>= 2;
                        good = std.math.maxInt(u8); // Reduce only once
                    }

                    seq <<= 8;
                    seq |= buffered[i + (Lookup.seq_len - 1)];
                    const lazy = c.matchAndAddHash(i, Lookup.hash(seq), match.len, chain, good);
                    match_unadded -= 1;
                    i += 1;

                    if (lazy.offset >= context.Match.min_offset and lazy.len > match.len) {
                        match_start += 1;
                        match = lazy;
                        match_unadded = match.len - 1;
                    }
                }

                if (match.offset < context.Match.min_offset) continue;

                std.debug.assert(i + match_unadded == match_start + match.len);
                std.debug.assert(std.mem.eql(
                    u8,
                    buffered[match_start..][0..match.len],
                    buffered[match_start - match.offset ..][0..match.len],
                )); // This assert also seems to help codegen.

                try c.outputBytes(buffered[last_unmatched..match_start]);
                try c.outputMatch(match);
                last_unmatched = match_start + match.len;

                while (i < hashable_len) {
                    seq <<= 8;
                    seq |= buffered[i + (Lookup.seq_len - 1)];
                    c.addHash(i, Lookup.hash(seq));
                    i += 1;

                    match_unadded -= 1;
                    if (match_unadded == 0) break;
                } else {
                    @branchHint(.unlikely);
                    // `c.history_end_unhashed` is set down below
                    break;
                }
                std.debug.assert(i == match_start + match.len);
            }

            if (is_finish) {
                try c.outputBytes(buffered[last_unmatched..]);
                c.buffered.control <<= @truncate(c.buffered.control_rem);
                try c.finishBlocks();
            } else {
                try c.outputBytes(buffered[last_unmatched..i]);
            }

            c.history_len = @min(i, context.history_len);
            const preserved = buffered[i - c.history_len ..];
            std.debug.assert(preserved.len >= @max(rebase_min_preserved, preserve));
            @memmove(buffered[0..preserved.len], preserved);
            w.end = preserved.len;
        }

        fn addHash(c: *Comp, i: usize, hash: Lookup.Hash) void {
            std.debug.assert(hash == Lookup.hash(std.mem.readInt(Lookup.Seq, c.writer.buffer[i..][0..Lookup.seq_len], .big)));

            const l = &c.lookup;
            l.chain_pos +%= 1;

            const replaced_i, const no_replace = @subWithOverflow(i, context.history_len);
            if (no_replace == 0) {
                @branchHint(.likely);
                const replaced_seq = std.mem.readInt(Lookup.Seq, c.writer.buffer[replaced_i..][0..Lookup.seq_len], .big);

                const replaced_h: Lookup.Hash = Lookup.hash(replaced_seq);
                l.head[replaced_h].is_null = l.head[replaced_h].is_null or
                    l.head[replaced_h].int() == l.chain_pos;
            }

            const prev_chain_index = l.head[hash];
            l.chain[l.chain_pos] = @bitCast((l.chain_pos -% prev_chain_index.value) |
                (prev_chain_index.int() & Lookup.OptionalIndex.null_bit.int())); // Preserves null
            l.head[hash] = .{ .value = l.chain_pos, .is_null = false };
        }

        fn betterMatchLen(old: u17, prev: []const u8, bytes: []const u8) u17 {
            std.debug.assert(old < @min(bytes.len, context.Match.max_len));
            std.debug.assert(prev.len >= bytes.len);
            std.debug.assert(bytes.len >= 3);

            var i: u17 = 0;
            const Blk = @Int(.unsigned, @min(std.math.divCeil(
                comptime_int,
                std.math.ceilPowerOfTwoAssert(usize, @bitSizeOf(usize)),
                8,
            ) catch unreachable, context.Match.max_len - 2) * 8);

            if (bytes.len < context.Match.max_len) {
                @branchHint(.unlikely); // Only end of stream

                while (bytes[i..].len >= @sizeOf(Blk)) {
                    const a = std.mem.readInt(Blk, prev[i..][0..@sizeOf(Blk)], .little);
                    const b = std.mem.readInt(Blk, bytes[i..][0..@sizeOf(Blk)], .little);
                    const diff = a ^ b;
                    if (diff != 0) {
                        @branchHint(.likely);
                        i += @ctz(diff) / 8;
                        return i;
                    }
                    i += @sizeOf(Block);
                }

                while (i != bytes.len and prev[i] == bytes[i]) {
                    i += 1;
                }
                std.debug.assert(i <= context.Match.max_len);
                return i;
            }

            if (old >= @sizeOf(Blk)) {
                // Check that a longer end is present, otherwise the match is always worse
                const a = std.mem.readInt(Blk, prev[old + 1 - @sizeOf(Blk) ..][0..@sizeOf(Blk)], .little);
                const b = std.mem.readInt(Blk, bytes[old + 1 - @sizeOf(Blk) ..][0..@sizeOf(Blk)], .little);
                std.debug.assert(i < context.Match.max_len);
                if (a != b) return i;
            }

            while (true) {
                const a = std.mem.readInt(Blk, prev[i..][0..@sizeOf(Blk)], .little);
                const b = std.mem.readInt(Blk, bytes[i..][0..@sizeOf(Blk)], .little);
                const diff = a ^ b;
                if (diff != 0) {
                    i += @ctz(diff) / 8;
                    return i;
                }
                i += @sizeOf(Blk);
                if (i == @sizeOf(Blk)) break;
            }

            const a = std.mem.readInt(u16, prev[i..][0..2], .little);
            const b = std.mem.readInt(u16, bytes[i..][0..2], .little);
            const diff = a ^ b;
            i += @ctz(diff) / 8;
            std.debug.assert(i <= context.Match.max_len);
            return i;
        }

        fn matchAndAddHash(c: *Comp, i: usize, h: Lookup.Hash, gt: u17, max_chain: u16, good_: u16) Match {
            const l = &c.lookup;
            const buffered = c.writer.buffered();

            var chain_limit = max_chain;
            var best_dist: u12 = undefined;
            var best_len = gt;
            const nice = @min(context.Match.max_len, c.opts.nice, buffered[i..].len);
            var good = good_;

            search: {
                if (l.head[h].is_null) break :search;
                var dist: u12 = l.chain_pos -% l.head[h].value;
                while (true) {
                    chain_limit -= 1;

                    const match_len = betterMatchLen(best_len, buffered[i - 1 - dist ..], buffered[i..]);
                    std.debug.assert(match_len <= context.Match.max_len);
                    if (best_dist < context.Match.min_offset or (match_len > best_len and dist >= context.Match.min_offset)) {
                        best_dist = dist;
                        best_len = match_len;
                        if (best_len >= nice) break;
                        if (best_len >= good) {
                            chain_limit >>= 2;
                            good = std.math.maxInt(u8); // Reduce only once
                        }
                    }

                    if (chain_limit == 0) break;
                    const next_chain_index = l.chain_pos -% @as(u12, @intCast(dist));

                    if (l.chain[next_chain_index].is_null) break;
                    dist, const out_of_window = @addWithOverflow(dist, l.chain[next_chain_index].value);
                    if (out_of_window == 1) break;
                }
            }

            c.addHash(i, h);
            return .{ .offset = @as(u13, best_dist) + 1, .len = best_len };
        }

        fn outputBytes(c: *Comp, bytes: []const u8) Writer.Error!void {
            std.debug.assert(c.buffered.control_rem > 0); // It must have been written before then

            var i: usize = 0;
            while (i < bytes.len) {
                const rem = bytes[i..];
                const outputting_len: u4 = @intCast(@min(c.buffered.control_rem, rem.len));
                const outputting = rem[0..outputting_len];
                std.debug.assert(c.buffered.blocks_len + outputting.len <= c.buffered.blocks.len);

                @memcpy(c.buffered.blocks[c.buffered.blocks_len..][0..outputting_len], outputting);
                c.buffered.blocks_len += outputting_len;

                c.buffered.control <<= @truncate(outputting_len);
                c.buffered.control |= @intCast((@as(u9, context.blockEncoding(.literal)) << outputting_len) -| 1);
                c.buffered.control_rem -= outputting_len;

                if (c.buffered.control_rem == 0) try c.finishBlocks();
                i += outputting_len;
            }
        }

        fn outputMatch(c: *Comp, match: Match) Writer.Error!void {
            std.debug.assert(c.buffered.control_rem > 0); // It must have been written before then
            std.debug.assert(c.buffered.blocks_len + context.Match.max_size <= c.buffered.blocks.len);

            var writer: Writer = .fixed(&c.buffered.blocks);
            writer.end = c.buffered.blocks_len;

            try context.Match.write(&writer, match);
            c.buffered.blocks_len = @intCast(writer.end);
            c.buffered.control <<= 1;
            c.buffered.control |= context.blockEncoding(.match);
            c.buffered.control_rem -= 1;

            if (c.buffered.control_rem == 0) try c.finishBlocks();
        }

        fn finishBlocks(c: *Comp) Writer.Error!void {
            try c.output.writeByte(c.buffered.control);
            try c.output.writeAll(c.buffered.blocks[0..c.buffered.blocks_len]);

            c.buffered.control = 0;
            c.buffered.control_rem = @bitSizeOf(u8);
            c.buffered.blocks_len = 0;
        }

        const Comp = @This();

        /// Does not compress data
        pub const Raw = struct {
            const only_literals = @as(u8, context.blockEncoding(.literal)) * 0xFF;

            output: *Writer,
            writer: Writer,

            /// It is asserted that `buffer` is at least 8 bytes.
            pub fn init(output: *Writer, buffer: []u8) Raw {
                std.debug.assert(buffer.len >= 8);

                return .{
                    .output = output,
                    .writer = .{
                        .vtable = &.{
                            .drain = &Raw.drain,
                        },
                        .buffer = buffer,
                        .end = 0,
                    },
                };
            }

            /// Finishes the stream of data.
            /// After calling this, the `.writer` becomes `.failing`.
            pub fn finish(raw: *Raw) Writer.Error!void {
                defer raw.writer = .failing;

                var buffered = raw.writer.buffered();

                while (buffered.len > 0) {
                    const to_write = @min(buffered.len, 8);

                    try raw.output.writeByte(only_literals);
                    try raw.output.writeAll(buffered[0..to_write]);
                    buffered = buffered[to_write..];
                }
            }

            fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
                const r: *Raw = @fieldParentPtr("writer", w);
                const out = r.output;

                var buffered = r.writer.buffered();

                while (buffered.len >= 8) {
                    try out.writeByte(only_literals);
                    try out.writeAll(buffered[0..8]);

                    buffered = buffered[8..];
                }

                const full_data_len = Writer.countSplat(data, splat);

                if (buffered.len + full_data_len < 8) {
                    @branchHint(.unlikely);

                    @memmove(r.writer.buffer, buffered);
                    r.writer.end = buffered.len;
                    return 0;
                }

                r.writer.end = 0;

                var literals_len: usize = buffered.len;
                var literals: [8]u8 = undefined;
                @memcpy(&literals, buffered);

                var current_index: usize = 0;
                var current_data_index: usize = 0;
                var remaining_splat = splat;

                while (true) {
                    const current = data[current_index];
                    const to_fill = @min(literals.len - literals_len, current.len);

                    @memcpy(literals[literals_len..], data[current_index][current_data_index..][0..to_fill]);
                    literals_len += to_fill;

                    if (literals_len == literals.len) {
                        defer literals_len = 0;

                        try out.writeByte(only_literals);
                        try out.writeAll(&literals);
                    }

                    if (current_data_index + to_fill == current.len) {
                        const is_splat = current_index == data.len - 1;
                        current_data_index = 0;
                        current_index += @intFromBool(!is_splat);

                        if (is_splat) if (remaining_splat > 0) {
                            remaining_splat -= 1;
                        } else break;
                    } else current_data_index += to_fill;
                }

                return full_data_len - literals_len;
            }
        };
    };
}

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");
