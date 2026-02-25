pub const empty: Storage = .init(.{ .session = .none });
pub const separator = '/';

pub const Descriptor = enum(u32) {
    invalid = std.math.maxInt(u32),
    cwd = std.math.maxInt(u32) - 1,
    _,
};

/// State of a file in the table
pub const Description = struct {
    pub const Table = Storage.Table(Description);
    pub const Stored = extern union {
        romfs: romfs.View.Entry,
        file: Filesystem.File,
        /// `invalid` is a sentinel for root.
        path: Builder.Table.Index,
    };

    pub const Flags = packed struct {
        pub const Kind = enum(u1) { file, directory };

        device: Device.Kind,
        kind: Kind,
    };

    pub const Extra = extern union {
        pub const Directory = extern union {
            pub const min_reader_buffer_len = @sizeOf(NameBuffer) + @sizeOf(Filesystem.Directory.Entry);
            pub const NameBuffer = [Io.Dir.max_name_bytes * 4]u8;

            romfs: romfs.View.Iterator,
            archive: Filesystem.Directory,
        };

        // XXX: I would like to use atomics but its an upstream issue...
        seek: zitrus.hardware.cpu.arm11.Monitor(u64),
        dir: Directory,
    };

    ref: std.atomic.Value(u16),
    flags: Flags,
    stored: Stored,
    extra: Extra,
};

/// A builder for a path.
pub const Builder = struct {
    pub const Table = Storage.Table([]const u16);
    pub const root: []const u16 = &.{'/', 0};
    pub const init: Builder = .{ .buf = undefined, .end = 0 };

    buf: [Io.Dir.max_path_bytes + 1]u16,
    end: usize,

    
    /// It is asserted that `path` is valid
    pub fn appendRaw(builder: *Builder, sub_path: []const u16) error{NameTooLong}!void {
        if (builder.end + sub_path.len > builder.buf.len) return error.NameTooLong;
        @memcpy(builder.buf[builder.end..][0..sub_path.len], sub_path);
        builder.end += sub_path.len;
    }

    pub fn append(builder: *Builder, sub_path: []const u8) error{NameTooLong, BadPathName}!void {
        if (sub_path.len == 0) return;
        if (builder.end == builder.buf.len) return error.NameTooLong;

        if (builder.end == 0 or builder.buf[builder.end - 1] != '/') {
            builder.buf[builder.end] = '/';
            builder.end += 1;
        }

        var it: Io.Dir.path.ComponentIterator(.posix, u8) = .init(sub_path); 

        var next = it.next();
        while (next) |component| {
            next = it.next();

            const name = component.name;
            if (std.mem.eql(u8, name, ".")) continue;
            if (std.mem.eql(u8, name, "..")) {
                const last = if (std.mem.lastIndexOfScalar(u16, builder.buf[0..builder.end - 1], '/')) |idx| 
                    builder.buf[(idx + 1)..builder.end]
                else 
                    &.{}; // This means we're at root.

                builder.end -= last.len;
                continue;
            }

            if (builder.end + name.len > builder.buf.len) return error.NameTooLong;

            const written = std.unicode.utf8ToUtf16Le(builder.buf[builder.end..], name) catch return error.BadPathName;
            builder.end += written;

            if (next != null) {
                if (builder.end == builder.buf.len) return error.NameTooLong;

                builder.buf[builder.end] = '/';
                builder.end += 1;
            }
        }
    }

    /// Adds a NULL terminator, without modifying `path.end`
    ///
    /// Returns `path` including the terminator.
    // NOTE: we're not using ':0' here as we want the terminator to be *included* in the slice!
    pub fn nullTerminate(builder: *Builder) error{NameTooLong}![]u16 {
        if (builder.end == builder.buf.len) return error.NameTooLong;

        builder.buf[builder.end] = 0;
        return builder.buf[0..builder.end + 1];
    }

    pub fn path(builder: *Builder) []u16 {
        return builder.buf[0..builder.end];
    }

    test Builder {
        const utf16 = std.unicode.utf8ToUtf16LeStringLiteral;
        var builder: Builder = .init;

        try builder.append("/work/pls");
        try testing.expectEqualSlices(u16, utf16("/work/pls"), builder.path());

        try builder.append("./.././.././.././..");
        try testing.expectEqualSlices(u16, utf16("/"), builder.path());

        try builder.append("./.././../some/./path/./that/works/./maybe/./././not/../../..");
        try testing.expectEqualSlices(u16, utf16("/some/path/that/"), builder.path());

        try builder.append("test.txt");
        try testing.expectEqualSlices(u16, utf16("/some/path/that/test.txt"), builder.path());

        const terminated = try builder.nullTerminate();
        try testing.expectEqual(0, terminated[terminated.len - 1]);
    }
};

pub const Device = struct {
    pub const empty: Device = .{
        .romfs = .empty,
        .sdmc = .none,
    };

    pub const Kind = enum(u4) {
        romfs,
        sdmc,

        pub fn archiveId(kind: Kind) ?Filesystem.ArchiveId {
            return switch (kind) {
                .romfs => null,
                .sdmc => .sdmc,
            };
        }
    };

    romfs: Filesystem.RomFs,
    sdmc: Filesystem.Archive,

    pub fn deinit(device: *Device, gpa: std.mem.Allocator, fs: Filesystem) void {
        device.romfs.deinit(gpa);
        if (device.sdmc != .none) device.sdmc.close(fs);
        device.* = .empty;
    }

    pub fn archive(device: *Device, kind: Kind) ?*Filesystem.Archive {
        return switch (kind) {
            .romfs => null,
            .sdmc => &device.sdmc,
        };
    }
};

