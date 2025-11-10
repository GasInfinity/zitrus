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
pub const min_alignment: std.mem.Alignment = .@"32";

pub const Header = extern struct {
    magic: [magic.len]u8 = magic.*,
    endian: hfmt.Endian = .little,
    header_size: u16 = @sizeOf(Header),
    version: u32 = 0x01000000,
    file_size: u32,

    meta_offset: u32,
    /// In bytes, 
    meta_size: u32,
    file_data_offset: u32,

    pub const CheckError = error{ NotDarc, InvalidHeaderSize, InvalidMetadataTable, InvalidDataOffset };
    pub fn check(hdr: Header) CheckError!void {
        if (!std.mem.eql(u8, &hdr.magic, magic)) return error.NotDarc;
        if (hdr.header_size < @sizeOf(Header)) return error.InvalidHeaderSize;
        if (hdr.meta_offset < hdr.header_size or !std.mem.isAligned(hdr.meta_offset, @sizeOf(u32)) or !std.mem.isAligned(hdr.meta_size, @sizeOf(u16))) return error.InvalidMetadataTable;
        if (hdr.file_data_offset < hdr.meta_offset + hdr.meta_size or !min_alignment.check(hdr.file_data_offset)) return error.InvalidDataOffset;
    }
};

pub const MetaEntry = extern struct {
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
        /// From the start of the name table
        name_offset: u24,
        kind: Kind,
        _unused0: u7 = 0,
    };

    attributes: Attributes,
    info: Info,

    pub fn name(entry: MetaEntry, table: []const u16) [:0]const u16 {
        return std.mem.span(@as([*:0]const u16, @ptrCast(table))[@divExact(entry.attributes.name_offset, 2)..]);
    }
};

/// DARC builder
pub const Builder = struct {
    pub const Directory = enum(u32) {
        root = 0,
        _,

        pub fn beginDirectory(dir: Directory, builder: *Builder, gpa: std.mem.Allocator, name: hfmt.AnyUtf) std.mem.Allocator.Error!Directory {
            std.debug.assert(dir == builder.current); // You must add files by depth

            const name_offset: u24 = @intCast(builder.name_table.items.len * @sizeOf(u16));
            const name_slice = try builder.name_table.addManyAsSlice(gpa, name.length());
            _ = name.encode(name_slice);
            try builder.name_table.append(gpa, 0);

            try builder.entries.append(gpa, .{
                .attributes = .{
                    .name_offset = name_offset,
                    .kind = .directory,
                },
                .info = .{ .directory = .{
                    .parent = @enumFromInt(@intFromEnum(builder.current)),
                    .end = undefined, // NOTE: To be filled by `Directory.end`
                }},
            });
            
            builder.current = @enumFromInt(builder.entries.items.len - 1);
            return builder.current;
        }

        pub fn addFile(dir: Directory, builder: *Builder, gpa: std.mem.Allocator, name: hfmt.AnyUtf, data: []const u8, alignment: std.mem.Alignment) std.mem.Allocator.Error!void { 
            var data_reader: std.Io.Reader = .fixed(data);
            return dir.streamFile(builder, gpa, name, &data_reader, alignment);
        }

        pub fn streamFile(dir: Directory, builder: *Builder, gpa: std.mem.Allocator, name: hfmt.AnyUtf, reader: *std.Io.Reader, alignment: std.mem.Alignment) (std.mem.Allocator.Error || std.Io.Reader.Error)!void {
            std.debug.assert(dir == builder.current); // You must add files by depth

            const name_offset: u24 = @intCast(builder.name_table.items.len * @sizeOf(u16));
            const name_slice = try builder.name_table.addManyAsSlice(gpa, name.length());
            _ = name.encode(name_slice);
            try builder.name_table.append(gpa, 0);

            const alignment_bytes: u32 = @intCast(alignment.toByteUnits());
            const data_offset: u32 = @intCast(builder.file_data.items.len);
            try reader.appendRemainingUnlimited(gpa, &builder.file_data);

            try builder.entries.append(gpa, .{
                .attributes = .{
                    .name_offset = name_offset,
                    .kind = .file,
                },
                .info = .{ .file = .{
                    // NOTE: This offset will be patched when we write it!
                    .offset = alignment_bytes, 
                    .size = @intCast(builder.file_data.items.len - data_offset),
                } },
            });
        }

        pub fn end(dir: *Directory, builder: *Builder) void {
            std.debug.assert(dir.* == builder.current);
            const entry = &builder.entries.items[@intFromEnum(dir.*)];

            entry.info.directory.end = @enumFromInt(builder.entries.items.len);
            builder.current = @enumFromInt(@intFromEnum(entry.info.directory.parent));
            dir.* = undefined;
        }
    };

    pub const empty: Builder = .{
        .entries = .empty,
        .name_table = .empty,
        .file_data = .empty,
        .current = @enumFromInt(0),
    };

    entries: std.ArrayList(MetaEntry),
    name_table: std.ArrayList(u16),
    file_data: std.ArrayList(u8),
    current: Directory,

    pub fn deinit(builder: *Builder, gpa: std.mem.Allocator) void {
        builder.file_data.deinit(gpa);
        builder.name_table.deinit(gpa);
        builder.entries.deinit(gpa);
        builder.* = undefined; 
    }

    pub fn beginRoot(builder: *Builder, gpa: std.mem.Allocator) std.mem.Allocator.Error!Directory {
        std.debug.assert(builder.current == .root);

        return Directory.root.beginDirectory(builder, gpa, .utf16(&.{}));
    }

    pub fn write(builder: Builder, writer: *std.Io.Writer) !void {
        const meta_size: u32 = @intCast(builder.entries.items.len * @sizeOf(MetaEntry) + builder.name_table.items.len * @sizeOf(u16));
        const header_meta_size: u32 = @intCast(@sizeOf(Header) + meta_size);
        const data_offset: u32 = @intCast(min_alignment.forward(header_meta_size));

        // XXX: I don't like having to do all this dance just to handle alignments correctly...
        try writer.writeStruct(Header{
            .endian = .little,
            .file_size = blk: {
                var file_size: u32 = data_offset;

                for (builder.entries.items) |entry| switch (entry.attributes.kind) {
                    .file => {
                        const file_data_alignment = entry.info.file.offset;
                        const aligned_offset = std.mem.alignForward(u32, file_size, file_data_alignment);
                        const file_data_size = entry.info.file.size;

                        file_size = aligned_offset + file_data_size;
                    },
                    .directory => {},
                };

                break :blk file_size;
            },
            .meta_offset = @sizeOf(Header),
            .meta_size = meta_size,
            .file_data_offset = data_offset,
        }, .little); 
        
        {
            var current_data_offset: u32 = data_offset;
            for (builder.entries.items) |entry| switch(entry.attributes.kind) {
                .file => {
                    const file_alignment = entry.info.file.offset;
                    const aligned_data_offset = std.mem.alignForward(u32, current_data_offset, file_alignment);
                    const file_size = entry.info.file.size;

                    try writer.writeStruct(MetaEntry{
                        .attributes = entry.attributes,
                        // NOTE: Offset stores alignment, see above
                        .info = .{ .file = .{ .offset = aligned_data_offset, .size = file_size } }
                    }, .little);

                    current_data_offset = aligned_data_offset + file_size;
                },
                .directory => try writer.writeStruct(entry, .little),
            };
        }

        try writer.writeSliceEndian(u16, builder.name_table.items, .little);
        try writer.splatByteAll(0x00, data_offset - header_meta_size);

        {
            var current_data_offset: u32 = data_offset;
            var remaining_data = builder.file_data.items;
            for (builder.entries.items) |entry| switch(entry.attributes.kind) {
                .file => {
                    const file_alignment = entry.info.file.offset;
                    const aligned_data_offset = std.mem.alignForward(u32, current_data_offset, file_alignment);
                    try writer.splatByteAll(0x00, aligned_data_offset - current_data_offset);

                    const file_size = entry.info.file.size;
                    try writer.writeAll(remaining_data[0..file_size]);

                    remaining_data = remaining_data[file_size..];
                    current_data_offset = aligned_data_offset + file_size;
                },
                .directory => {},
            };
        }
    }
};

