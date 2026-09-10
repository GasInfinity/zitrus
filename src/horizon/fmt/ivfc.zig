pub const Id = enum(u32) {
    /// RomFS (3 levels), master hash (L0) 32-bits, header size 64-bits (0x5C)
    romfs = 0x10000,
    /// DISA/DIFF (4 levels), master hash (L0) 64-bits, header size 32-bits (0x78)
    disa = 0x20000,
    _,
};

pub const Header = extern struct {
    pub const magic_value = "IVFC";

    magic: [magic_value.len]u8 = magic_value.*,
    id: Id,

    pub const CheckError = error{NotIvfc};
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic_value)) return error.NotIvfc;
    }
};

pub const Level = extern struct {
    logical_offset: u64,
    size: u64,
    /// In Log2
    block_size_shift: u64,

    pub fn acceptableBlockSizeShift(size: u64) u32 {
        return @intCast(@max((std.math.log2(size | 1) * 2) / 3 + 2, 9));
    }
};

pub const Parsed = struct {
    l0_size: u32,
    levels: []const Level,

    pub const ReadError = error{InvalidIvfc} || Header.CheckError;
    pub fn read(in: *Io.Reader, levels_buffer: []Level, expect: ?Id) (Io.Reader.Error || ReadError)!Parsed {
        const hdr: Header = try in.takeStruct(Header, .little);
        try hdr.check();

        if (expect) |expected| if (hdr.id != expected) {
            return error.InvalidIvfc;
        };

        const l0_size: u32, const levels: []Level = info: switch (hdr.id) {
            .romfs => {
                const l0_size = try in.takeInt(u32, .little);
                try in.readSliceEndian(Level, levels_buffer[0..3], .little);
                const hdr_size = try in.takeInt(u64, .little);
                if (hdr_size != @sizeOf(Header) + @sizeOf(u32) + @sizeOf([3]Level) + @sizeOf(u64)) return error.InvalidIvfc;
                break :info .{ l0_size, levels_buffer[0..3] };
            },
            .disa => {
                const raw_l0_size = try in.takeInt(u64, .little);
                // NOTE: This is *basically* impossible, it's 99.999999999% more likely it's just corrupt instead.
                if (raw_l0_size > std.math.maxInt(u32)) return error.InvalidIvfc;
                const l0_size: u32 = @intCast(raw_l0_size);

                try in.readSliceEndian(Level, levels_buffer[0..4], .little);
                const hdr_size = try in.takeInt(u32, .little);
                if (hdr_size != @sizeOf(Header) + @sizeOf(u64) + @sizeOf([4]Level) + @sizeOf(u32)) return error.InvalidIvfc;
                break :info .{ l0_size, levels_buffer[0..4] };
            },
            _ => return error.InvalidIvfc,
        };

        if (!std.mem.isAligned(l0_size, 0x20)) return error.InvalidIvfc;

        for (levels[0..levels.len], 0..) |hash_level, i| {
            if (i < (levels.len - 1) and !std.mem.isAlignedGeneric(u64, hash_level.size, 0x20)) return error.InvalidIvfc;
            if (hash_level.block_size_shift > 32) return error.InvalidIvfc;
        }

        for (1..levels.len) |i| {
            if (levels[i - 1].size != ((levels[i].size + (@as(u64, 1) << @intCast(levels[i].block_size_shift)) - 1) >> @intCast(levels[i].block_size_shift)) << 5) return error.InvalidIvfc;
        }

        return .{
            .l0_size = l0_size,
            .levels = levels,
        };
    }

    /// Verifies the IVFC
    ///
    /// Logical position of the reader is left unchanged.
    /// Asserts `block_buffer` is `@max(parsed.levels[i].block_size)`
    pub fn verify(parsed: Parsed, block_buffer: []u8, offsets: []const u64, reader: *Io.File.Reader) Io.File.Reader.SeekError!bool {
        const initial_offset = reader.logicalPos();

        var hashes: u32 = @intCast(parsed.l0_size / 0x20);
        var computed_hash: [0x20]u8 = undefined;
        var stored_hash: [0x20]u8 = undefined;
        for (parsed.levels, 1..) |level, level_idx| {
            for (0..hashes) |i| {
                const current_offset = i << @intCast(level.block_size_shift);
                const block_size = @as(usize, 1) << @intCast(level.block_size_shift);
                const current_size = @min(level.size - current_offset, block_size);
                const data = block_buffer[0..block_size];

                try reader.seekTo(initial_offset + offsets[level_idx - 1] + (i * 0x20));
                try reader.interface.readSliceAll(&stored_hash);
                try reader.seekTo(initial_offset + offsets[level_idx] + current_offset);
                try reader.interface.readSliceAll(data[0..current_size]);
                @memset(data[current_size..], 0x00);

                Sha256.hash(data, &computed_hash, .{});

                if (!std.mem.eql(u8, &stored_hash, &computed_hash)) return false;
            }

            hashes = @intCast(std.mem.alignForward(u64, level.size, @as(u64, 1) << @intCast(level.block_size_shift)) >> @intCast(level.block_size_shift));
        }

        try reader.seekTo(initial_offset);
        return true;
    }
};

