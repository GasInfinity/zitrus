//! Common Compression / Decompression of LZ-like formats because we never run out of them
//! and they are literally the same.
//!
//! Based on the documentation found in: https://problemkaputt.de/gbatek.htm#lzdecompressionfunctions

pub const Block = enum(u1) { literal, match };
pub const Match = struct {
    offset: u13,
    len: u17,
};

// Heavily based on zig's flate decompressor as the documentation to make `Reader`s and `Writer`s is lacking a lil bit.
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

const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const std = @import("std");