fs: Filesystem = .{ .session = .none },
device: Device,

/// Protects `descriptors`, `table` and `cwd`
lock: Io.RwLock = .init,

/// May be `invalid`, in that case non-device paths *will* return `error.FileNotFound`
cwd: Description.Table.Index = .invalid,
fds: std.ArrayList(Description.Table.Index) = .empty,
descriptions: Description.Table = .empty,
paths: Builder.Table = .empty,

/// Now owns `fs`
pub fn init(fs: Filesystem) Storage {
    return .{
        .fs = fs,
        .device = .empty,
        .lock = .init,
    .cwd = .invalid,
        .fds = .empty,
        .descriptions = .empty,
    };
}

pub fn deinit(storage: *Storage, gpa: std.mem.Allocator) void {
    if (storage.fs.session == horizon.ClientSession.none) return; // Nothing to deinit

    switch (storage.cwd) {
        .invalid => {},
        _ => |idx| storage.closeDescription(gpa, idx),
    }

    storage.paths.deinit(gpa);
    storage.descriptions.deinit(gpa);
    storage.fds.deinit(gpa);
    storage.device.deinit(gpa, storage.fs);
    storage.fs.close();
    storage.* = .empty;
}

pub const OpenPathError = error{
    ReadOnlyFileSystem,
    SystemResources,
    FileNotFound,
    NoDevice,
    BadPathName,
    PathAlreadyExists,
    NameTooLong,
    IsDir,
    NotDir,
    Unexpected,
};

pub const OpenFlags = struct {
    pub const Allow = enum {
        file,
        directory,
        any,
    };
    pub const Create = enum {
        none,
        create,
        exclusive,
    };

    mode: Io.File.OpenMode,
    create: Create = .none,
    allow: Allow = .any,
};

/// The format is `device:/PATH/TO/FILE`.
/// The device name is optional and will be that of `dir` if ommited.
/// `cwd` may be unlinked, if so trying to open a non-device path will fail with `error.NoDevice`
///
/// Assumes `lock` is held as non-shareable.
pub fn openPath(storage: *Storage, gpa: std.mem.Allocator, parent_dir: Descriptor, sub_path: []const u8, opts: OpenFlags) OpenPathError!Descriptor {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;
    if (opts.create != .none) std.debug.assert(opts.allow == .file);

    const fd = storage.allocateLowestDescriptor(gpa) catch return error.SystemResources;
    errdefer storage.fds.items[@intFromEnum(fd)] = .invalid;

    const free_desc = storage.descriptions.allocateOne(gpa) catch return error.SystemResources;
    errdefer storage.descriptions.free(free_desc);

    storage.fds.items[@intFromEnum(fd)] = free_desc;

    const desc: Description = des: {
        const maybe_device, const device_path = try splitParsePath(sub_path);
        const maybe_dir_desc = try storage.getDirectoryDescription(parent_dir); 
        const device = maybe_device orelse if (maybe_dir_desc) |desc| 
            desc.flags.device
        else
            return error.NoDevice;

        try storage.tryMount(gpa, device);

        switch (device) {
            .romfs => {
                if (opts.create != .none) return error.ReadOnlyFileSystem;

                const parent: romfs.View.Directory = if (Io.Dir.path.isAbsolutePosix(device_path)) 
                    .root
                else maybe_dir_desc.?.stored.romfs.asDirectory(); // We already return NoDevice above

                var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
                const utf16_device_path = utf16_device_path_buffer[0..std.unicode.utf8ToUtf16Le(&utf16_device_path_buffer, device_path) catch return error.BadPathName];
                const entry = try storage.device.romfs.openAny(parent, utf16_device_path);

                if ((opts.allow == .file or opts.mode != .read_only) and entry.kind == .directory) return error.IsDir;
                if ((opts.allow == .directory) and entry.kind == .file) return error.NotDir;
                if (opts.mode != .read_only) return error.ReadOnlyFileSystem; // XXX: pluh... and ReadOnlyFileSystem?

                break :des .{
                    .ref = .init(1),
                    .stored = .{ .romfs = entry },
                    .flags = .{
                        .device = .romfs,
                        .kind = switch (entry.kind) {
                            .file => .file,
                            .directory => .directory,
                        },
                    },
                    .extra = switch (entry.kind) {
                        .file => .{ .seek = .init(0) },
                        .directory => .{ .dir = .{ .romfs = entry.asDirectory().iterator(storage.device.romfs.view) } },
                    },
                };
            },
            .sdmc => {
                // NOTE: We already check in tryMount that fs is valid and we've opened the archive.
                const fs = storage.fs;
                const archive = storage.device.archive(device).?.*;

                var builder: Builder = .init;
                const path_z = try storage.buildPath(&builder, device_path, maybe_dir_desc);

                if (std.mem.eql(u16, path_z, Builder.root)) break :des .{
                    .ref = .init(1),
                    .stored = .{ .path = .invalid },
                    .flags = .{
                        .device = device,
                        .kind = .directory,
                    },
                    .extra = .{ .dir = .{ .archive = .none } },
                };

                file: {
                    switch (opts.create) {
                        .none, .create => {},
                        .exclusive => fs.sendCreateFile(0, archive, .utf16, @ptrCast(path_z), .{}, 0) catch |err| switch (err) {
                            error.PathAlreadyExists => return error.PathAlreadyExists,
                            else => return error.Unexpected,
                        },
                    }

                    const file = fs.sendOpenFile(0, archive, .utf16, @ptrCast(path_z), .{
                        .read = opts.mode != .write_only,
                        .write = opts.mode != .read_only,
                        .create = opts.create != .none,
                    }, .{}) catch |err| switch (err) {
                        error.IsDir => |e| if (opts.allow != .file and opts.mode == .read_only)
                            break :file
                        else 
                            return e,
                        error.FileNotFound => |e| return e,
                        else => return error.Unexpected,
                        // TODO: We have to map the errors in OpenFile
                    };
                    errdefer file.close();
                    
                    if (opts.allow == .directory) return error.NotDir;

                    break :des .{
                        .ref = .init(1),
                        .stored = .{ .file = file },
                        .flags = .{
                            .device = device,
                            .kind = .file,
                        },
                        .extra = .{ .seek = .init(0) },
                    };
                }

                // NOTE: We already know (truly?) this is a directory atp, we can avoid opening a handle (which we only need to iterate)
                const stored_path_idx = storage.paths.allocateOne(gpa) catch return error.SystemResources;
                errdefer storage.paths.free(stored_path_idx);
                
                const stored_path: []const u16 = gpa.dupe(u16, path_z) catch return error.SystemResources;
                errdefer gpa.free(stored_path);
                
                storage.paths.list.items[@intFromEnum(stored_path_idx)] = .{ .value = stored_path };

                break :des .{
                    .ref = .init(1),
                    .stored = .{ .path = stored_path_idx },
                    .flags = .{
                        .device = device,
                        .kind = .directory,
                    },
                    .extra = .{ .dir = .{ .archive = .none } },
                };
            },
        }
    };

    storage.descriptions.list.items[@intFromEnum(free_desc)] = .{ .value = desc };
    return fd;
}

