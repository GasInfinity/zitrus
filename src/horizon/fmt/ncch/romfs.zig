//! RomFS reader and writer.
//!
//!
//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/RomFS

pub const separator = '/';
pub const ComponentIterator = std.fs.path.ComponentIterator(.posix, u16);

pub const IvfcHeader = extern struct {
    pub const Level = extern struct { logical_offset: u64, hash_data_size: u64, block_size: u32, _reserved0: u32 };
    magic: [4]u8 = "IVFC".*,
    magic_int: u32 = 0x10000,
    master_hash_size: u32,
    levels: [3]ivfc.Level,
    _reserved0: u32,
    // XXX: ???
    optional_info_size: u32,

    comptime {
        std.debug.assert(@sizeOf(IvfcHeader) == 0x5C);
    }
};

pub const Header = extern struct {
    pub const min_data_alignment = 16;

    pub const HashMetaInfo = extern struct {
        hash_table_offset: u32,
        hash_table_size: u32,
        meta_table_offset: u32,
        meta_table_size: u32,

        pub fn isAligned(info: HashMetaInfo) bool {
            return std.mem.isAligned(info.hash_table_offset, @sizeOf(u32)) and std.mem.isAligned(info.hash_table_size, @sizeOf(u32)) or std.mem.isAligned(info.meta_table_offset, @sizeOf(u32)) and std.mem.isAligned(info.meta_table_size, @sizeOf(u32));
        }
    };

    length: u32 = @sizeOf(Header),
    directory_info: HashMetaInfo,
    file_info: HashMetaInfo,
    file_data_offset: u32,

    /// Checks if the header is consistent/valid.
    pub fn check(hdr: Header) !void {
        if (hdr.length != @sizeOf(Header)) return error.InvalidHeaderLength;
        if (!std.mem.isAligned(hdr.file_data_offset, Header.min_data_alignment)) return error.InvalidDataAlignment;
        if (!hdr.directory_info.isAligned()) return error.InvalidDirectoryAlignment;
        if (!hdr.file_info.isAligned()) return error.InvalidFileAlignment;
    }
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
        data_size: u64 align(@sizeOf(u32)),
        next_hash_collision: FileOffset,
        name_byte_len: u32,

        pub fn initEmpty(parent: DirectoryOffset, name_byte_len: u32) FileHeader {
            return .{
                .parent = parent,
                .next_sibling = .none,
                .data_offset = undefined,
                .data_size = undefined,
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

    fn Builder(comptime T: type, comptime TOffset: type) type {
        if ((T != FileHeader or TOffset != FileOffset) and (T != DirectoryHeader or TOffset != DirectoryOffset)) @compileError("Can only use a metadata table with a valid header and offset.");

        return struct {
            pub const empty: Self = .{ .data = .empty };

            data: std.ArrayList(u32),

            pub fn deinit(builder: *Self, gpa: std.mem.Allocator) void {
                builder.data.deinit(gpa);
            }

            pub fn addOne(builder: *Self, gpa: std.mem.Allocator, parent: DirectoryOffset, name: Name) !TOffset {
                const name_len = name.length();
                const name_byte_len = name_len * @sizeOf(u16);
                const total_elements = @divExact(@sizeOf(T) + std.mem.alignForward(usize, name_byte_len, @sizeOf(u32)), @sizeOf(u32));

                const offset: u32 = @intCast(builder.data.items.len * @sizeOf(u32));
                const entry = try builder.data.addManyAsSlice(gpa, total_elements);
                const entry_hdr: *T = @ptrCast(entry);
                const entry_name: []u16 = std.mem.bytesAsSlice(u16, std.mem.sliceAsBytes(entry[(@divExact(@sizeOf(T), @sizeOf(u32)))..]));

                entry_hdr.* = .initEmpty(parent, @intCast(name_byte_len));

                const last = name.encode(entry_name);
                @memset(entry_name[last..], 0x00);

                return @enumFromInt(offset);
            }

            pub inline fn get(builder: Self, offset: TOffset) *T {
                // NOTE: @constCast here is justified, we own the data!
                return @constCast(builder.toView().get(offset));
            }

            pub inline fn getName(builder: Self, offset: TOffset) []const u16 {
                return builder.toView().getName(offset);
            }

            pub inline fn write(builder: Self, writer: *std.Io.Writer) !void {
                return builder.toView().write(writer);
            }

            pub inline fn toView(builder: Self) meta.View(T, TOffset) {
                return .init(builder.data.items);
            }

            const Self = @This();
        };
    }

    fn View(comptime T: type, comptime TOffset: type) type {
        if ((T != FileHeader or TOffset != FileOffset) and (T != DirectoryHeader or TOffset != DirectoryOffset)) @compileError("Can only use a metadata table with a valid header and offset.");

        return struct {
            data: []const u32,

            /// `data` must be in native endian.
            pub fn init(data: []const u32) Self {
                return .{ .data = data };
            }

            pub fn get(table: Self, offset: TOffset) *const T {
                std.debug.assert(std.mem.isAligned(@intFromEnum(offset), @alignOf(u32)));
                const aligned_offset = @divExact(@intFromEnum(offset), @sizeOf(u32));

                std.debug.assert(aligned_offset < table.data.len);
                return std.mem.bytesAsValue(T, std.mem.sliceAsBytes(table.data[aligned_offset..]));
            }

            pub fn getName(table: Self, offset: TOffset) []const u16 {
                const hdr = table.get(offset);
                const name_bytes = std.mem.sliceAsBytes(table.data[@divExact(@intFromEnum(offset) + @sizeOf(T), @sizeOf(u32))..])[0..hdr.name_byte_len];

                return @alignCast(std.mem.bytesAsSlice(u16, name_bytes));
            }

            pub fn write(table: Self, writer: *std.Io.Writer) !void {
                if (builtin.cpu.arch.endian() == .little) {
                    try writer.writeAll(std.mem.sliceAsBytes(table.data));
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
                            if (@divExact(@intFromEnum(entry), 4) >= it.table.data.len) return null;
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

    pub const DirectoryBuilder = meta.Builder(DirectoryHeader, DirectoryOffset);
    pub const DirectoryView = meta.View(DirectoryHeader, DirectoryOffset);
    pub const FileBuilder = meta.Builder(FileHeader, FileOffset);
    pub const FileView = meta.View(FileHeader, FileOffset);

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

    directories: meta.DirectoryBuilder,
    files: meta.FileBuilder,
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
        new_hdr.data_size = @intCast(data.len);

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
        inline for (&.{ &builder.directories, &builder.files }, &.{ &builder.directory_hashes, &builder.file_hashes }) |meta_builder, hash_table| {
            const hash_table_size = officialHashPrime(@intCast(meta_builder.data.items.len));

            try hash_table.resize(gpa, hash_table_size);
            @memset(hash_table.items, .none);

            const view = meta_builder.toView();
            var it = view.iterator();

            while (it.next()) |entry| {
                const hdr = meta_builder.get(entry);
                const name = meta_builder.getName(entry);

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
        const data_offset: u32 = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directories.data.items.len + builder.files.data.items.len + builder.directory_hashes.items.len + builder.file_hashes.items.len));
        const aligned_data_offset = std.mem.alignForward(u32, data_offset, Header.min_data_alignment);

        try writer.writeStruct(Header{
            .length = @sizeOf(Header),
            .directory_info = .{
                .hash_table_offset = @sizeOf(Header),
                .hash_table_size = @intCast(@sizeOf(u32) * builder.directory_hashes.items.len),
                .meta_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directory_hashes.items.len + builder.file_hashes.items.len)),
                .meta_table_size = @intCast(@sizeOf(u32) * builder.directories.data.items.len),
            },
            .file_info = .{
                .hash_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * builder.directory_hashes.items.len),
                .hash_table_size = @intCast(@sizeOf(u32) * builder.file_hashes.items.len),
                .meta_table_offset = @intCast(@sizeOf(Header) + @sizeOf(u32) * (builder.directories.data.items.len + builder.directory_hashes.items.len + builder.file_hashes.items.len)),
                .meta_table_size = @intCast(@sizeOf(u32) * builder.files.data.items.len),
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

/// RomFS view, doesn't allow modifications.
pub const View = struct {
    pub const Directory = enum(u32) {
        root = 0x00,
        _,

        pub fn name(directory: Directory, view: View) []const u16 {
            return view.directories.getName(@enumFromInt(@intFromEnum(directory)));
        }
    };

    pub const File = enum(u32) {
        pub const Stat = struct {
            /// Offset of file data starting from `data_offset`.
            offset: u64,
            /// Size of the file in bytes.
            size: u64,
        };

        _,

        pub fn name(file: File, view: View) []const u16 {
            return view.files.getName(@enumFromInt(@intFromEnum(file)));
        }

        pub fn stat(file: File, view: View) Stat {
            const file_meta = view.files.get(@enumFromInt(@intFromEnum(file)));

            return .{
                .offset = file_meta.data_offset,
                .size = file_meta.data_size,
            };
        }
    };

    pub const Entry = struct {
        pub const Kind = enum(u8) { directory, file };
        pub const Handle = enum(u32) { _ };

        kind: Kind,
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
            return switch (entry.kind) {
                .directory => view.directories.getName(@enumFromInt(@intFromEnum(entry.handle))),
                .file => view.files.getName(@enumFromInt(@intFromEnum(entry.handle))),
            };
        }
    };

    pub const Init = struct {
        view: View,
        data_offset: u32,
    };

    directories: meta.DirectoryView,
    files: meta.FileView,
    directory_hashes: []const meta.DirectoryOffset,
    file_hashes: []const meta.FileOffset,

    /// Reads a `View` of a RomFS from an `std.fs.File.Reader`
    /// within its current position.
    ///
    /// Final seek offset is unaffected if no error is returned.
    pub fn initFile(file_reader: *std.fs.File.Reader, gpa: std.mem.Allocator) !Init {
        const initial_offset = file_reader.logicalPos();
        const hdr = try file_reader.interface.takeStruct(Header, .little);

        try hdr.check();

        const directories = try gpa.alloc(u32, @divExact(hdr.directory_info.meta_table_size, @sizeOf(u32)));
        errdefer gpa.free(directories);

        const files = try gpa.alloc(u32, @divExact(hdr.file_info.meta_table_size, @sizeOf(u32)));
        errdefer gpa.free(files);

        const directory_hashes = try gpa.alloc(meta.DirectoryOffset, @divExact(hdr.directory_info.hash_table_size, @sizeOf(u32)));
        errdefer gpa.free(directory_hashes);

        const file_hashes = try gpa.alloc(meta.FileOffset, @divExact(hdr.file_info.hash_table_size, @sizeOf(u32)));
        errdefer gpa.free(file_hashes);

        try file_reader.seekTo(initial_offset + hdr.directory_info.hash_table_offset);
        try file_reader.interface.readSliceEndian(meta.DirectoryOffset, directory_hashes, .little);

        try file_reader.seekTo(initial_offset + hdr.file_info.hash_table_offset);
        try file_reader.interface.readSliceEndian(meta.FileOffset, file_hashes, .little);

        try file_reader.seekTo(initial_offset + hdr.directory_info.meta_table_offset);
        try file_reader.interface.readSliceEndian(u32, directories, builtin.cpu.arch.endian());

        try file_reader.seekTo(initial_offset + hdr.file_info.meta_table_offset);
        try file_reader.interface.readSliceEndian(u32, files, builtin.cpu.arch.endian());

        try file_reader.seekTo(initial_offset);

        comptime {
            if (builtin.cpu.arch.endian() != .little) @compileError("TODO: Big endian RomFS meta parsing (post-process)");
        }

        return .{
            .view = .init(.init(directories), .init(files), directory_hashes, file_hashes),
            .data_offset = hdr.file_data_offset,
        };
    }

    pub fn init(directories: meta.DirectoryView, files: meta.FileView, directory_hashes: []const meta.DirectoryOffset, file_hashes: []const meta.FileOffset) View {
        return .{
            .directories = directories,
            .files = files,
            .directory_hashes = directory_hashes,
            .file_hashes = file_hashes,
        };
    }

    pub fn deinit(view: View, gpa: std.mem.Allocator) void {
        gpa.free(view.directories.data);
        gpa.free(view.files.data);
        gpa.free(view.directory_hashes);
        gpa.free(view.file_hashes);
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
        var last: []const u16 = (it.next() orelse return error.FileNotFound).name;

        while (it.next()) |current| {
            last_parent = if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral(".")))
                last_parent
            else if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral("..")))
                @enumFromInt(@intFromEnum(view.directories.get(@enumFromInt(@intFromEnum(last_parent))).parent))
            else
                view.findDirectory(last_parent, last) orelse return error.FileNotFound;

            last = current.name;
        }

        if (path[path.len - 1] == separator) {
            return if (view.findDirectory(last_parent, last)) |dir| .initDirectory(dir) else error.FileNotFound;
        }

        return if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral(".")))
            .initDirectory(last_parent)
        else if (std.mem.eql(u16, last, std.unicode.utf8ToUtf16LeStringLiteral("..")))
            .initDirectory(@enumFromInt(@intFromEnum(view.directories.get(@enumFromInt(@intFromEnum(last_parent))).parent)))
        else if (view.findFile(last_parent, last)) |file|
            .initFile(file)
        else if (view.findDirectory(last_parent, last)) |dir|
            .initDirectory(dir)
        else
            return error.FileNotFound;
    }

    pub fn findFile(view: View, parent: Directory, name: []const u16) ?File {
        const name_hash = meta.hash(name, @enumFromInt(@intFromEnum(parent)));
        const first_offset: meta.FileOffset = view.file_hashes[name_hash % view.file_hashes.len];

        return find: switch (first_offset) {
            .none => null,
            _ => |offset| {
                const file = view.files.get(offset);
                const file_name = view.files.getName(offset);

                if (parent != @as(Directory, @enumFromInt(@intFromEnum(file.parent))) or !std.mem.eql(u16, file_name, name)) {
                    continue :find file.next_hash_collision;
                }

                break :find @enumFromInt(@intFromEnum(offset));
            },
        };
    }

    pub fn findDirectory(view: View, parent: Directory, name: []const u16) ?Directory {
        const name_hash = meta.hash(name, @enumFromInt(@intFromEnum(parent)));
        const first_offset: meta.DirectoryOffset = view.directory_hashes[name_hash % view.directory_hashes.len];

        return find: switch (first_offset) {
            // NOTE: You cannot open the root directory, it is already implicitly opened.
            .root => continue :find view.directories.get(.root).next_hash_collision,
            .none => null,
            _ => |offset| {
                const directory = view.directories.get(offset);
                const directory_name = view.directories.getName(offset);

                if (parent != @as(Directory, @enumFromInt(@intFromEnum(directory.parent))) or !std.mem.eql(u16, directory_name, name)) {
                    continue :find directory.next_hash_collision;
                }

                break :find @enumFromInt(@intFromEnum(offset));
            },
        };
    }

    /// Iterator over all directories and files in a directory.
    pub fn iterator(view: View, parent: Directory) Iterator {
        return .init(view, parent);
    }

    /// Iterator over all files in a directory
    pub fn fileIterator(view: View, parent: Directory) FileIterator {
        return .init(view, parent);
    }

    /// Iterator over all directories in a directory.
    pub fn directoryIterator(view: View, parent: Directory) DirectoryIterator {
        return .init(view, parent);
    }

    pub const Iterator = struct {
        directory: DirectoryIterator,
        file: FileIterator,

        pub fn init(view: View, parent: Directory) Iterator {
            return .{
                .directory = .init(view, parent),
                .file = .init(view, parent),
            };
        }

        pub fn next(it: *Iterator, view: View) ?Entry {
            return if (it.directory.next(view)) |current|
                .initDirectory(current)
            else if (it.file.next(view)) |current|
                .initFile(current)
            else
                null;
        }
    };

    pub const FileIterator = struct {
        current: meta.FileOffset,

        pub fn init(view: View, parent: Directory) FileIterator {
            const directory = view.directories.get(@enumFromInt(@intFromEnum(parent)));

            return .{
                .current = @enumFromInt(@intFromEnum(directory.first_file)),
            };
        }

        pub fn next(it: *FileIterator, view: View) ?File {
            return switch (it.current) {
                .none => null,
                _ => |offset| blk: {
                    defer it.current = view.files.get(offset).next_sibling;
                    break :blk @enumFromInt(@intFromEnum(offset));
                },
            };
        }
    };

    pub const DirectoryIterator = struct {
        current: meta.DirectoryOffset,

        pub fn init(view: View, parent: Directory) DirectoryIterator {
            const directory = view.directories.get(@enumFromInt(@intFromEnum(parent)));

            return .{
                .current = @enumFromInt(@intFromEnum(directory.first_directory)),
            };
        }

        pub fn next(it: *DirectoryIterator, view: View) ?Directory {
            return switch (it.current) {
                .none => null,
                // root is never the child of any directory.
                .root => unreachable,
                _ => |offset| blk: {
                    defer it.current = view.directories.get(offset).next_sibling;
                    break :blk @enumFromInt(@intFromEnum(offset));
                },
            };
        }
    };
};

test "builder and view are idempotent" {
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

    try builder.rehash(gpa);

    var view: View = .init(builder.directories.toView(), builder.files.toView(), builder.directory_hashes.items, builder.file_hashes.items);

    {
        const jp = try view.openFile(.root, std.unicode.utf8ToUtf16LeStringLiteral("A/ソウル・ソサエティ"));
        const jp_stat = jp.stat(view);
        const jp_data = builder.file_data.items[jp_stat.offset..][0..jp_stat.size];

        try testing.expectEqualSlices(u8, "Ahh yes, japanese\n", jp_data);
    }

    {
        const sp = try view.openFile(.root, std.unicode.utf8ToUtf16LeStringLiteral("A/BC/¿qué?"));
        const sp_stat = sp.stat(view);
        const sp_data = builder.file_data.items[sp_stat.offset..][0..sp_stat.size];

        try testing.expectEqualSlices(u8, "Spanish or english, decide please\n", sp_data);
    }

    _ = try view.openDir(.root, std.unicode.utf8ToUtf16LeStringLiteral("A/BC/CD"));
}

const testing = std.testing;

const builtin = @import("builtin");
const std = @import("std");
const zitrus = @import("zitrus");
const ivfc = zitrus.horizon.fmt.ivfc;
