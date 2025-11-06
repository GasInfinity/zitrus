//! **D**(ata?) **Arc**hive
//!
//! Yet another archive format, it looks like this:
//! * Header
//! * Entries (Root/First one tells you how many)
//! * `0`-terminated string table of file/directory names.
//! * File data
//!
//! Importantly, it is used in the logo found inside the ExeFS
//!
//! Based on the documentation found in 3dbrew and GBATEK:
//! * https://www.3dbrew.org/wiki/DARC
//! * https://problemkaputt.de/gbatek.htm#3dsfilesarchivedarc

pub const separator = '/';
pub const ComponentIterator = std.fs.path.ComponentIterator(.posix, u16);

pub const magic = "darc";

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    endian: hfmt.Endian,
    header_size: u16 = @sizeOf(Header),
    version: u32,
    file_size: u32,

    file_table_offset: u32,
    /// In bytes
    file_table_size: u32,
    file_data_offset: u32,

    pub const CheckError = error{ NotDarc, InvalidHeaderSize, InvalidFileTable, InvalidDataOffset };
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotDarc;
        if (hdr.header_size < @sizeOf(Header)) return error.InvalidHeaderSize;
        if (hdr.file_table_offset < hdr.header_size or !std.mem.isAligned(hdr.file_table_offset, @sizeOf(u32)) or !std.mem.isAligned(hdr.file_table_size, @sizeOf(u16))) return error.InvalidFileTable;
        if (hdr.file_data_offset < hdr.file_table_offset + hdr.file_table_size or !std.mem.isAligned(hdr.file_data_offset, 0x20)) return error.InvalidDataOffset;
    }
};

pub const TableEntry = extern struct {
    pub const Index = enum(u32) { _ };

    pub const Info = extern union {
        pub const Directory = extern struct {
            parent: Index,
            /// Exclusive index
            end: Index,
        };
        pub const File = extern struct {
            /// Relative to the start of the file
            offset: u32,
            size: u32,
        };
        directory: Directory,
        file: File,
    };

    pub const Attributes = packed struct(u32) {
        pub const Kind = enum(u1) { file, directory };
        /// From the end of the table
        name_offset: u24,
        kind: Kind,
        _unused0: u7 = 0,
    };

    attributes: Attributes,
    info: Info,

    pub fn name(entry: TableEntry, table: []const u16) []const u16 {
        return std.mem.span(@as([*:0]const u16, @ptrCast(table))[@divExact(entry.attributes.name_offset, 2)..]);
    }
};

