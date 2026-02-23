pub const empty: Storage = .init(.{ .session = .none });

pub const Descriptor = enum(u32) {
    invalid = std.math.maxInt(u32),
    cwd = std.math.maxInt(u32) - 1,
    _,
};

/// State of a file in the table
pub const Description = struct {
    pub const Table = Storage.Table(Description);
    pub const Stored = packed union {
        romfs: romfs.View.Entry,
        file: Filesystem.File,
        path: Path.Table.Index,
    };

    pub const Flags = packed struct {
        pub const Kind = enum(u1) { file, directory };

        device: Device.Kind,
        kind: Kind,
    };

    ref: std.atomic.Value(u16),
    flags: Flags,
    stored: Stored,
    // XXX: I would like to use atomics but its an upstream issue...
    seek: zitrus.hardware.cpu.arm11.Monitor(u64),
};

pub const Path = struct {
    pub const root: Path = .{ .utf16 = &.{'/'} };
    pub const Table = Storage.Table(Path);

    utf16: []const u16, 
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
paths: Path.Table = .empty,

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
        _ => |idx| storage.closeDescription(idx),
    }

    storage.paths.deinit(gpa);
    storage.descriptions.deinit(gpa);
    storage.fds.deinit(gpa);
    storage.device.deinit(gpa, storage.fs);
    storage.fs.close();
    storage.* = .empty;
}

pub const OpenPathError = error{
    // XXX: We should be using ReadOnlyFileSystem but it seems std.Io doesn't have that error?
    AccessDenied,
    SystemResources,
    FileNotFound,
    NoDevice,
    BadPathName,
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

    mode: Io.File.OpenMode,
    allow: Allow,
};

/// The format is `device:/PATH/TO/FILE`.
/// The device name is optional and will be that of `dir` if ommited.
/// `cwd` may be unlinked, if so trying to open a non-device path will fail with `error.NoDevice`
///
/// Assumes `lock` is held as non-shareable.
pub fn openPath(storage: *Storage, gpa: std.mem.Allocator, parent_dir: Descriptor, path: []const u8, opts: OpenFlags) OpenPathError!Descriptor {
    if (path.len > Io.Dir.max_path_bytes) return error.NameTooLong;

    const fd = storage.allocateLowestDescriptor(gpa) catch return error.SystemResources;
    errdefer storage.fds.items[@intFromEnum(fd)] = .invalid;

    const free_desc = storage.descriptions.allocateOne(gpa) catch return error.SystemResources;
    errdefer storage.descriptions.free(free_desc);

    storage.fds.items[@intFromEnum(fd)] = free_desc;

    const desc: Description = des: {
        const maybe_device, const device_path = if (std.mem.findScalar(u8, path, '/')) |first_slash| dev: {
            break :dev if (std.mem.findScalar(u8, path[0..first_slash], ':')) |first_colon| {
                if (first_colon != first_slash - 1) return error.BadPathName;
                
                break :dev .{ std.meta.stringToEnum(Device.Kind, path[0..first_colon]) orelse return error.BadPathName, path[(first_colon + 1)..] };
            } else .{ null, path };
        } else .{ null, path };

        const dir_index = switch(parent_dir) {
            .invalid => return programmerBug("invalid dir to open"),
            .cwd => storage.cwd,
            _ => |opened| blk: {
                // Only cwd is allowed to be invalid (only at the start, after setting it it is always available as you can't close it)
                std.debug.assert(opened != .invalid); 
                break :blk storage.fds.items[@intFromEnum(opened)];
            },
        };

        const dir_desc = switch (dir_index) {
            .invalid => null,
            _ => &storage.descriptions.list.items[@intFromEnum(dir_index)].value,
        };

        const device = maybe_device orelse if (dir_desc) |desc| 
            desc.flags.device
        else
            return error.NoDevice;

        try storage.tryMount(gpa, device);

        switch (device) {
            .romfs => {
                const parent: romfs.View.Directory = if (Io.Dir.path.isAbsolutePosix(device_path)) 
                    .root
                else dir_desc.?.stored.romfs.asDirectory(); // We already return NoDevice above

                var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
                const utf16_device_path = utf16_device_path_buffer[0..std.unicode.utf8ToUtf16Le(&utf16_device_path_buffer, device_path) catch return error.BadPathName];
                const entry = try storage.device.romfs.openAny(parent, utf16_device_path);

                if ((opts.allow == .file or opts.mode != .read_only) and entry.kind == .directory) return error.IsDir;
                if ((opts.allow == .directory) and entry.kind == .file) return error.NotDir;
                if (opts.mode != .read_only) return error.AccessDenied; // XXX: pluh... and ReadOnlyFileSystem?

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
                    .seek = .init(0),
                };
            },
            .sdmc => {
                const fs = storage.fs;
                const parent: Path = if (Io.Dir.path.isAbsolutePosix(device_path))
                    .root
                else switch (dir_desc.?.stored.path) { // We already return NoDevice above
                    .invalid => unreachable,
                    _ => |open| storage.paths.list.items[@intFromEnum(open)].value,
                };

                // + 1 for the NUL-terminator
                if (parent.utf16.len + device_path.len + 1 > Io.Dir.max_path_bytes) return error.SystemResources;

                var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
                @memcpy(utf16_device_path_buffer[0..parent.utf16.len], parent.utf16);

                const second_path: []const u8 = if (device_path.len > 0 and device_path[0] == '/') device_path[1..] else device_path;
                const end = std.unicode.utf8ToUtf16Le(utf16_device_path_buffer[parent.utf16.len..], second_path) catch return error.BadPathName;
                utf16_device_path_buffer[parent.utf16.len + end] = 0;

                const utf16_path = utf16_device_path_buffer[0..parent.utf16.len + end + 1];
                const archive = storage.device.archive(device).?.*;

                // NOTE: We already check in tryMount that fs is valid and we've opened the archive.

                file: {
                    const file = fs.sendOpenFile(0, archive, .utf16, @ptrCast(utf16_path), .{
                        .read = opts.mode != .write_only,
                        .write = opts.mode != .read_only,
                        .create = false,
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
                        .seek = .init(0),
                    };
                }

                const dir = fs.sendOpenDirectory(archive, .utf16, @ptrCast(utf16_path)) catch |err| switch (err) {
                    error.FileNotFound => unreachable, // we already check above if it is not found?
                    else => return error.Unexpected,
                };
                defer dir.close();

                if (opts.allow == .file or opts.mode != .read_only) return error.IsDir;

                const stored_path = storage.paths.allocateOne(gpa) catch return error.SystemResources;
                errdefer storage.paths.free(stored_path);
                
                if (true) @panic("TODO: archive directories");

                break :des .{
                    .ref = .init(1),
                    .stored = .{ .path = .invalid },
                    .flags = .{
                        .device = device,
                        .kind = .file,
                    },
                    .seek = .init(0),
                };
            },
        }
    };

    storage.descriptions.list.items[@intFromEnum(free_desc)] = .{ .value = desc };
    return fd;
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
                const initial_offset = desc.seek.load();

                const read = storage.device.romfs.readPositional(desc.stored.romfs.asFile(), initial_offset, buffer) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                if (read == 0) return error.EndOfStream;

                while (true) {
                    const offset = desc.seek.load();

                    if (!desc.seek.store(offset + read)) break;
                }

                break :blk read; 
            },
            .sdmc => blk: {
                const initial_offset = desc.seek.load();

                const read = desc.stored.file.sendRead(initial_offset, buffer) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                if (read == 0) return error.EndOfStream;
                while (true) {
                    const offset = desc.seek.load();
                    if (!desc.seek.store(offset + read)) break;
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
                const initial_offset = desc.seek.load();
                const written = desc.stored.file.sendWrite(initial_offset, buffer, .{}) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                while (true) {
                    const offset = desc.seek.load();
                    if (!desc.seek.store(offset + written)) break;
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
                const last: i64 = @bitCast(desc.seek.load());
                const new: u65 = @bitCast(std.math.add(i65, last, offset) catch return error.Unseekable);
                if (last > 0 and new < 0) return error.Unseekable;
                if (!desc.seek.store(@truncate(new))) break;
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
            _ = desc.seek.load();
            if (!desc.seek.store(offset)) break;
        },
    }
}

