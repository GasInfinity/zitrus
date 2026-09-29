//! LZrev (reverse-LZSS) decompressor and (TODO) compressor
//!
//! As the data must be decompressed from the end, all mentions of
//! `next` byte refer to the byte at position `current - 1`.
//!
//! A summary of the structure:
//!     - Uncompressed part
//!     - Compressed part
//!         - Read a control byte and iterate each bit from MSb to LSb
//!             - 0 -> Next byte is uncompressed, copy directly to the next decompressed position.
//!             - 1 -> Next short is a range where the 4 MSb is the `length + 3` and the rest `offset + 3` from previously decompressed data
//!     - Footer
//!         - Compressed bounds w/ the 8 MSb being the total footer length and the rest being the amount of `LZrev` compressed data [32-bits]
//!         - Delta between compressed and decompressed data [32-bits]
//!
//! Based on the documentation found in GBATEK: https://problemkaputt.de/gbatek-lz-decompression-functions.htm

pub const history_len = 4096;
pub const max_window_len = 2 * history_len + Match.max_len;
pub const partially_compressed = true;

const min_match_len = 3;

pub const Footer = packed struct(u32) {
    /// Subtract this to get the end of the compressed data.
    compressed_len: u24,

    /// Subtract this to get the start of the compressed data.
    footer_len: u8,
};

pub const Control = packed struct(u8) {
    pub const Match = enum(u1) { uncompressed, dictionary };

    _: u7,
    match: Control.Match,

    pub fn next(control: Control) Control {
        return @bitCast(@as(u8, @bitCast(control)) << 1);
    }
};

pub const Match = packed struct(u16) {
    pub const min_offset = 3;
    pub const max_len = 18;
    pub const max_size = 2;

    offset_minus_three: u12,
    len_minus_three: u4,

    pub fn offset(range: Match) usize {
        return @as(usize, range.offset_minus_three) + min_match_len;
    }

    pub fn len(range: Match) usize {
        return @as(usize, range.len_minus_three) + min_match_len;
    }

    /// Asserts `writer` capacity is at least `max_size`
    pub fn write(writer: *std.Io.Writer, match: lz.Match) std.Io.Writer.Error!void {
        const encoded: Match = .{
            .offset_minus_three = @intCast(match.offset - 3),
            .len_minus_three = @intCast(match.len - 3),
        };

        // HACK: big because we reverse the bytes afterwards, i.e we compress and reverse
        try writer.writeStruct(encoded, .big);
    }
};

pub const DecompressionError = error{
    InvalidLzrevBounds,
    InvalidMatch,
    DecompressionOverflow,
};

pub const DecompressionState = extern struct {
    pub const init: DecompressionState = .{ .decompressed_index = 0, .compressed_index = 0 };

    decompressed_index: usize,
    compressed_index: usize,
};

pub fn len(compressed: []const u8) usize {
    // XXX: whether the delta is signed or unsigned is not specified.
    const delta = std.mem.readInt(u32, compressed[(compressed.len - @sizeOf(u32))..][0..4], .little);

    return @as(u32, @intCast(compressed.len)) +% delta;
}

/// Decompresses LZrev-compressed data.
///
/// `diagnostic` is filled when returning `error.DecompressionOverflow` or `error.InvalidMatch`
///
/// Asserts that decompressed is at least `len(compressed)`.
pub fn bufDecompress(decompressed: []u8, compressed: []const u8, diagnostic: ?*DecompressionState) DecompressionError!void {
    const delta = std.mem.readInt(u32, compressed[(compressed.len - @sizeOf(u32))..][0..4], .little);
    const delta_bounds: Footer = @bitCast(std.mem.readInt(u32, compressed[(compressed.len - (2 * @sizeOf(u32)))..][0..4], .little));
    const real_decompressed_len = compressed.len +% delta;

    std.debug.assert(decompressed.len >= real_decompressed_len);

    if (delta_bounds.compressed_len > compressed.len or delta_bounds.footer_len > compressed.len) return error.InvalidLzrevBounds;

    const compressed_end = compressed.len - delta_bounds.compressed_len;
    const compressed_start = compressed.len - delta_bounds.footer_len;

    var current_decompressed_index = real_decompressed_len - 1;
    var current_compressed_index = compressed_start - 1;

    errdefer {
        if (diagnostic) |diag| diag.* = .{
            .compressed_index = current_compressed_index,
            .decompressed_index = current_decompressed_index,
        };
    }

    // Copy the data we already know is not compressed.
    // NOTE: We use memmove to support decompressing in-place
    @memmove(decompressed[0..(compressed_end + 1)], compressed[0..(compressed_end + 1)]);

    decompression: while (current_compressed_index > compressed_end) {
        var current_control: Control = @bitCast(compressed[current_compressed_index]);
        current_compressed_index -= 1;

        for (0..@bitSizeOf(Control)) |_| {
            defer current_control = current_control.next();

            // We're overwriting compressed bytes!
            if (current_decompressed_index < current_compressed_index) return error.DecompressionOverflow;

            switch (current_control.match) {
                .uncompressed => {
                    decompressed[current_decompressed_index] = compressed[current_compressed_index];
                    current_compressed_index -= 1;
                    current_decompressed_index -= 1;
                },
                .dictionary => {
                    const range: Match = @bitCast(std.mem.readInt(u16, compressed[(current_compressed_index - 1)..][0..2], .little));
                    const offset = range.offset();
                    const range_len = range.len();

                    if ((current_decompressed_index + offset) >= real_decompressed_len or range_len > (current_decompressed_index + 1)) return error.InvalidMatch;

                    for (0..range_len) |_| {
                        decompressed[current_decompressed_index] = decompressed[current_decompressed_index + offset];
                        current_decompressed_index -|= 1;
                    }

                    current_compressed_index -|= 2;
                },
            }

            if (current_compressed_index <= compressed_end) {
                break :decompression;
            }
        }
    }
}

