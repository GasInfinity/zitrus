//! **S**orted **Arc**hive
//!
//! Yet another archive format, this time without directory support!
//!
//! Files MUST be sorted by their hash as applications use binary search afterwards.
//! Also, names may not be included, this can happen when a given name doesn't have any collision (?)
//!
//! Based on the documentation found in 3dbrew and GBATEK:
//! * https://www.3dbrew.org/wiki/SARC
//! * https://www.problemkaputt.de/gbatek.htm#3dsfilesarchivesarc

pub const magic = "SARC";

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    header_size: u16 = @sizeOf(Header),
    endian: hfmt.Endian,
    file_size: u32,
    data_offset: u32,
    version: u16 = 0x0100,
    _pad0: [2]u8 = @splat(0),

    pub const CheckError = error{ NotSarc, InvalidHeaderSize };
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotSarc;
        if (hdr.header_size < @sizeOf(Header)) return error.InvalidHeaderSize;
    }
};

pub const FileAllocationTable = extern struct {
    pub const Entry = extern struct {
        hash: u32,
        /// In `u32`s
        name_offset: u16,
        attributes: u16,
        data_start: u32,
        data_end: u32,

        pub fn name(entry: Entry, name_table: []const u8) [:0]const u8 {
            return std.mem.span(@as([*:0]const u8, @ptrCast(name_table))[@as(usize, entry.name_offset) * @sizeOf(u32) ..]);
        }
    };

    magic: [4]u8 = "SFAT".*,
    header_size: u16 = @sizeOf(FileAllocationTable),
    entries: u16,
    hash_multiplier: u32,

    pub const CheckError = error{ NotFat, InvalidHeaderSize };
    pub fn check(hdr: FileAllocationTable) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, "SFAT")) return error.NotFat;
        if (hdr.header_size < @sizeOf(FileAllocationTable)) return error.InvalidHeaderSize;
    }
};

pub const FilenameTable = extern struct {
    magic: [4]u8 = "SFNT".*,
    header_size: u16 = @sizeOf(FileAllocationTable),
    _pad0: [2]u8 = @splat(0),

    pub const CheckError = error{ NotFnt, InvalidHeaderSize };
    pub fn check(hdr: FilenameTable) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, "SFNT")) return error.NotFnt;
        if (hdr.header_size < @sizeOf(FilenameTable)) return error.InvalidHeaderSize;
    }
};

pub fn hashName(name: []const u8, multiplier: u32) u32 {
    var sum: u32 = 0;
    for (name) |c| sum = (sum *% multiplier) + c;
    return sum;
}

/// Basic support for opening files from absolute paths as there's no notion of "directory".
pub const View = struct {
    pub const File = enum(u32) {
        pub const Stat = struct {
            /// Hash of the name of this file.
            hash: u32,
            /// Offset of file data starting from `data_offset`.
            offset: u32,
            /// Size of the file in bytes.
            size: u32,
        };

        _,

        pub fn name(file: File, view: View) [:0]const u8 {
            return view.entries[@intFromEnum(file)].name(view.name_table);
        }

        pub fn stat(file: File, view: View) Stat {
            const file_entry = view.entries[@intFromEnum(file)];

            return .{
                .hash = file_entry.hash,
                .offset = file_entry.data_start,
                .size = file_entry.data_end - file_entry.data_start,
            };
        }
    };

    hash_multiplier: u32,
    entries: []const FileAllocationTable.Entry,
    name_table: []const u8,

    pub const Init = struct {
        view: View,
        data_offset: u32,
        data_size: u32,
    };

    pub const InitError = std.Io.Reader.Error || std.mem.Allocator.Error || Header.CheckError || FileAllocationTable.CheckError || FilenameTable.CheckError;

    /// Reads a `View` of a Darc from a `std.Io.Reader`.
    ///
    /// If successful, `reader` points to the start of file data (data_offset)
    pub fn initReader(reader: *std.Io.Reader, gpa: std.mem.Allocator) InitError!Init {
        // XXX: Can this be big endian?
        const hdr = try reader.takeStruct(Header, .little);

        try hdr.check();
        try reader.discardAll((hdr.header_size - @sizeOf(Header)));

        const fat_hdr = try reader.takeStruct(FileAllocationTable, .little);
        try fat_hdr.check();

        if (fat_hdr.entries == 0) return .{
            .view = .{
                .hash_multiplier = fat_hdr.hash_multiplier,
                .entries = &.{},
                .name_table = &.{},
            },
            .data_offset = hdr.data_offset,
            .data_size = hdr.file_size - hdr.data_offset,
        };

        try reader.discardAll((fat_hdr.header_size - @sizeOf(FileAllocationTable)));
        const entries = try reader.readSliceEndianAlloc(gpa, FileAllocationTable.Entry, fat_hdr.entries, .little);
        errdefer gpa.free(entries);

        const fnt_hdr = try reader.takeStruct(FilenameTable, .little);
        try fnt_hdr.check();
        try reader.discardAll((fnt_hdr.header_size - @sizeOf(FilenameTable)));

        const name_table = try reader.readAlloc(gpa, hdr.data_offset - (hdr.header_size + fat_hdr.header_size + @sizeOf(FileAllocationTable.Entry) * entries.len + fnt_hdr.header_size));
        errdefer gpa.free(name_table);

        return .{
            .view = .{
                .hash_multiplier = fat_hdr.hash_multiplier,
                .entries = entries,
                .name_table = name_table,
            },
            .data_offset = hdr.data_offset,
            .data_size = hdr.file_size - hdr.data_offset,
        };
    }

    pub fn deinit(view: View, gpa: std.mem.Allocator) void {
        gpa.free(view.name_table);
        gpa.free(view.entries);
    }

    pub fn iterator(view: View) Iterator {
        return .{ .view = view, .current = 0 };
    }

    pub fn openFileAbsolute(view: View, path: []const u8) !File {
        return view.openFileAbsoluteHash(hashName(path, view.hash_multiplier));
    }

    pub fn openFileAbsoluteHash(view: View, hash: u32) !File {
        const search_ctx: PathSearchContext = .{
            .view = view,
            .hash = hash,
        };

        return @enumFromInt(std.sort.binarySearch(FileAllocationTable.Entry, view.entries, search_ctx, PathSearchContext.compareEntries) orelse return error.FileNotFound);
    }

    pub const Iterator = struct {
        view: View,
        current: usize,

        pub fn next(it: *Iterator) ?File {
            if (it.current >= it.view.entries.len) return null;

            defer it.current += 1;
            return @enumFromInt(it.current);
        }
    };

    const PathSearchContext = struct {
        view: View,
        hash: u32,

        pub fn compareEntries(ctx: PathSearchContext, item: FileAllocationTable.Entry) std.math.Order {
            return std.math.order(item.hash, ctx.hash);
        }
    };
};

const std = @import("std");
const zitrus = @import("zitrus");

const hfmt = zitrus.horizon.fmt;