pub fn createFileAtomic(io: std.Io, dir: Io.Dir, sub_path: []const u8, opts: Io.Dir.CreateFileAtomicOptions) Io.Dir.CreateFileAtomicError!Io.File.Atomic {
    _, const device_path = try splitParsePath(sub_path);

    const target_dir, const dest_path, const close_on_deinit = if (Io.Dir.path.dirnamePosix(device_path)) |dirname| blk: {
        const new_dir = if (opts.make_path)
            dir.createDirPathOpen(io, dirname, .{}) catch |err| switch (err) {
                // None of these make sense in this context.
                error.IsDir,
                error.Streaming,
                error.DiskQuota,
                error.PathAlreadyExists,
                error.LinkQuotaExceeded,
                error.PipeBusy,
                error.FileTooBig,
                error.FileLocksUnsupported,
                error.DeviceBusy,
                => return error.Unexpected,

                else => |e| return e,
            }
        else
            try dir.openDir(io, dirname, .{});

        break :blk .{ new_dir, Io.Dir.path.basename(device_path), true };
    } else .{ dir, sub_path, false };

    while (true) {
        var random_integer: u64 = undefined;
        io.random(@ptrCast(&random_integer));
        const tmp_sub_path = std.fmt.hex(random_integer);
        const file = target_dir.createFile(io, &tmp_sub_path, .{
            .permissions = opts.permissions,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.DeviceBusy => continue,
            error.FileBusy => continue,

            error.IsDir => return error.Unexpected, // No path components.
            error.FileTooBig => return error.Unexpected, // Creating, not opening.
            error.FileLocksUnsupported => return error.Unexpected, // Not asking for locks.
            error.PipeBusy => return error.Unexpected, // Not opening a pipe.

            else => |e| return e,
        };
        return .{
            .file = file,
            .file_basename_hex = random_integer,
            .dest_sub_path = dest_path,
            .file_open = true,
            .file_exists = true,
            .close_dir_on_deinit = close_on_deinit,
            .dir = target_dir,
        };
    }
}

pub const AccessPathError = TryMountError || error{
    ReadOnlyFileSystem,
    FileNotFound,
    NameTooLong,
    BadPathName,
    AccessDenied,
};

/// Assumes `lock` is held as non-shareable.
pub fn accessPath(storage: *Storage, gpa: std.mem.Allocator, parent_dir: Descriptor, sub_path: []const u8, read: bool, write: bool) AccessPathError!void {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;
    
    const maybe_device, const device_path = try splitParsePath(sub_path);
    const maybe_dir_desc = try storage.getDirectoryDescription(parent_dir); 
    const device = maybe_device orelse if (maybe_dir_desc) |desc| 
        desc.flags.device
    else
        return error.NoDevice;

    try storage.tryMount(gpa, device); 

    switch (device) {
        .romfs => {
            const parent: romfs.View.Directory = if (Io.Dir.path.isAbsolutePosix(device_path)) 
                .root
            else maybe_dir_desc.?.stored.romfs.asDirectory(); // We already return NoDevice above

            var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
            const utf16_device_path = utf16_device_path_buffer[0..std.unicode.utf8ToUtf16Le(&utf16_device_path_buffer, device_path) catch return error.BadPathName];
            _ = try storage.device.romfs.openAny(parent, utf16_device_path);

            if (write) return error.ReadOnlyFileSystem;
        },
        .sdmc => {
            const fs = storage.fs;
            const archive = storage.device.archive(device).?.*;

            var builder: Builder = .init;
            const path_z = try storage.buildPath(&builder, device_path, maybe_dir_desc);

            // NOTE: We already check in tryMount that fs is valid and we've opened the archive.
            if (std.mem.eql(u16, path_z, Builder.root)) return if (write) error.AccessDenied;

            var current_read = read;

            while (true) {
                if(fs.sendOpenFile(0, archive, .utf16, @ptrCast(path_z), .{
                    .read = current_read,
                    .write = write,
                    .create = false,
                }, .{})) |file| {
                    file.close();
                    return;
                } else |err| switch (err) {
                    error.IsDir => return if (write) error.AccessDenied,
                    error.FileNotFound => |e| return e,
                    // NOTE: It seems we can't access a file sometimes without `read`
                    error.UnexpectedOpenFlags => {
                        if (current_read) return error.Unexpected;
                        current_read = true;
                    },
                    else => return error.Unexpected,
                    // TODO: We have to map the errors in OpenFile
                }
            }
        },
    }
}

pub const ModifyPathOperation = enum {
    create_dir,
    delete_dir,
    delete_file,
};

pub const ModifyError = TryMountError || error{
    ReadOnlyFileSystem,
    FileNotFound,
    PathAlreadyExists,
    NameTooLong,
    BadPathName,
    IsDir,
    NotDir,
};

/// Assumes `lock` is held as non-shareable.
pub fn modifyPath(storage: *Storage, gpa: std.mem.Allocator, parent_dir: Descriptor, sub_path: []const u8, operation: ModifyPathOperation) ModifyError!void {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;

    const maybe_device, const device_path = try splitParsePath(sub_path);
    const maybe_dir_desc = try storage.getDirectoryDescription(parent_dir); 
    const device = maybe_device orelse if (maybe_dir_desc) |desc| 
        desc.flags.device
    else
        return error.NoDevice;

    try storage.tryMount(gpa, device);

    switch (device) {
        .romfs => return error.ReadOnlyFileSystem,
        .sdmc => {
            const fs = storage.fs;
            const archive = storage.device.archive(device).?.*;

            var builder: Builder = .init;
            const path_z = try storage.buildPath(&builder, device_path, maybe_dir_desc);

            switch (operation) {
                .create_dir => fs.sendCreateDirectory(0, archive, .utf16, @ptrCast(path_z), .{}) catch |err| switch(err) {
                    error.FileNotFound, error.PathAlreadyExists => |e| return e,
                    else => return error.Unexpected,
                },
                .delete_dir => fs.sendDeleteDirectory(0, archive, .utf16, @ptrCast(path_z)) catch |err| switch(err) {
                    error.FileNotFound, error.NotDir => |e| return e,
                    else => return error.Unexpected,
                },
                .delete_file => fs.sendDeleteFile(0, archive, .utf16, @ptrCast(path_z)) catch |err| switch(err) {
                    error.FileNotFound, error.IsDir => |e| return e,
                    else => return error.Unexpected,
                },
            }
        },
    }
}

/// Assumes `lock` is held as non-shareable.
pub fn renamePath(storage: *Storage, gpa: std.mem.Allocator, src_parent_dir: Descriptor, src_path: []const u8, dst_parent_dir: Descriptor, dst_path: []const u8, preserve: bool) Io.Dir.RenamePreserveError!void {
    if (src_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (src_path.len == 0) return error.BadPathName;
    if (dst_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (dst_path.len == 0) return error.BadPathName;

    const maybe_src_dir_desc = try storage.getDirectoryDescription(src_parent_dir); 
    const maybe_dst_dir_desc = try storage.getDirectoryDescription(dst_parent_dir); 

    const maybe_src_device, const src_device_path = try splitParsePath(src_path);
    const src_device = maybe_src_device orelse if (maybe_src_dir_desc) |desc| 
        desc.flags.device
    else
        return error.NoDevice;

    const maybe_dst_device, const dst_device_path = try splitParsePath(dst_path);
    const dst_device = maybe_dst_device orelse if (maybe_dst_dir_desc) |desc| 
        desc.flags.device
    else
        return error.NoDevice;

    if (src_device != dst_device) return error.CrossDevice;

    try storage.tryMount(gpa, src_device);
    try storage.tryMount(gpa, dst_device);

    switch (dst_device) {
        .romfs => return error.ReadOnlyFileSystem,
        .sdmc => {
            const fs = storage.fs;
            const src_archive = storage.device.archive(src_device).?.*;
            const dst_archive = storage.device.archive(dst_device).?.*;

            var src_builder: Builder = .init;
            const src_path_z = try storage.buildPath(&src_builder, src_device_path, maybe_src_dir_desc);
            
            var dst_builder: Builder = .init;
            const dst_path_z = try storage.buildPath(&dst_builder, dst_device_path, maybe_dst_dir_desc);

            rename_file: while (true) {
                if (fs.sendRenameFile(0, src_archive, dst_archive, .utf16, @ptrCast(src_path_z), .utf16, @ptrCast(dst_path_z))) |_| {
                    return;
                } else |err| switch (err) {
                    error.PathAlreadyExists => |e| {
                        if (preserve) return e;

                        if (fs.sendDeleteFile(0, dst_archive, .utf16, @ptrCast(dst_path_z))) |_| {
                            continue :rename_file;
                        } else |del_err| switch (del_err) {
                            error.IsDir => |de| return de,
                            else => return error.Unexpected,
                        }
                    },
                    // This can also happen in src_path points to a directory so lets try to delete it.
                    error.FileNotFound => break :rename_file,
                    else => return error.Unexpected,
                }
            }

            rename_dir: while (true) {
                if (fs.sendRenameDirectory(0, src_archive, dst_archive, .utf16, @ptrCast(src_path_z), .utf16, @ptrCast(dst_path_z))) |_| {
                    return;
                } else |err| switch (err) {
                    error.PathAlreadyExists => |e| {
                        if (preserve) return e;

                        if (fs.sendDeleteDirectory(0, dst_archive, .utf16, @ptrCast(dst_path_z))) |_| {
                            continue :rename_dir;
                        } else |del_err| switch (del_err) {
                            error.NotDir => |de| return de,
                            else => return error.Unexpected,
                        }
                    },
                    // src_path truly doesn't exist, we've already tried files
                    error.FileNotFound => |e| return e,
                    else => return error.Unexpected,
                }
            }
        },
    }
}

/// Assumes `lock` is held as non-shareable.
pub fn createDirPath(storage: *Storage, gpa: std.mem.Allocator, parent_dir: Descriptor, sub_path: []const u8) Io.Dir.CreateDirPathError!Io.Dir.CreatePathStatus {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;

    const maybe_device, const device_path = try splitParsePath(sub_path);
    const maybe_dir_desc = try storage.getDirectoryDescription(parent_dir); 
    const device = maybe_device orelse if (maybe_dir_desc) |desc| 
        desc.flags.device
    else
        return error.NoDevice;

    try storage.tryMount(gpa, device);

    switch (device) {
        .romfs => return error.ReadOnlyFileSystem,
        .sdmc => {
            const fs = storage.fs;
            const archive = storage.device.archive(device).?.*;

            const parent: []const u16 = if (Io.Dir.path.isAbsolutePosix(device_path))
                Builder.root
            else switch (maybe_dir_desc.?.stored.path) { // We already return NoDevice above
                .invalid => Builder.root,
                _ => |open| storage.paths.list.items[@intFromEnum(open)].value,
            };

            // + 1 for the NUL-terminator
            if (parent.len + device_path.len + 1 > Io.Dir.max_path_bytes) return error.NameTooLong;

            var builder: Builder = .init;
            try builder.appendRaw(parent[0..parent.len - 1]); // Remove the NULL terminator as we don't need it here.
            const parent_end = builder.end;
            try builder.append(device_path);

            const path_z = try builder.nullTerminate();
            const path: []const u16 = builder.path();

            var it: Io.Dir.path.ComponentIterator(.posix, u16) = .init(path[parent_end..]);
            var status: Io.Dir.CreatePathStatus = .existed;
            var component = it.last() orelse return error.BadPathName;

            while (true) {
                // NOTE: This looks weird (and is brittle...) but this way we don't have to allocate an intermediate buffer!
                const current_path_z = path_z[0..parent_end + component.path.len + 1];

                const last = path_z[parent_end + component.path.len];
                path_z[parent_end + component.path.len] = 0;

                if (fs.sendCreateDirectory(0, archive, .utf16, @ptrCast(current_path_z), .{})) |_| {
                    status = .created;
                } else |err| switch (err) {
                    error.PathAlreadyExists => exists: {
                        (fs.sendOpenFile(0, archive, .utf16, @ptrCast(current_path_z), .{
                            .read = true,
                        }, .{}) catch |ferr| switch (ferr) {
                            error.IsDir => break :exists,
                            error.FileNotFound => |e| return e,
                            else => return error.Unexpected,
                        }).close();

                        return error.NotDir;
                    },
                    error.FileNotFound => |e| {
                        path_z[parent_end + component.path.len] = last;
                        component = it.previous() orelse return e;
                        continue;
                    },
                    else => return error.Unexpected,
                }

                path_z[parent_end + component.path.len] = last;
                component = it.next() orelse return status;
            }
        },
    }
}

/// Assumes `lock` is held as shareable.
pub fn readDir(storage: *Storage, r: *Io.Dir.Reader, entries: []Io.Dir.Entry) Io.Dir.Reader.Error!usize {
    std.debug.assert(r.buffer.len > @sizeOf(Description.Extra.Directory.NameBuffer));

    const handle = r.dir.handle; 
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .file => return error.Unexpected,
        .directory => switch (desc.flags.device) {
            .romfs => {
                switch (r.state) {
                    .finished => return 0,
                    .reset => {
                        desc.extra.dir.romfs = desc.stored.romfs.asDirectory().iterator(storage.device.romfs.view);

                        r.state = .reading;
                        r.end = 0;
                        r.index = 0;
                    },
                    .reading => {},
                }

                const bytes = r.buffer;

                var consumed: usize = 0;
                var i: usize = 0;
                while (i < entries.len) {
                    const e = desc.extra.dir.romfs.next(storage.device.romfs.view) orelse {
                        r.state = .finished;
                        break;
                    };

                    const utf16_name = e.name(storage.device.romfs.view);
                    if (utf16_name.len * 2 > (bytes.len - consumed)) break;

                    const name_len = std.unicode.utf16LeToUtf8(bytes[consumed..], utf16_name) catch return error.Unexpected;

                    entries[i] = .{
                        .name = bytes[consumed..][0..name_len],
                        .inode = {},
                        .kind = switch (e.kind) {
                            .file => .file,
                            .directory => .directory,
                        },
                    };

                    consumed += name_len;
                    i += 1;
                }

                return i;
            },
            .sdmc => {
                const fs = storage.fs;
                const dir = &desc.extra.dir.archive;
                const archive = storage.device.archive(desc.flags.device).?.*;
                const path_z: []const u16 = switch (desc.stored.path) {
                    .invalid => Builder.root,
                    _ => |idx| storage.paths.list.items[@intFromEnum(idx)].value,
                };

                switch (r.state) {
                    .finished => return 0,
                    .reset => {
                        if (desc.extra.dir.archive != Filesystem.Directory.none) {
                            dir.close();
                            dir.* = .none;
                        }

                        r.state = .reading;
                        r.end = @sizeOf(Description.Extra.Directory.NameBuffer);
                        r.index = r.end;
                    },
                    .reading => {},
                }

                if (dir.* == Filesystem.Directory.none) {
                    dir.* = fs.sendOpenDirectory(archive, .utf16, @ptrCast(path_z)) catch |err| switch (err) {
                        // This can happen if the directory is deleted while iterating.
                        error.FileNotFound => {
                            r.state = .finished;
                            return 0;
                        },
                        else => return error.Unexpected,
                    };
                }
                
                const bytes = r.buffer[0..@sizeOf(Description.Extra.Directory.NameBuffer)];
                
                var consumed: usize = 0;
                var i: usize = 0;
                while (i < entries.len) {
                    if (r.end - r.index < @sizeOf(Filesystem.Directory.Entry)) {
                        const entries_buf: []align(@alignOf(usize)) Filesystem.Directory.Entry = buf: {
                            const remaining = r.buffer[@sizeOf(Description.Extra.Directory.NameBuffer)..];
                            // NOTE: This is always aligned as it has @alignOf(u32) and the name buffer is aligned to 4 bytes.
                            const entry_ptr: [*]align(@alignOf(usize)) Filesystem.Directory.Entry = @alignCast(@ptrCast(remaining.ptr));
                            break :buf entry_ptr[0..(remaining.len / @sizeOf(Filesystem.Directory.Entry))];
                        };

                        const read = dir.sendRead(entries_buf) catch return error.Unexpected;

                        if (read == 0) {
                            dir.close();
                            dir.* = .none;

                            r.state = .finished;
                            r.end = 0;
                            r.index = r.end;
                            return 0;
                        }

                        r.end = @sizeOf(Description.Extra.Directory.NameBuffer) + read * @sizeOf(Filesystem.Directory.Entry);
                        r.index = @sizeOf(Description.Extra.Directory.NameBuffer);
                    }

                    const entry: *align(@alignOf(usize)) Filesystem.Directory.Entry = @alignCast(@ptrCast(r.buffer[r.index..][0..@sizeOf(Filesystem.Directory.Entry)]));
                    const utf16_name = entry.utf16_name[0..std.mem.findScalar(u16, &entry.utf16_name, 0) orelse entry.utf16_name.len];
                    if (utf16_name.len * 2 > (bytes.len - consumed)) break;

                    const name_len = std.unicode.utf16LeToUtf8(bytes[consumed..], utf16_name) catch return error.Unexpected;

                    entries[i] = .{
                        .name = bytes[consumed..][0..name_len],
                        .inode = {},
                        .kind = if (entry.attributes.directory) .directory else .file,
                    };

                    r.index += @sizeOf(Filesystem.Directory.Entry);
                    consumed += name_len;
                    i += 1;
                }

                return i;
            },
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn length(storage: *Storage, handle: Descriptor) Io.File.LengthError!u64  {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => 0,
        .file => switch (desc.flags.device) {
            .romfs => desc.stored.romfs.asFile().stat(storage.device.romfs.view).size,
            .sdmc => desc.stored.file.sendGetSize() catch return error.Unexpected,
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn stat(storage: *Storage, handle: Descriptor) Io.File.StatError!Io.File.Stat {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => .{
            .inode = {},
            .nlink = 0,
            .size = 0,
            .permissions = .default_dir,
            .kind = .directory,
            .atime = null,
            .mtime = .fromNanoseconds(0),
            .ctime = .fromNanoseconds(0),
            .block_size = 512,
        },
        .file => switch (desc.flags.device) {
            .romfs => .{
                .inode = {},
                .nlink = 0,
                .size = desc.stored.romfs.asFile().stat(storage.device.romfs.view).size,
                .permissions = .default_file,
                .kind = .file,
                .atime = null,
                .mtime = .fromNanoseconds(0),
                .ctime = .fromNanoseconds(0),
                .block_size = 512,
            },
            .sdmc => .{
                .inode = {},
                .nlink = 0,
                .size = desc.stored.file.sendGetSize() catch return error.Unexpected,
                .permissions = .default_file,
                .kind = .file,
                .atime = null,
                .mtime = .fromNanoseconds(0), // TODO: We can technically get the mtime through ControlArchive
                .ctime = .fromNanoseconds(0),
                .block_size = 512,
            },
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn setLength(storage: *Storage, handle: Descriptor, new_length: u64) Io.File.SetLengthError!void {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => return error.NonResizable,
        .file => switch (desc.flags.device) {
            .romfs => return error.NonResizable,
            .sdmc => desc.stored.file.sendSetSize(new_length) catch return error.Unexpected,
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn readPositional(storage: *Storage, handle: Descriptor, buffer: []u8, offset: u64) Io.File.ReadPositionalError!usize {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => error.IsDir,
        .file => switch (desc.flags.device) {
            .romfs => storage.device.romfs.readPositional(desc.stored.romfs.asFile(), offset, buffer) catch |e| switch (e) {
                else => error.Unexpected,
            },
            .sdmc => desc.stored.file.sendRead(offset, buffer) catch |e| switch (e) {
                else => error.Unexpected,
            },
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn writePositional(storage: *Storage, handle: Descriptor, buffer: []const u8, offset: u64) Io.File.WritePositionalError!usize {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => error.NotOpenForWriting,
        .file => switch (desc.flags.device) {
            .romfs => error.NotOpenForWriting,
            .sdmc => desc.stored.file.sendWrite(offset, buffer, .{}) catch |e| switch (e) {
                else => error.Unexpected,
            },
        }
    };
}

/// Assumes `lock` is held as shareable.
pub fn readStreaming(storage: *Storage, handle: Descriptor, buffer: []u8) Io.Operation.FileReadStreaming.Result {
    const desc = try storage.getDescription(handle);

    // NOTE: This is NOT fully atomic, its the user's fault if seek races occur.
    // I only guarantee that the 64-bit stores and loads are atomic.

    return switch (desc.flags.kind) {
        .directory => error.IsDir,
        .file => switch (desc.flags.device) {
            .romfs => blk: {
                const seek = &desc.extra.seek;
                const initial_offset = seek.load();
                const read = storage.device.romfs.readPositional(desc.stored.romfs.asFile(), initial_offset, buffer) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                if (read == 0) return error.EndOfStream;

                while (true) {
                    _ = seek.load();
                    if (!seek.store(initial_offset + read)) break;
                }

                break :blk read; 
            },
            .sdmc => blk: {
                const seek = &desc.extra.seek;
                const initial_offset = seek.load();
                const read = desc.stored.file.sendRead(initial_offset, buffer) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                if (read == 0) return error.EndOfStream;
                while (true) {
                    _ = seek.load();
                    if (!seek.store(initial_offset + read)) break;
                }

                break :blk read; 
            },
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn writeStreaming(storage: *Storage, handle: Descriptor, buffer: []const u8) Io.Operation.FileWriteStreaming.Result {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => return error.NotOpenForWriting,
        .file => switch (desc.flags.device) {
            .romfs => return error.NotOpenForWriting,
            .sdmc => blk: {
                const seek = &desc.extra.seek;
                const initial_offset = seek.load();
                const written = desc.stored.file.sendWrite(initial_offset, buffer, .{}) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                while (true) {
                    _ = seek.load();
                    if (!seek.store(initial_offset + written)) break;
                }

                break :blk written; 
            },
        }
    };
}

/// Assumes `lock` is held as shareable.
pub fn seekBy(storage: *Storage, handle: Descriptor, offset: i64) Io.File.SeekError!void {
    const desc = try storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .directory => return error.Unseekable,
        .file => {
            while (true) {
                const seek = &desc.extra.seek;
                const last: i64 = @bitCast(seek.load());
                const new: u65 = @bitCast(std.math.add(i65, last, offset) catch return error.Unseekable);
                if (last > 0 and new < 0) return error.Unseekable;
                if (!seek.store(@truncate(new))) break;
            }
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn seekTo(storage: *Storage, handle: Descriptor, offset: u64) Io.File.SeekError!void {
    const desc = try storage.getDescription(handle);

    switch (desc.flags.kind) {
        .directory => return error.Unseekable,
        .file => while (true) {
            const seek = &desc.extra.seek;
            _ = seek.load();
            if (!seek.store(offset)) break;
        },
    }
}

/// Assumes `lock` is held as non-shareable.
pub fn close(storage: *Storage, gpa: std.mem.Allocator, handle: Descriptor) void {
    const index = switch(handle) {
        .invalid, .cwd => programmerBug("invalid fd") catch return, // cwd is only valid in open
        _ => storage.fds.items[@intFromEnum(handle)],
    };

    storage.closeDescription(gpa, index);
    storage.fds.items[@intFromEnum(handle)] = .invalid;
}

/// Assumes `lock` is held as non-shareable.
pub fn setCurrentDir(storage: *Storage, gpa: std.mem.Allocator, handle: Descriptor) error{Unexpected}!void {
    const index = switch(handle) {
        .invalid, .cwd => return programmerBug("invalid fd"), // cwd is only valid in open
        _ => storage.fds.items[@intFromEnum(handle)],
    }; 

    const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
    std.debug.assert(desc.flags.kind == .directory);
    std.debug.assert(desc.ref.fetchAdd(1, .monotonic) > 0);

    const last_cwd = storage.cwd;
    storage.cwd = index;

    log.debug("cwd {} -> {}", .{last_cwd, storage.cwd});

    switch (last_cwd) {
        .invalid => {},
        _ => |open| storage.closeDescription(gpa, open),
    }
}

fn splitParsePath(path: []const u8) error{BadPathName}!struct { ?Device.Kind, []const u8 } {
    return if (std.mem.findScalar(u8, path, '/')) |first_slash| dev: {
        break :dev if (std.mem.findScalar(u8, path[0..first_slash], ':')) |first_colon| {
            if (first_colon != first_slash - 1) return error.BadPathName;
            
            break :dev .{ std.meta.stringToEnum(Device.Kind, path[0..first_colon]) orelse return error.BadPathName, path[(first_colon + 1)..] };
        } else .{ null, path };
    } else .{ null, path };
}

/// Buils a full path, returns the final path from `Builder.nullTerminator`
fn buildPath(storage: *Storage, builder: *Builder, device_path: []const u8, maybe_desc: ?*Description) error{NameTooLong, BadPathName}![]u16 {
    const parent: []const u16 = if (Io.Dir.path.isAbsolutePosix(device_path))
        Builder.root
    else switch (maybe_desc.?.stored.path) { // We already return NoDevice above
        .invalid => Builder.root,
        _ => |open| storage.paths.list.items[@intFromEnum(open)].value,
    };

    // + 1 for the NUL-terminator
    if (parent.len + device_path.len + 1 > Io.Dir.max_path_bytes) return error.NameTooLong;

    try builder.appendRaw(parent[0..parent.len - 1]); // Remove the NULL terminator as we don't need it
    try builder.append(device_path);

    return try builder.nullTerminate();
}

fn getDescription(storage: *Storage, handle: Descriptor) Io.UnexpectedError!*Description {
    return switch(handle) {
        .invalid, .cwd => return programmerBug("invalid fd"), // cwd is only valid in open
        _ => switch (storage.fds.items[@intFromEnum(handle)]) {
            .invalid => return programmerBug("fd not pointing to anything, possibly UAF"),
            else => |idx| &storage.descriptions.list.items[@intFromEnum(idx)].value,
        },
    };
}

/// May return null if `cwd` is unlinked
fn getDirectoryDescription(storage: *Storage, handle: Descriptor) Io.UnexpectedError!?*Description {
    const dir_index = switch(handle) {
        .invalid => return programmerBug("invalid dir"),
        .cwd => storage.cwd,
        _ => |opened| blk: {
            // Only cwd is allowed to be invalid (only at the start, after setting it it is always available as you can't close it)
            std.debug.assert(opened != .invalid); 
            break :blk storage.fds.items[@intFromEnum(opened)];
        },
    };

    return switch (dir_index) {
        .invalid => null,
        _ => blk: {
            const desc = &storage.descriptions.list.items[@intFromEnum(dir_index)].value;
            if (desc.flags.kind != .directory) return programmerBug("non-dir fd");
            break :blk desc;
        },
    };
}

fn closeDescription(storage: *Storage, gpa: Allocator, index: Description.Table.Index) void {
    std.debug.assert(index != .invalid); // UAF

    const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
    std.debug.assert(desc.ref.load(.monotonic) > 0);

    if (desc.ref.fetchSub(1, .monotonic) == 1) {
        switch (desc.flags.device) {
            .romfs => {}, // Opened files/directories are just offsets.
            .sdmc => switch(desc.flags.kind) {
                .directory => free: {
                    if (desc.extra.dir.archive != Filesystem.Directory.none) desc.extra.dir.archive.close();

                    const idx = switch (desc.stored.path) {
                        .invalid => break :free,
                        _ => |idx| idx,
                    };
                    defer storage.paths.free(idx);

                    const path = storage.paths.list.items[@intFromEnum(idx)].value;
                    gpa.free(path);
                },
                .file => desc.stored.file.close(),
            },
        }

        log.debug("description {d} closed ({}, {})", .{@intFromEnum(index), desc.flags.device, desc.flags.kind});
        storage.descriptions.free(index);
    }
}

fn allocateLowestDescriptor(storage: *Storage, gpa: Allocator) Allocator.Error!Descriptor {
    for (storage.fds.items, 0..) |item, i| if (item == .invalid) {
        return @enumFromInt(i);
    };

    _ = try storage.fds.addOne(gpa);
    return @enumFromInt(storage.fds.items.len - 1);
}

pub const TryMountError = error{NoDevice, SystemResources, Unexpected};

fn tryMount(storage: *Storage, gpa: std.mem.Allocator, kind: Device.Kind) TryMountError!void {
    if (storage.fs.session == horizon.ClientSession.none) return error.NoDevice;

    switch (kind) {
        .romfs => if (storage.device.romfs.file == Filesystem.File.none) {
            storage.device.romfs = Filesystem.RomFs.initSelf(storage.fs, gpa) catch |err| switch (err) {
                error.NoRomFs => return error.NoDevice,
                error.OutOfMemory => return error.SystemResources,
                else => return error.Unexpected,
            };
        },
        .sdmc => {
            const dev = storage.device.archive(kind).?;

            switch (dev.*) {
                .none => dev.* = storage.fs.sendOpenArchive(kind.archiveId().?, .empty, &.{}) catch return error.Unexpected,
                _ => {}, // nothing to do
            }
        }
    }
}

fn Table(comptime T: type) type {
    return struct {
        pub const empty: TableSelf = .{
            .list = .empty,
            .first_free = .invalid,
            .last_free = .invalid,
        };

        pub const Index = enum(u32) {
            invalid = std.math.maxInt(u32),
            _,
        };

        pub const Item = union {
            value: T,
            next: Index,
        };

        list: std.ArrayList(Item),
        first_free: Index,
        last_free: Index,

        pub fn deinit(table: *TableSelf, gpa: Allocator) void {
            table.list.deinit(gpa);
            table.* = .empty;
        }

        pub fn allocateOne(table: *TableSelf, gpa: Allocator) Allocator.Error!Index {
            if (table.first_free == .invalid) try table.list.ensureUnusedCapacity(gpa, 1);
            return table.allocateOneAssumeCapacity();
        }

        pub fn allocateOneAssumeCapacity(table: *TableSelf) Index {
            return switch (table.first_free) {
                .invalid => blk: {
                    std.debug.assert(table.last_free == .invalid);
                    _ = table.list.addOneAssumeCapacity();
                    break :blk @enumFromInt(table.list.items.len - 1);
                },
                _ => |one_free| blk: {
                    const freed = &table.list.items[@intFromEnum(one_free)];

                    switch (freed.next) {
                        .invalid => {
                            std.debug.assert(table.last_free == one_free);

                            table.first_free = .invalid;
                            table.last_free = .invalid;
                        },
                        _ => |next_free| table.first_free = next_free,
                    }

                    break :blk one_free;
                }
            };
        }

        pub fn free(table: *TableSelf, index: Index) void {
            std.debug.assert(index != .invalid);
            table.list.items[@intFromEnum(index)] = .{ .next = .invalid };

            switch (table.last_free) {
                .invalid => {
                    std.debug.assert(table.first_free == .invalid);

                    table.first_free = index;
                    table.last_free = index;
                }, 
                _ => {
                    table.list.items[@intFromEnum(table.last_free)].next = index;
                    table.last_free = index; 
                },
            }
        }

        const TableSelf = @This();
    };
}

fn programmerBug(msg: []const u8) Io.UnexpectedError {
    if (is_debug) std.debug.panic("programmer bug: {s}", .{msg});
    return error.Unexpected;
}

const testing = std.testing;

const is_debug = builtin.mode == .Debug;
const Storage = @This();
const log = std.log.scoped(.io_storage);

const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const romfs = horizon.fmt.ncch.romfs;
const Filesystem = horizon.services.Filesystem;