/// Asserts `buffer` is at least `max_window_len`
/// Asserts `data` is at most `std.math.maxInt(u24)`
pub fn allocCompress(gpa: std.mem.Allocator, buffer: []u8, data: []u8, opts: Compress.Options) ![]u8 {
    // NOTE: This function is basically a HACK but I will not make a separate compressor just for this :wilted_rose:
    std.debug.assert(data.len <= std.math.maxInt(u24));

    // NOTE: We have to leave some bytes uncompressed orelse we'll overwrite already existing data.
    // The compressor already keeps track of the best compressed/uncompressed ratio

    var allocating: std.Io.Writer.Allocating = try .initCapacity(gpa, data.len + (data.len + 7) / 8 + @sizeOf(u32) * 2);
    defer allocating.deinit();

    const best_consumed, const best_written = blk: {
        var rr: ReverseReader = .init(&.{}, data);
        var compress: Compress = .init(&allocating.writer, buffer, opts);
        std.debug.assert(try rr.reader.streamRemaining(&compress.writer) == data.len);
        try compress.finish();

        break :blk .{ compress.threshold.s.best_consumed, compress.threshold.s.best_written };
    };

    std.mem.reverse(u8, allocating.written());

    const compressed_with_footer_len = best_written + @sizeOf(u32) * 2;
    const compressed = if (best_written == allocating.written().len) blk: {
        // Cool if we managed to compress everything
        const footer: Footer = .{
            .compressed_len = @intCast(compressed_with_footer_len),
            .footer_len = @sizeOf(Footer) + @sizeOf(u32),
        };

        try allocating.writer.writeStruct(footer, .little);
        try allocating.writer.writeInt(u32, @intCast(best_consumed -| compressed_with_footer_len), .little);
        break :blk try allocating.toOwnedSlice();
    } else blk: {
        const uncompressed_len = (data.len - best_consumed);
        const compressed = try gpa.alloc(u8, uncompressed_len + best_written + @sizeOf(u32) * 2);
        errdefer gpa.free(compressed);

        const uncompressed = data[0..uncompressed_len];
        const written = allocating.written();
        const compressed_data = written[written.len - best_written ..][0..best_written];
        const end = uncompressed_len + compressed_data.len;

        @memcpy(compressed[0..uncompressed.len], uncompressed);
        @memcpy(compressed[uncompressed.len..][0..compressed_data.len], compressed_data);

        const footer: Footer = .{
            .compressed_len = @intCast(compressed_with_footer_len),
            .footer_len = @sizeOf(Footer) + @sizeOf(u32),
        };

        std.mem.writeInt(u32, compressed[end..][0..4], @bitCast(footer), .little);
        std.mem.writeInt(u32, compressed[(end + 4)..][0..4], @intCast(best_consumed -| compressed_with_footer_len), .little);
        break :blk compressed;
    };
    errdefer gpa.free(compressed);

    return compressed;
}

const ReverseReader = struct {
    data: []const u8,
    index: usize,
    reader: std.Io.Reader,

    pub fn init(buffer: []u8, data: []u8) ReverseReader {
        return .{
            .data = data,
            .index = data.len,
            .reader = .{
                .vtable = &.{
                    .stream = stream,
                },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
        };
    }

    fn stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const rr: *ReverseReader = @alignCast(@fieldParentPtr("reader", r));
        if (rr.index == 0) return error.EndOfStream;

        var remaining: usize = @intFromEnum(limit);
        while (remaining > 0) {
            if (rr.index == 0) break;

            remaining -= 1;
            rr.index -= 1;
            try w.writeByte(rr.data[rr.index]);
        }
        return @intFromEnum(limit) - remaining;
    }
};

pub fn blockKind(block: u1) lz.Block {
    return switch (block) {
        0 => .literal,
        1 => .match,
    };
}

pub fn blockEncoding(block: lz.Block) u1 {
    return switch (block) {
        .literal => 0,
        .match => 1,
    };
}

const Compress = lz.Compress(lzrev);

test len {
    _ = len;
}

test bufDecompress {
    _ = bufDecompress;
}

// TODO: Fuzzing in 0.17 as it is broken in 0.16

const testing = std.testing;

const lzrev = @This();

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const lz = zitrus.compress.lz;