pub const View = struct {
    pub const File = enum(u32) { _ };
    pub const Directory = enum(u32) { root = 0, _ };
    pub const Entry = struct {
        pub const Handle = enum(u32) { _ };

        kind: TableEntry.Attributes.Kind,
        handle: Handle,

        pub fn initDirectory(directory: Directory) Entry {
            return .{
                .kind = .directory,
                .handle = @enumFromInt(@intFromEnum(directory)),
            };
        }

        pub fn initFile(file: File) Entry {
            return .{
                .kind = .file,
                .handle = @enumFromInt(@intFromEnum(file)),
            };
        }

        pub fn name(entry: Entry, view: View) []const u16 {
            const table_entry = view.entries[@intFromEnum(entry.handle)];
            return table_entry.name(view.name_table);
        }

        pub fn asDirectory(entry: Entry) Directory {
            return switch (entry.kind) {
                .directory => @enumFromInt(@intFromEnum(entry.handle)),
                .file => unreachable,
            };
        }

        pub fn asFile(entry: Entry) File {
            return switch (entry.kind) {
                .directory => unreachable,
                .file => @enumFromInt(@intFromEnum(entry.handle)),
            };
        }
    };

    entries: []const TableEntry,
    name_table: []const u16,

    pub const Init = struct {
        view: View,
        data_offset: usize,
        data_size: usize,
    };

    pub const InitError = std.Io.Reader.Error || std.mem.Allocator.Error || Header.CheckError || error{RootNotDir};

    /// Reads a `View` of a Darc from a `std.Io.Reader`.
    ///
    /// If successful, `reader` points to the start of file data (data_offset)
    pub fn initReader(reader: *std.Io.Reader, gpa: std.mem.Allocator) InitError!Init {
        // XXX: Can this be big endian?
        const hdr = try reader.takeStruct(Header, .little);

        try hdr.check();
        try reader.discardAll((hdr.file_table_offset - @sizeOf(Header)));

        if (hdr.file_size == 0) return .{
            .view = .{
                .entries = &.{},
                .name_table = &.{},
            },
            .data_offset = hdr.file_data_offset,
            .data_size = hdr.file_size - hdr.file_data_offset,
        };

        const root = try reader.peekStruct(TableEntry, .little);

        if (root.attributes.kind != .directory) return error.RootNotDir;

        const entries = try reader.readSliceEndianAlloc(gpa, TableEntry, @intFromEnum(root.info.directory.end), .little);
        errdefer gpa.free(entries);

        const name_table = try reader.readSliceEndianAlloc(gpa, u16, @divExact(hdr.file_table_size - (entries.len * @sizeOf(TableEntry)), @sizeOf(u16)), .little);
        errdefer gpa.free(name_table);

        try reader.discardAll(hdr.file_data_offset - (hdr.file_table_offset + hdr.file_table_size));

        return .{
            .view = .{
                .entries = entries,
                .name_table = name_table,
            },
            .data_offset = hdr.file_data_offset,
            .data_size = hdr.file_size - hdr.file_data_offset,
        };
    }

    pub fn deinit(view: View, gpa: std.mem.Allocator) void {
        gpa.free(view.name_table);
        gpa.free(view.entries);
    }

    pub fn openFile(view: View, parent: Directory, path: []const u16) !File {
        const opened = try view.openAny(parent, path);

        return switch (opened.kind) {
            .file => @enumFromInt(@intFromEnum(opened.handle)),
            .directory => error.IsDir,
        };
    }

    pub fn openDir(view: View, parent: Directory, path: []const u16) !Directory {
        const opened = try view.openAny(parent, path);

        return switch (opened.kind) {
            .file => error.NotDir,
            .directory => @enumFromInt(@intFromEnum(opened.handle)),
        };
    }

    pub fn openAny(view: View, parent: Directory, path: []const u16) !Entry {
        if (path.len == 0) return error.FileNotFound;

        var it = ComponentIterator.init(path) catch {};

        var last_parent: Directory = if (it.root()) |_| .root else parent;
        var last: []const u16 = (it.next() orelse (if (it.root() != null) return .initDirectory(.root) else return error.BadPathName)).name;

        while (it.next()) |current| {
            last_parent = if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral("..")))
                @enumFromInt(@intFromEnum(view.entries[@intFromEnum(last_parent)].info.directory.parent))
            else if (view.find(last_parent, last)) |e| switch (e.kind) {
                .directory => e.asDirectory(),
                .file => return error.FileNotFound,
            } else return error.FileNotFound;

            last = current.name;
        }

        if (path[path.len - 1] == separator) return if (view.find(last_parent, last)) |e| switch (e.kind) {
            .directory => e,
            .file => error.FileNotFound,
        } else error.FileNotFound;

        return if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral("..")))
            .initDirectory(@enumFromInt(@intFromEnum(view.entries[@intFromEnum(last_parent)].info.directory.parent)))
        else if (view.find(last_parent, last)) |entry|
            return entry
        else
            return error.FileNotFound;
    }

    pub fn find(view: View, parent: Directory, name: []const u16) ?Entry {
        var it = view.iterator(parent);

        while (it.next(view)) |e| {
            if (std.mem.eql(u16, e.name(view), name)) return e;
        }

        return null;
    }

    pub fn iterator(view: View, parent: Directory) Iterator {
        return .init(view, parent);
    }

    pub const Iterator = struct {
        current: u32,
        end: u32,

        pub fn init(view: View, parent: Directory) Iterator {
            return .{
                .current = @intFromEnum(parent) + 1,
                .end = @intFromEnum(view.entries[@intFromEnum(parent)].info.directory.end),
            };
        }

        pub fn next(it: *Iterator, view: View) ?Entry {
            if (it.current >= it.end) return null;

            const current = it.current;
            const child = view.entries[current];

            defer switch (child.attributes.kind) {
                .directory => it.current = @intFromEnum(child.info.directory.end),
                .file => it.current += 1,
            };

            return .{
                .kind = child.attributes.kind,
                .handle = @enumFromInt(it.current),
            };
        }
    };
};

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const hfmt = zitrus.horizon.fmt;