/// Assumes `lock` is held as non-shareable.
pub fn close(storage: *Storage, handle: Descriptor) void {
    const index = switch(handle) {
        .invalid, .cwd => unreachable, // cwd is only valid in open
        _ => storage.fds.items[@intFromEnum(handle)],
    };

    storage.closeDescription(index);
    storage.fds.items[@intFromEnum(handle)] = .invalid;
}

/// Assumes `lock` is held as non-shareable.
pub fn setCurrentDir(storage: *Storage, handle: Descriptor) void {
    const index = switch(handle) {
        .invalid, .cwd => unreachable, // cwd is only valid in open
        _ => storage.fds.items[@intFromEnum(handle)],
    }; 

    const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
    std.debug.assert(desc.ref.fetchAdd(1, .monotonic) > 0);

    const last_cwd = storage.cwd;
    storage.cwd = index;

    log.debug("cwd {} -> {}", .{last_cwd, storage.cwd});

    switch (last_cwd) {
        .invalid => {},
        _ => |open| storage.closeDescription(open),
    }
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

fn closeDescription(storage: *Storage, index: Description.Table.Index) void {
    std.debug.assert(index != .invalid); // UAF

    const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
    std.debug.assert(desc.ref.load(.monotonic) > 0);

    if (desc.ref.fetchSub(1, .monotonic) == 1) {
        switch (desc.flags.device) {
            .romfs => {}, // Opened files/directories are just offsets.
            .sdmc => switch(desc.flags.kind) {
                .directory => {},
                .file => desc.stored.file.close(),
            },
        }

        log.debug("description {d} closed", .{@intFromEnum(index)});
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

pub const TryMountError = error{NoDevice, Unexpected};

fn tryMount(storage: *Storage, gpa: std.mem.Allocator, kind: Device.Kind) TryMountError!void {
    if (storage.fs.session == horizon.ClientSession.none) return error.NoDevice;

    switch (kind) {
        .romfs => if (storage.device.romfs.file == Filesystem.File.none) {
            storage.device.romfs = Filesystem.RomFs.initSelf(storage.fs, gpa) catch |err| switch (err) {
                error.NoRomFs => return error.NoDevice,
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