pub const BlockHashingWriter = struct {
    err: ?anyerror,
    gpa: std.mem.Allocator,

    block_size: u64,
    block_written: u64,

    hasher: Sha256,
    hashes: std.ArrayList([0x20]u8),
    out: *Io.Writer,
    writer: Io.Writer,

    /// `buffer` must have a non-zero length
    pub fn init(gpa: std.mem.Allocator, block_size: u64, buffer: []u8, out: *Io.Writer) std.mem.Allocator.Error!BlockHashingWriter {
        return try .initCapacity(gpa, block_size, buffer, out, 0);
    }

    /// `buffer` must have a non-zero length
    pub fn initCapacity(gpa: std.mem.Allocator, block_size: u64, buffer: []u8, out: *Io.Writer, capacity: usize) std.mem.Allocator.Error!BlockHashingWriter {
        std.debug.assert(buffer.len > 0); 

        return .{
            .err = null,
            .gpa = gpa,

            .block_size = block_size,
            .block_written = 0,

            .hasher = .init(.{}),
            .hashes = try .initCapacity(gpa, capacity),
            .out = out,
            .writer = .{
                .buffer = buffer, 
                .end = 0,
                .vtable = &.{
                    .drain = drain,
                },
            },
        };
    }

    pub fn deinit(writer: *BlockHashingWriter) void {
        writer.hashes.deinit(writer.gpa); 
    }

    pub fn end(blk_w: *BlockHashingWriter) !void {
        const buffer = blk_w.writer.buffer;
        if (blk_w.writer.end > 0) try blk_w.writer.flush();
        if (blk_w.block_written == 0) return; 

        // When finishing, the hasher is weirdly filled with zeroes; not finished directly.
        @memset(buffer, 0x00);
        const hasher = &blk_w.hasher;
        const hashes =  &blk_w.hashes;
        const final_hash = try hashes.addOne(blk_w.gpa);
        
        var rem = blk_w.block_size - blk_w.block_written;
        while (rem > 0) {
            const hashing = @min(rem, buffer.len);
            hasher.update(buffer[0..hashing]);
            rem -= hashing;
        }
        hasher.final(final_hash);
        hasher.* = .init(.{});
        blk_w.block_written = 0;
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const blk_w: *BlockHashingWriter = @alignCast(@fieldParentPtr("writer", w));
        try blk_w.drainSingle(w.buffered());
        w.end = 0;

        var drained: usize = 0;
        for (data[0..data.len - 1]) |buffer| {
            try blk_w.drainSingle(buffer);
            drained += buffer.len;
        }

        for (0..splat) |_| try blk_w.drainSingle(data[data.len - 1]);
        drained += data[data.len - 1].len * splat;
        return drained;
    }

    fn drainSingle(blk_w: *BlockHashingWriter, buffer: []const u8) Io.Writer.Error!void {
        const hashes = &blk_w.hashes;
        const hasher = &blk_w.hasher;

        var current: usize = 0;
        while (current < buffer.len) {
            const block_rem = blk_w.block_size - blk_w.block_written;
            const remaining = buffer[current..];
            const hashing = @min(block_rem, remaining.len);
            blk_w.block_written += hashing;
            hasher.update(remaining[0..hashing]);

            if (blk_w.block_written == blk_w.block_size) {
                blk_w.block_written = 0;
                const hash = hashes.addOne(blk_w.gpa) catch |err| {
                    blk_w.err = err;
                    return error.WriteFailed;
                };

                hasher.final(hash);
                hasher.* = .init(.{});
            }

            current += hashing;
        }

        blk_w.out.writeAll(buffer) catch |err| {
            blk_w.err = err;
            return error.WriteFailed;
        };
    }
};

