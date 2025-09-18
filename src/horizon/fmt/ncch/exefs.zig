/// Header of an ExeFS files as defined in https://www.3dbrew.org/wiki/ExeFS
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

    pub fn iterator(hdr: Header) Iterator {
        return .{
            .header = hdr,
            .current = 0,
        };
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
        };

        header: Header,
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
