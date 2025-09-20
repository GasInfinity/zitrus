//! ExeFS reader and writer.
//!
//! The structure is pretty simple:
//!     - Header -> There's a maximum of 10 files (at least in the header),
//!       file offsets are relative to the end of the header and the corresponding
//!       hash of file `i` is stored at `9 - i`.
//!     - File data
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/ExeFS

pub const Header = extern struct {
    pub const max_files = 10;

    pub const File = extern struct {
        name: [7:0]u8,
        /// Offset in bytes from the start of the data.
        offset: u32,
        /// Size in bytes.
        size: u32,
    };

    files: [max_files]Header.File,
    _reserved0: [0x20]u8 = @splat(0),
    /// SHA256 hashes over the entire files, stored in reverse order.
    file_hashes: [max_files][0x20]u8,

    pub fn iterator(hdr: *const Header) Iterator {
        return .{
            .header = hdr,
            .current = 0,
        };
    }

    pub fn find(hdr: *const Header, name: []const u8) ?Iterator.File {
        var it = hdr.iterator();

        return f: while (it.next()) |file| {
            if (std.mem.eql(u8, file.name, name)) {
                break :f file;
            }
        } else null;
    }

    pub const Iterator = struct {
        pub const File = struct {
            name: [:0]const u8,
            /// A SHA256 hash calculated over the file contents.
            hash: *const [0x20]u8,
            /// Offset in bytes from the start of the data.
            offset: u32,
            /// Size in bytes.
            size: u32,

            /// Checks if the stored hash matches a newly computed hash of the data.
            pub fn check(file: Iterator.File, data: []const u8) bool {
                std.debug.assert(file.size == data.len);

                var data_hash: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(data, &data_hash, .{});
                return std.mem.eql(u8, file.hash, &data_hash);
            }
        };

        header: *const Header,
        current: u8,

        pub fn next(it: *Iterator) ?Iterator.File {
            if (it.current >= max_files) {
                return null;
            }

            const file = &it.header.files[it.current];
            const name = std.mem.span((&file.name).ptr);

            if (name.len == 0 or name.len >= file.name.len) {
                return null;
            }

            defer it.current += 1;

            return .{
                .name = name,
                .hash = &it.header.file_hashes[max_files - 1 - it.current],
                .offset = file.offset,
                .size = file.size,
            };
        }

        pub fn reset(it: *Iterator) void {
            it.current = 0;
        }
    };
};

pub const File = struct {
    name: []const u8,
    data: []const u8,

    pub fn fillHeaderName(file: File) [8]u8 {
        std.debug.assert(file.name < 8);
        var buf: [8]u8 = undefined;
        @memcpy(buf[0..file.name.len], file.name);
        buf[file.name.len] = 0;
        return buf;
    }
};

/// Writes an ExeFS to the specified writer.
///
/// Asserts that the amount of files is less than `Header.max_files`,
/// its file size fits in an `u32` and the accumulated size of all files
/// is less or equal than `std.math.maxInt(u32)`.
pub fn write(writer: *std.Io.Writer, files: []const File) void {
    std.debug.assert(files.len <= Header.max_files);

    var header: Header = std.mem.zeroes(Header);
    var accumulated_offset: u32 = 0;

    for (files, 0..) |file, i| {
        defer accumulated_offset += @intCast(file.data.len);

        header.files[i] = .{
            .name = file.name,
            .offset = accumulated_offset,
            .size = @intCast(file.data.len),
        };

        std.crypto.hash.sha2.Sha256.hash(file.data, &header.file_hashes[Header.max_files - 1 - i], .{});
    }

    try writer.writeStruct(header, .little);

    for (files) |file| {
        try writer.writeAll(file.data);
    }
}

// TODO: Tests

const std = @import("std");
