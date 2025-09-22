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

const minimum_encoded_range_value = 3;

pub const EncodedDeltaBounds = packed struct(u32) {
    /// Subtract this to get the end of the compressed data.
    compressed_len: u24,

    /// Subtract this to get the start of the compressed data.
    footer_len: u8,
};

pub const Control = packed struct(u8) {
    pub const Match = enum(u1) { uncompressed, dictionary };

    _: u7,
    match: Match,

    pub fn next(control: Control) Control {
        return @bitCast(@as(u8, @bitCast(control)) << 1);
    }
};

pub const PreviousRange = packed struct(u16) {
    offset_minus_three: u12,
    len_minus_three: u4,

    pub fn offset(range: PreviousRange) usize {
        return @as(usize, range.offset_minus_three) + minimum_encoded_range_value;
    }

    pub fn len(range: PreviousRange) usize {
        return @as(usize, range.len_minus_three) + minimum_encoded_range_value;
    }
};

pub const SlidingWindow = struct {
    pub const max_len = 0x1000;

    pub const empty: SlidingWindow = .{
        .window = undefined,
        .position = 0,
        .len = 0,
    };

    window: [max_len]u8,
    position: u16,
    len: u16,

    /// Adds a new byte to the sliding window, overwrites any previous bytes if needed.
    pub fn slide(sliding: *SlidingWindow, byte: u8) void {
        if (sliding.len < max_len) {
            sliding.window[sliding.len] = byte;
            sliding.len += 1;
            return;
        }

        sliding.window[sliding.position] = byte;
        sliding.position += 1;
    }

    pub fn findAvailable(sliding: *SlidingWindow) void {
        return sliding.len > 3;
    }
};

pub const DecompressionError = error{
    InvalidLzrevBounds,
    InvalidLzrevDictionaryRange,
};

pub fn len(compressed: []const u8) usize {
    // XXX: whether the delta is signed or unsigned is not specified.
    const delta = std.mem.readInt(u32, compressed[(compressed.len - @sizeOf(u32))..][0..4], .little);

    return compressed.len +% delta;
}

/// Decompresses LZrev-compressed data.
///
/// Asserts that decompressed is at least `len(compressed)`.
pub fn bufDecompress(decompressed: []u8, compressed: []const u8) DecompressionError!void {
    const delta = std.mem.readInt(u32, compressed[(compressed.len - @sizeOf(u32))..][0..4], .little);
    const delta_bounds: EncodedDeltaBounds = @bitCast(std.mem.readInt(u32, compressed[(compressed.len - (2 * @sizeOf(u32)))..][0..4], .little));
    const real_decompressed_len = compressed.len +% delta;

    std.debug.assert(decompressed.len >= real_decompressed_len);

    if (delta_bounds.compressed_len > compressed.len or delta_bounds.footer_len > compressed.len) {
        return error.InvalidLzrevBounds;
    }

    const compressed_end = compressed.len - delta_bounds.compressed_len;
    const compressed_start = compressed.len - delta_bounds.footer_len;

    var current_decompressed_index = real_decompressed_len - 1;
    var current_compressed_index = compressed_start - 1;

    // Copy the data we already know is not compressed.
    @memcpy(decompressed[0..(compressed_end + 1)], compressed[0..(compressed_end + 1)]);

    decompression: while (current_compressed_index > compressed_end) {
        var current_control: Control = @bitCast(compressed[current_compressed_index]);
        current_compressed_index -= 1;

        for (0..@bitSizeOf(Control)) |_| {
            defer current_control = current_control.next();

            switch (current_control.match) {
                .uncompressed => {
                    decompressed[current_decompressed_index] = compressed[current_compressed_index];
                    current_compressed_index -= 1;
                    current_decompressed_index -= 1;
                },
                .dictionary => {
                    const range: PreviousRange = @bitCast(std.mem.readInt(u16, compressed[(current_compressed_index - 1)..][0..2], .little));
                    const offset = range.offset();

                    if ((current_decompressed_index + offset) >= real_decompressed_len or range.len() > current_decompressed_index) {
                        return error.InvalidLzrevDictionaryRange;
                    }

                    for (0..range.len()) |_| {
                        decompressed[current_decompressed_index] = decompressed[current_decompressed_index + offset];
                        current_decompressed_index -= 1;
                    }

                    current_compressed_index -= 2;
                },
            }

            if (current_compressed_index <= compressed_end) {
                break :decompression;
            }
        }
    }
}

// TODO: compression, try not to bruteforce it pls

test SlidingWindow {
    var sliding: SlidingWindow = .empty;

    for (0..SlidingWindow.max_len) |i| {
        sliding.slide(@truncate(i));
    }

    try testing.expect(sliding.position == 0);
    try testing.expect(sliding.len == SlidingWindow.max_len);

    sliding.slide(69);

    try testing.expect(sliding.position == 1);
    try testing.expect(sliding.window[0] == 69);
}

test len {
    _ = len;
}

test bufDecompress {
    _ = bufDecompress;
}

const testing = std.testing;

const builtin = @import("builtin");
const std = @import("std");