test "Writing random bytes as RomFS IVFC, verifying it afterwards"{
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var rand: std.Random.DefaultPrng = .init(std.testing.random_seed);
    const rnd = rand.random();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const size = rnd.intRangeAtMost(u32, std.math.maxInt(u16), std.math.maxInt(u20));
    const ivfc = try tmp.dir.createFile(io, "ivfc", .{ .read = true });
    defer ivfc.close(io);

    {
        const rnd_bytes = try gpa.alloc(u8, size);
        defer gpa.free(rnd_bytes);
        rnd.bytes(rnd_bytes);

        var ivfc_buffer: [512]u8 = undefined;
        var ivfc_writer = ivfc.writer(io, &ivfc_buffer);

        var inner_ivfc_buffer: [512]u8 = undefined;
        var reader: Io.Reader = .fixed(rnd_bytes);
        _ = try fmt.ncch.romfs.Ivfc.write(&ivfc_writer, &inner_ivfc_buffer, &reader, Level.acceptableBlockSizeShift(rnd_bytes.len), gpa, rnd_bytes.len);
        try ivfc_writer.interface.flush();
    }

    var ivfc_reader_buffer: [512]u8 = undefined;
    var ivfc_reader = ivfc.reader(io, &ivfc_reader_buffer);
    var levels_buffer: [3]Level = undefined;
    const parsed: Parsed = try .read(&ivfc_reader.interface, &levels_buffer, .romfs);

    const max_block_size = blk: {
        var max_block_size: usize = 0;
        for (parsed.levels) |level| max_block_size = @max(max_block_size, @as(usize, 1) << @intCast(level.block_size_shift));
        break :blk max_block_size;
    };

    const l0_start = std.mem.alignForward(usize, @sizeOf(fmt.ncch.romfs.Ivfc), 0x20);
    const l3_start = std.mem.alignForward(u64, l0_start + parsed.l0_size, @as(usize, 1) << @intCast(parsed.levels[2].block_size_shift));
    const l1_start = std.mem.alignForward(u64, l3_start + parsed.levels[2].size, @as(usize, 1) << @intCast(parsed.levels[0].block_size_shift));
    const l2_start = std.mem.alignForward(u64, l1_start + parsed.levels[0].size, @as(usize, 1) << @intCast(parsed.levels[1].block_size_shift));

    // L0...L3
    const offsets: []const u64 = &.{
        l0_start,
        l1_start,
        l2_start,
        l3_start,
    };

    const block_buffer = try gpa.alloc(u8, max_block_size);
    defer gpa.free(block_buffer);

    try ivfc_reader.seekTo(0);
    if (!try parsed.verify(block_buffer, offsets, &ivfc_reader)) {
        return error.Failed;
    }
}

const std = @import("std");
const zitrus = @import("zitrus");
const fmt = zitrus.horizon.fmt;

const Io = std.Io;
const Sha256 = std.crypto.hash.sha2.Sha256;
