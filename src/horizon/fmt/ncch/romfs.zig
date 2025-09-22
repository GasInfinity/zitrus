//! RomFS reader and writer.
//!
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/RomFS

pub const Header = extern struct {
    pub const min_data_alignment = 16;

    pub const HashMetaInfo = extern struct {
        hash_table_offset: u32,
        hash_table_size: u32,
        meta_table_offset: u32,
        meta_table_size: u32,
    };

    length: u32 = @sizeOf(Header),
    directory_info: HashMetaInfo,
    file_info: HashMetaInfo,
    file_data_offset: u32,
};

pub const meta = struct {
    pub const DirectoryOffset = enum(u32) {
        pub const first: DirectoryOffset = .root;

        root = 0x00,
        none = 0xFFFFFFFF,
        _,
    };

    pub const FileOffset = enum(u32) {
        pub const first: FileOffset = @enumFromInt(0);

        none = 0xFFFFFFFF,
        _,
    };

    pub const DirectoryHeader = extern struct {
        parent: DirectoryOffset,
        next_sibling: DirectoryOffset,
        first_directory: DirectoryOffset,
        first_file: FileOffset,
        next_hash_collision: DirectoryOffset,
        name_byte_len: u32,

        pub fn initEmpty(parent: DirectoryOffset, name_byte_len: u32) DirectoryHeader {
            return .{
                .parent = parent,
                .next_sibling = .none,
                .first_directory = .none,
                .first_file = .none,
                .next_hash_collision = .none,
                .name_byte_len = name_byte_len,
            };
        }
    };

    pub const FileHeader = extern struct {
        parent: DirectoryOffset,
        next_sibling: FileOffset,
        data_offset: u64 align(@sizeOf(u32)),
        data_len: u64 align(@sizeOf(u32)),
        next_hash_collision: FileOffset,
        name_byte_len: u32,

        pub fn initEmpty(parent: DirectoryOffset, name_byte_len: u32) FileHeader {
            return .{
                .parent = parent,
                .next_sibling = .none,
                .data_offset = undefined,
                .data_len = undefined,
                .next_hash_collision = .none,
                .name_byte_len = name_byte_len,
            };
        }
    };

    pub const Name = union(enum(u1)) {
        as_utf8: []const u8,
        as_utf16: []const u16,

        pub fn utf8(value: []const u8) Name {
            return .{ .as_utf8 = value };
        }

        pub fn utf16(value: []const u16) Name {
            return .{ .as_utf16 = value };
        }

        /// Calculates UTF-16 length of the name.
        ///
        /// Asserts the name is a valid utf8 or utf16 string.
        pub fn length(name: Name) usize {
            return switch (name) {
                .as_utf8 => |as_utf8| std.unicode.calcUtf16LeLen(as_utf8) catch unreachable,
                .as_utf16 => |as_utf16| as_utf16.len,
            };
        }

        /// Asserts the name is a valid utf8 or utf16 string and that the encoded string fits in the output.
        pub fn encode(name: Name, buf: []u16) usize {
            return switch (name) {
                .as_utf8 => |as_utf8| std.unicode.utf8ToUtf16Le(buf, as_utf8) catch unreachable,
                .as_utf16 => |as_utf16| blk: {
                    @memcpy(buf[0..as_utf16.len], as_utf16);
                    break :blk as_utf16.len;
                },
            };
        }
    };

    pub fn Table(comptime T: type, comptime TOffset: type) type {
        if (T != FileHeader and T != DirectoryHeader) @compileError("Can only use a metadata table with a valid header.");

        return struct {
            pub const empty: Self = .{ .raw = .empty };

            raw: std.ArrayList(u32),

            pub fn deinit(table: *Self, gpa: std.mem.Allocator) void {
                table.raw.deinit(gpa);
            }

            pub fn addOne(table: *Self, gpa: std.mem.Allocator, parent: DirectoryOffset, name: Name) !TOffset {
                const name_len = name.length();
                const name_byte_len = name_len * @sizeOf(u16);
                const total_elements = @divExact(@sizeOf(T) + std.mem.alignForward(usize, name_byte_len, @sizeOf(u32)), @sizeOf(u32));

                const offset: u32 = @intCast(table.raw.items.len * @sizeOf(u32));
                const entry = try table.raw.addManyAsSlice(gpa, total_elements);
                const entry_hdr: *T = @ptrCast(entry);
                const entry_name: []u16 = std.mem.bytesAsSlice(u16, std.mem.sliceAsBytes(entry[(@divExact(@sizeOf(T), @sizeOf(u32)))..]));

                entry_hdr.* = .initEmpty(parent, @intCast(name_byte_len));

                const last = name.encode(entry_name);
                @memset(entry_name[last..], 0x00);

                return @enumFromInt(offset);
            }

            pub fn get(table: Self, offset: TOffset) *T {
                std.debug.assert(std.mem.isAligned(@intFromEnum(offset), @alignOf(u32)));
                const aligned_offset = @divExact(@intFromEnum(offset), @sizeOf(u32));

                std.debug.assert(aligned_offset < table.raw.items.len);
                return std.mem.bytesAsValue(T, std.mem.sliceAsBytes(table.raw.items[aligned_offset..]));
            }

            pub fn getName(table: Self, offset: TOffset) []const u16 {
                const hdr = table.get(offset);
                const name_bytes = std.mem.sliceAsBytes(table.raw.items[@divExact(@intFromEnum(offset) + @sizeOf(T), @sizeOf(u32))..])[0..hdr.name_byte_len];

                return @alignCast(std.mem.bytesAsSlice(u16, name_bytes));
            }

            pub fn write(table: Self, writer: *std.Io.Writer) !void {
                if (builtin.cpu.arch.endian() == .little) {
                    try writer.writeAll(std.mem.sliceAsBytes(table.raw.items));
                } else @panic("TODO: Big endian write support");
            }

            /// Iterator over the entire table.
            pub fn iterator(table: *const Self) Iterator {
                return .{
                    .table = table,
                    .offset = .first,
                };
            }

            pub const Iterator = struct {
                table: *const Self,
                offset: TOffset,

                pub fn next(it: *Iterator) ?TOffset {
                    return switch (it.offset) {
                        .none => unreachable,
                        else => |entry| blk: {
                            if (@divExact(@intFromEnum(entry), 4) >= it.table.raw.items.len) return null;
                            const hdr = it.table.get(entry);

                            defer it.offset = @enumFromInt(@intFromEnum(it.offset) + @sizeOf(T) + std.mem.alignForward(u32, hdr.name_byte_len, @sizeOf(u32)));
                            break :blk it.offset;
                        },
                    };
                }
            };

            const Self = @This();
        };
    }

    pub fn hash(name: []const u16, parent: DirectoryOffset) u32 {
        var ohash: u32 = @intFromEnum(parent) ^ 123456789;

        for (name) |c| {
            ohash = std.math.rotr(u32, ohash, 5) ^ c;
        }

        return ohash;
    }
};

