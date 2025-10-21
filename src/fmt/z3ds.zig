/// Z3DS is a new format for compressed executables and ROMs
///
/// Based on the documentation found in https://github.com/azahar-emu/azahar/pull/1208
/// XXX: Endianness is not said explicitly, assuming little endian.
pub const magic = "Z3DS";

pub const Header = extern struct {
    magic: [4]u8 = magic.*,
    underlying_magic: [4]u8,
    version: u8,
    _reserved0: u8 = 0,
    header_size: u16,
    metadata_size: u32,
    compressed_size: u64,
    uncompressed_size: u64,
};

pub const Metadata = extern struct {
    pub const Entry = struct {
        pub const end: Entry = .{ .type = .end, .name = &.{}, .data = &.{} };

        type: Type,
        name: []const u8,
        data: []const u8,

        pub fn compressor(name: []const u8) Entry {
            return .{ .type = .binary, .name = "compressor", .data = name };
        }

        pub fn date(compression_date: []const u8) Entry {
            return .{ .type = .binary, .name = "date", .data = compression_date };
        }

        pub fn write(entry: Entry, writer: *std.Io.Writer) std.Io.Writer.Error!u8 {
            try writer.writeStruct(Metadata{
                .type = entry.type,
                .name_len = @intCast(entry.name.len),
                .data_len = @intCast(entry.data.len),
            }, .little);
            try writer.writeAll(entry.name);
            try writer.writeAll(entry.data);
        }
    };

    pub const Header = extern struct {
        version: u8,
    };

    pub const Type = enum(u8) {
        end,
        binary,
        _,
    };

    type: Type,
    name_len: u8,
    data_len: u16,
    // name: [name_len]u8,
    // data: [data_len]u8,

    pub fn iterator(reader: *std.Io.Reader, data_buffer: []u8) Iterator {
        return .{ .reader = reader, .data_buf = data_buffer };
    }

    pub const Iterator = struct {
        reader: *std.Io.Reader,
        data_buf: []u8,
        name_buf: [256]u8 = undefined,

        pub fn next(it: *Iterator) !?Entry {
            const meta = try it.reader.takeStruct(Metadata, .little);
            it.unread_data_len = meta.data_len;

            const name = it.name_buf[0..meta.name_len];
            try it.reader.readSliceAll(name);

            const data = it.data_buf[0..meta.data_len];
            try it.reader.readSliceAll(data);

            return switch (meta.type) {
                .end => null,
                _ => .{
                    .type = meta.type,
                    .name = name,
                    .data = data,
                },
            };
        }
    };
};

const std = @import("std");