pub const View = struct {
    pub const Directory = enum(u32) {
        root = 0,
        _,

        pub fn name(directory: Directory, view: View) [:0]const u16 {
            return view.entries[@intFromEnum(directory)].name(view.name_table);
        }
    };

    pub const File = enum(u32) {
        pub const Stat = struct {
            /// Offset of file data starting from `data_offset`.
            offset: u32,
            /// Size of the file in bytes.
            size: u32,
        };

        _,

        pub fn name(file: File, view: View) [:0]const u16 {
            return view.entries[@intFromEnum(file)].name(view.name_table);
        }

        pub fn stat(file: File, view: View) Stat {
            const file_meta = view.entries[@intFromEnum(file)];

            return .{
                .offset = file_meta.info.file.offset - view.data_offset,
                .size = file_meta.info.file.size,
            };
        }
    };

    pub const Entry = struct {
        pub const Handle = enum(u32) { _ };

        kind: MetaEntry.Attributes.Kind,
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

    data_offset: u32,
    entries: []const MetaEntry,
    name_table: []const u16,

    pub const Init = struct {
        view: View,
        data_size: u32,
    };

    pub const InitError = std.Io.Reader.Error || std.mem.Allocator.Error || Header.CheckError || error{RootNotDir};

    /// Reads a `View` of a Darc from a `std.Io.Reader`.
    ///
    /// If successful, `reader` points to the start of file data (data_offset)
    pub fn initReader(reader: *std.Io.Reader, gpa: std.mem.Allocator) InitError!Init {
        // XXX: Can this be big endian?
        const hdr = try reader.takeStruct(Header, .little);

        try hdr.check();
        try reader.discardAll((hdr.meta_offset - @sizeOf(Header)));

        if (hdr.file_size == 0) return .{
            .view = .{
                .data_offset = hdr.file_data_offset,
                .entries = &.{},
                .name_table = &.{},
            },
            .data_size = hdr.file_size - hdr.file_data_offset,
        };

        const root = try reader.peekStruct(MetaEntry, .little);

        if (root.attributes.kind != .directory) return error.RootNotDir;

        const entries = try reader.readSliceEndianAlloc(gpa, MetaEntry, @intFromEnum(root.info.directory.end), .little);
        errdefer gpa.free(entries);

        const name_table = try reader.readSliceEndianAlloc(gpa, u16, @divExact(hdr.meta_size - (entries.len * @sizeOf(MetaEntry)), @sizeOf(u16)), .little);
        errdefer gpa.free(name_table);

        try reader.discardAll(hdr.file_data_offset - (hdr.meta_offset + hdr.meta_size));

        return .{
            .view = .{
                .data_offset = hdr.file_data_offset,
                .entries = entries,
                .name_table = name_table,
            },
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