pub fn officialHashPrime(entries: u32) u32 {
    if (entries < 3) {
        return 3;
    }

    if (entries < 19) {
        return entries | 1;
    }

    var simple_prime: u32 = entries;
    check: while (true) {
        inline for (&.{ 2, 3, 5, 7, 11, 13, 17 }) |divisor| {
            if ((simple_prime % divisor) == 0) {
                simple_prime += 1;
                continue :check;
            }
        }

        return simple_prime;
    }
}

/// RomFS builder.
///
/// Remember to call `rehash` before writing!
pub const Builder = struct {
    pub const Directory = struct {
        offset: meta.DirectoryOffset,
        last_directory: meta.DirectoryOffset,
        last_file: meta.FileOffset,
    };

    directories: meta.Table(meta.DirectoryHeader, meta.DirectoryOffset),
    files: meta.Table(meta.FileHeader, meta.FileOffset),
    file_data: std.ArrayList(u8),
    directory_hashes: std.ArrayList(meta.DirectoryOffset),
    file_hashes: std.ArrayList(meta.FileOffset),
    root: Directory,

    pub fn init(gpa: std.mem.Allocator) !Builder {
        var builder: Builder = .{
            .directories = .empty,
            .files = .empty,
            .file_data = .empty,
            .directory_hashes = .empty,
            .file_hashes = .empty,
            .root = .{
                .offset = .root,
                .last_directory = .none,
                .last_file = .none,
            },
        };

        // This is the root directory
        _ = try builder.directories.addOne(gpa, .root, .utf16(&.{}));
        return builder;
    }

    pub fn deinit(builder: *Builder, gpa: std.mem.Allocator) void {
        builder.directories.deinit(gpa);
        builder.files.deinit(gpa);
        builder.directory_hashes.deinit(gpa);
        builder.file_hashes.deinit(gpa);
        builder.file_data.deinit(gpa);
    }

    pub fn addDirectory(builder: *Builder, gpa: std.mem.Allocator, parent: *Directory, name: meta.Name) !Directory {
        const new = try builder.directories.addOne(gpa, parent.offset, name);

        switch (parent.last_directory) {
            .root => unreachable,
            .none => {
                const parent_hdr = builder.directories.get(parent.offset);
                parent_hdr.first_directory = new;
            },
            _ => |sibling| {
                const sibling_hdr = builder.directories.get(sibling);
                sibling_hdr.next_sibling = new;
            },
        }

        parent.last_directory = new;
        return .{
            .offset = new,
            .last_directory = .none,
            .last_file = .none,
        };
    }

    pub fn addFile(builder: *Builder, gpa: std.mem.Allocator, parent: *Directory, name: meta.Name, data: []const u8) !void {
        const new = try builder.files.addOne(gpa, parent.offset, name);
        const new_hdr = builder.files.get(new);

        new_hdr.data_offset = @intCast(builder.file_data.items.len);
        new_hdr.data_len = @intCast(data.len);

        try builder.file_data.appendSlice(gpa, data);

        switch (parent.last_file) {
            .none => {
                const parent_hdr = builder.directories.get(parent.offset);
                parent_hdr.first_file = new;
            },
            _ => |sibling| {
                const sibling_hdr = builder.files.get(sibling);
                sibling_hdr.next_sibling = new;
            },
        }

        parent.last_file = new;
    }

    pub fn rehash(builder: *Builder, gpa: std.mem.Allocator) !void {
        inline for (&.{ &builder.directories, &builder.files }, &.{ &builder.directory_hashes, &builder.file_hashes }) |table, hash_table| {
            const hash_table_size = officialHashPrime(@intCast(table.raw.items.len));

            try hash_table.resize(gpa, hash_table_size);
            @memset(hash_table.items, .none);

            var it = table.iterator();

            while (it.next()) |entry| {
                const hdr = table.get(entry);
                const name = table.getName(entry);

                const hash = meta.hash(name, hdr.parent);
                const hash_entry = &hash_table.items[hash % hash_table_size];
                const last_entry = hash_entry.*;

                hash_entry.* = entry;

                switch (last_entry) {
                    .none => {},
                    else => |collision| hdr.next_hash_collision = collision,
                }
            }
        }
    }

    /// Writes the built RomFS.
    ///
    /// Remember to `rehash` before writing!
    pub fn write(builder: *Builder, writer: *std.Io.Writer) !void {
        // NOTE: Basically, Hdr -> DirH -> FileH -> DirM -> FileM -> FileD
        const data_offset: u32 = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directories.raw.items.len + builder.files.raw.items.len + builder.directory_hashes.items.len + builder.file_hashes.items.len));
        const aligned_data_offset = std.mem.alignForward(u32, data_offset, Header.min_data_alignment);

        try writer.writeStruct(Header{
            .length = @sizeOf(Header),
            .directory_info = .{
                .hash_table_offset = @sizeOf(Header),
                .hash_table_size = @intCast(@sizeOf(u32) * builder.directory_hashes.items.len),
                .meta_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directory_hashes.items.len + builder.file_hashes.items.len)),
                .meta_table_size = @intCast(@sizeOf(u32) * builder.directories.raw.items.len),
            },
            .file_info = .{
                .hash_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * builder.directory_hashes.items.len),
                .hash_table_size = @intCast(@sizeOf(u32) * builder.file_hashes.items.len),
                .meta_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directories.raw.items.len + builder.directory_hashes.items.len + builder.file_hashes.items.len)),
                .meta_table_size = @intCast(@sizeOf(u32) * builder.files.raw.items.len),
            },
            .file_data_offset = aligned_data_offset,
        }, .little);
        try writer.writeSliceEndian(meta.DirectoryOffset, builder.directory_hashes.items, .little);
        try writer.writeSliceEndian(meta.FileOffset, builder.file_hashes.items, .little);
        try builder.directories.write(writer);
        try builder.files.write(writer);
        try writer.splatByteAll(undefined, (aligned_data_offset - data_offset));
        try writer.writeAll(builder.file_data.items);
    }
};

test {
    if (builtin.target.os.tag == .other) {
        return error.SkipZigTest; // cannot use testing.allocator in horizon currently.
    }

    const gpa = testing.allocator;

    var builder: Builder = try .init(gpa);
    defer builder.deinit(gpa);

    var a = try builder.addDirectory(gpa, &builder.root, .utf8("A"));
    var bc = try builder.addDirectory(gpa, &a, .utf8("BC"));
    _ = try builder.addDirectory(gpa, &bc, .utf8("CD"));
    _ = try builder.addDirectory(gpa, &a, .utf8("DE"));

    try builder.addFile(gpa, &a, .utf8("ソウル・ソサエティ"), "Ahh yes, japanese\n");
    try builder.addFile(gpa, &bc, .utf8("¿qué?"), "Spanish or english, decide please\n");

    var backed_writer: std.Io.Writer.Allocating = .init(gpa);
    defer backed_writer.deinit();

    const writer = &backed_writer.writer;
    try builder.rehash(gpa);
    try builder.write(writer);

    // for (backed_writer.written()) |b| {
    //     std.debug.print("{X} ", .{b});
    // }
    // std.debug.print("\n", .{});
}

const testing = std.testing;

const builtin = @import("builtin");
const std = @import("std");
