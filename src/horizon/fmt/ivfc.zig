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
};

pub const Parsed = struct {
    l0_size: u64,
    levels: []const Level,

    pub const ReadError = error{InvalidIvfc} || Header.CheckError;
    pub fn read(in: *Io.Reader, levels_buffer: []Level) (Io.Reader.Error || ReadError)!Parsed {
        std.debug.assert(levels_buffer >= 4);
        const hdr: Header = try in.takeStruct(Header, .little);
        try hdr.check();

        const l0_size, const levels = info: switch (hdr.id) {
            .romfs => {
                const l0_size = try in.takeInt(u32, .little);
                try in.readSliceEndian(Level, levels_buffer[0..3], .little);
                const hdr_size = try in.takeInt(u64, .little);
                if (hdr_size != @sizeOf(Header) + @sizeOf(u32) + @sizeOf([3]Level) + @sizeOf(u64)) return error.InvalidIvfc;
                break :info .{ l0_size, levels_buffer[0..3] };
            },
            .disa => {
                const l0_size = try in.takeInt(u64, .little);
                try in.readSliceEndian(Level, levels_buffer[0..4], .little);
                const hdr_size = try in.takeInt(u32, .little);
                if (hdr_size != @sizeOf(Header) + @sizeOf(u64) + @sizeOf([4]Level) + @sizeOf(u32)) return error.InvalidIvfc;
                break :info .{ l0_size, levels_buffer[0..4] };
            },
            else => return error.UnknownId,
        };

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

        var hashes: u64 = (parsed.l0_size / 0x20);
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

                std.crypto.hash.sha2.Sha256.hash(data, &computed_hash, .{});

                if (!std.mem.eql(u8, &stored_hash, &computed_hash)) return false;
            }

            hashes = std.mem.alignForward(u64, level.size, @as(u64, 1) << @intCast(level.block_size_shift)) >> @intCast(level.block_size_shift);
        }

        try reader.seekTo(initial_offset);
        return true;
    }
};

const std = @import("std");
const Io = std.Io;
