pub const empty: Storage = .{
    .lock = .init,
    .net = .empty,
    .filesystem = .empty,
    .cwd = .invalid,
    .fds = .empty,
    .descriptions = .empty,
    .paths = .empty,
};

pub const separator = '/';

// This is a workaround to not stall any soc:U IPC call. We'll
// busy loop/wait instead so other threads can progress.
//
// Time we'll sleep when waiting some operation,
// has been arbitrarily chosen.
// NOTE: We choose this instead of multiple sessions because cancellation needs it.
// You can't cancel an IPC call! (AFAIK)
const socket_busy_loop_workaround_ns = 100000;

pub const Ownage = enum(u1) { unowned, owned };

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
        file: FilesystemSrv.File,
        /// `invalid` is a sentinel for root.
        path: Builder.Table.Index,
        socket: SocketUser.Descriptor,
    };

    pub const Flags = packed struct(u16) {
        pub const Kind = enum(u2) {
            file,
            directory,
            socket,
        };

        mount: u8,
        kind: Kind,
        _: u6 = 0,
    };

    pub const Extra = extern union {
        pub const Directory = extern union {
            pub const min_reader_buffer_len = @sizeOf(NameBuffer) + @sizeOf(FilesystemSrv.Directory.Entry);
            pub const NameBuffer = [Io.Dir.max_name_bytes * 4]u8;

            romfs: romfs.View.Iterator,
            archive: FilesystemSrv.Directory,
        };

        // XXX: I would like to use atomics but its an upstream issue...
        seek: zitrus.hardware.cpu.arm11.Monitor(u64),
        dir: Directory,
        none: void,
    };

    ref: std.atomic.Value(u16),
    flags: Flags,
    stored: Stored,
    extra: Extra,

    pub fn initSocket(sock: SocketUser.Descriptor) Description {
        return .{
            .ref = .init(1),
            .flags = .{ .mount = 0, .kind = .socket },
            .stored = .{ .socket = sock },
            .extra = .{ .none = {} },
        };
    }
};

/// A builder for a path.
pub const Builder = struct {
    pub const Table = Storage.Table([]const u16);
    pub const root: []const u16 = &.{ '/', 0 };
    pub const init: Builder = .{ .buf = undefined, .end = 0 };

    buf: [Io.Dir.max_path_bytes + 1]u16,
    end: usize,

    /// It is asserted that `path` is valid
    pub fn appendRaw(builder: *Builder, sub_path: []const u16) error{NameTooLong}!void {
        if (builder.end + sub_path.len > builder.buf.len) return error.NameTooLong;
        @memcpy(builder.buf[builder.end..][0..sub_path.len], sub_path);
        builder.end += sub_path.len;
    }

    pub fn append(builder: *Builder, sub_path: []const u8) error{ NameTooLong, BadPathName }!void {
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
                const last = if (std.mem.lastIndexOfScalar(u16, builder.buf[0 .. builder.end - 1], '/')) |idx|
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
        return builder.buf[0 .. builder.end + 1];
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

pub const Filesystem = struct {
    pub const empty: Filesystem = .{
        .owned = .unowned,
        .fs = .{ .session = .none },
        .mounts = .empty,
    };

    pub const Init = struct {
        fs: FilesystemSrv,
        extra: Ownage,
    };

    pub const MountError = error{SystemResources};
    pub const Mount = struct {
        pub const empty: Mount = .{
            .name = &.{},
            .data = undefined,
        };

        pub const Kind = enum { romfs, archive };
        pub const Data = union(Kind) {
            romfs: FilesystemSrv.RomFs,
            archive: FilesystemSrv.Archive,
        };

        name: []const u8,
        data: Data,

        pub fn deinit(mnt: *Mount, gpa: std.mem.Allocator, fs: FilesystemSrv) void {
            defer mnt.* = .empty;

            switch (mnt.data) {
                .romfs => |rfs| rfs.deinit(gpa),
                .archive => mnt.data.archive.close(fs),
            }
        }
    };

    owned: Ownage,
    fs: FilesystemSrv,
    /// Not Thread-Safe
    mounts: std.ArrayList(Mount),

    pub fn init(filesystem: *Filesystem, opts: Init) !void {
        filesystem.* = .{
            .owned = opts.extra,
            .fs = opts.fs,
            .mounts = .empty,
        };
    }

    pub fn find(filesystem: *Filesystem, name: []const u8) ?u8 {
        return blk: for (filesystem.mounts.items, 0..) |mnt, i| {
            if (std.mem.eql(u8, mnt.name, name)) break :blk @intCast(i);
        } else null;
    }

    /// Not Thread-Safe
    pub fn mountArchive(filesystem: *Filesystem, gpa: std.mem.Allocator, name: []const u8, id: FilesystemSrv.ArchiveId, path_type: FilesystemSrv.PathType, path: []const u8) !void {
        return try filesystem.mount(gpa, name, .{
            .archive = try filesystem.fs.sendOpenArchive(id, path_type, path),
        });
    }

    /// Not Thread-Safe
    pub fn mountSelfRomFs(filesystem: *Filesystem, gpa: std.mem.Allocator, name: []const u8) !void {
        return try filesystem.mount(gpa, name, .{
            .romfs = try .initSelf(filesystem.fs, gpa),
        });
    }

    /// Not Thread-Safe
    pub fn mount(filesystem: *Filesystem, gpa: std.mem.Allocator, name: []const u8, data: Mount.Data) MountError!void {
        std.debug.assert(name.len > 0);

        const mnt = mnt: for (filesystem.mounts.items) |*mnt| {
            if (mnt.name.len == 0) break :mnt mnt;
        } else if (filesystem.mounts.items.len <= std.math.maxInt(u8))
            filesystem.mounts.addOne(gpa) catch return error.SystemResources
        else
            return error.SystemResources;

        mnt.* = .{
            .name = name,
            .data = data,
        };
    }

    /// Not Thread-Safe, asserts all file handled associated with this mount have been closed.
    ///
    /// Remember to unlinkCurrentDir if you set any!
    pub fn umount(filesystem: *Filesystem, gpa: std.mem.Allocator, name: []const u8) void {
        std.debug.assert(name.len > 0);

        const mnt: *Mount = mnt: for (filesystem.mounts.items) |mnt| {
            if (std.mem.eql(u8, mnt.name, name)) break :mnt mnt;
        } else unreachable;

        mnt.deinit(gpa, filesystem.fs);
    }

    pub fn deinit(filesystem: *Filesystem, gpa: std.mem.Allocator) void {
        defer filesystem.* = .empty;

        for (filesystem.mounts.items) |*mnt| {
            if (mnt.name.len > 0) mnt.deinit(gpa, filesystem.fs);
        }

        filesystem.mounts.deinit(gpa);
        if (filesystem.owned == .owned) filesystem.fs.close();
    }
};

pub const Network = struct {
    pub const empty: Network = .{
        .soc = .{ .session = .none },
        .buffer = &.{},
        .memory = .none,
    };

    pub const Init = struct {
        pub const Extra = union(Ownage) {
            unowned: void,
            owned: u32,
        };

        soc: SocketUser,
        extra: Extra,
    };

    soc: SocketUser,
    buffer: []align(horizon.heap.page_size) u8,
    memory: horizon.MemoryBlock,

    pub fn init(net: *Network, gpa: std.mem.Allocator, opts: Init) !void {
        const soc = opts.soc;
        const buffer: []align(horizon.heap.page_size) u8, const memory: horizon.MemoryBlock = switch (opts.extra) {
            .owned => |buffer_size| blk: {
                const buffer = try gpa.alignedAlloc(u8, .fromByteUnits(horizon.heap.page_size), buffer_size);
                errdefer gpa.free(buffer);

                const memory: horizon.MemoryBlock = try .create(buffer.ptr, buffer.len, .none, .rw);
                errdefer memory.close();

                try soc.sendInitialize(memory, buffer.len);
                break :blk .{ buffer, memory };
            },
            .unowned => .{ &.{}, .none },
        };

        net.* = .{
            .soc = soc,
            .buffer = buffer,
            .memory = memory,
        };
    }

    pub fn deinit(net: *Network, gpa: std.mem.Allocator) void {
        defer net.* = .empty;

        if (net.memory == horizon.MemoryBlock.none) return;

        net.soc.sendDeinitialize();
        net.memory.close();
        gpa.free(net.buffer);
        net.soc.close();
    }
};

/// Protects `descriptors`, `table` and `cwd`.
///
/// Hold a write lock if you have any pointer.
lock: Io.RwLock,

net: Network,
filesystem: Filesystem,

/// May be `invalid`, in that case non-device paths *will* return `error.NoDevice`
cwd: Description.Table.Index,
fds: std.ArrayList(Description.Table.Index),
descriptions: Description.Table,
paths: Builder.Table,

pub fn deinit(storage: *Storage, io: std.Io, gpa: std.mem.Allocator) void {
    storage.unlinkCurrentDir(io, gpa);
    storage.filesystem.deinit(gpa);
    storage.net.deinit(gpa);
    storage.paths.deinit(gpa);
    storage.descriptions.deinit(gpa);
    storage.fds.deinit(gpa);
    storage.* = .empty;
}

pub fn unlinkCurrentDir(storage: *Storage, io: std.Io, gpa: std.mem.Allocator) void {
    defer storage.cwd = .invalid;

    switch (storage.cwd) {
        .invalid => {},
        _ => |idx| storage.closeDescription(io, gpa, idx),
    }
}

pub fn operate(storage: *Storage, io: std.Io, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    return switch (operation) {
        .file_read_streaming => |op| blk: {
            for (op.data) |buf| {
                if (buf.len == 0) continue;

                break :blk .{ .file_read_streaming = storage.readStreaming(io, op.file.handle, buf) };
            }

            break :blk .{ .file_read_streaming = 0 };
        },
        .file_write_streaming => |op| blk: {
            const buf = if (op.header.len != 0)
                op.header
            else buf: for (op.data[0 .. op.data.len - 1]) |buf| {
                if (buf.len == 0) continue;
                break :buf buf;
            } else if (op.data[op.data.len - 1].len > 0 and op.splat > 0)
                op.data[op.data.len - 1]
            else
                break :blk .{ .file_write_streaming = 0 };

            break :blk .{ .file_write_streaming = storage.writeStreaming(io, op.file.handle, buf) };
        },
        .net_receive => |op| .{
            .net_receive = nr: {
                const stored, const flags = storage.getDescriptionStoredFlags(io, op.socket_handle);
                std.debug.assert(flags.kind == .socket);

                break :nr storage.netReceive(stored.socket, op.message_buffer, op.data_buffer, op.flags);
            },
        },
        .device_io_control => unreachable,
    };
}

pub fn batchAwaitAsync(storage: *Storage, io: std.Io, b: *Io.Batch) Io.Cancelable!void {
    return storage.batchAwait(io, .failing, b, false, .none) catch unreachable; // concurrency == false
}

pub fn batchAwaitConcurrent(storage: *Storage, io: std.Io, gpa: std.mem.Allocator, b: *Io.Batch, timeout: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
    return try storage.batchAwait(io, gpa, b, true, timeout);
}

pub fn batchCancel(storage: *Storage, gpa: std.mem.Allocator, b: *Io.Batch) void {
    _ = storage;

    if (b.userdata) |ud| {
        const polls_ptr: [*]SocketUser.Descriptor.Poll = @ptrCast(@alignCast(ud));
        const polls = polls_ptr[b.storage.len];

        gpa.free(polls);
    }
}

const poll_buffer_len = 16;
fn batchAwait(storage: *Storage, io: std.Io, gpa: std.mem.Allocator, b: *Io.Batch, concurrency: bool, timeout: Io.Timeout) !void {
    var poll_buffer: [poll_buffer_len]SocketUser.Descriptor.Poll = undefined;
    var polls: struct {
        buf: []SocketUser.Descriptor.Poll,
        len: usize,

        pub fn add(polls: *@This(), p_gpa: std.mem.Allocator, p_b: *Io.Batch, sock: SocketUser.Descriptor, events: SocketUser.Descriptor.Poll.Events) Allocator.Error!void {
            if (polls.len == polls.buf.len) {
                const new: []SocketUser.Descriptor.Poll = if (p_b.userdata) |ud|
                    @as([*]SocketUser.Descriptor.Poll, @ptrCast(@alignCast(ud)))[0..p_b.storage.len]
                else
                    try p_gpa.alloc(SocketUser.Descriptor.Poll, p_b.storage.len);

                @memcpy(new[0..polls.len], polls.buf);
                polls.buf = new;
            }

            polls.buf[polls.len] = .{
                .fd = sock,
                .events = events,
                .poll = .{},
            };
            polls.len += 1;
        }
    } = .{ .buf = &poll_buffer, .len = 0 };

    var completions: usize = 0;

    grab_poll: {
        var prev_index: Io.Operation.OptionalIndex = .none;
        var index = b.submitted.head;

        while (index != .none) {
            const b_storage = &b.storage[index.toIndex()];
            const submission = &b_storage.submission;
            const next_index = submission.node.next;
            defer index = next_index;

            nb: {
                const result: Io.Operation.Result = switch (submission.operation) {
                    .device_io_control => unreachable,
                    .file_read_streaming, .file_write_streaming => try storage.operate(io, submission.operation),
                    .net_receive => |recv| .{
                        .net_receive = nr: {
                            const stored, const flags = storage.getDescriptionStoredFlags(io, recv.socket_handle);
                            std.debug.assert(flags.kind == .socket);

                            const sock = stored.socket;
                            var data_i: usize = 0;

                            for (recv.message_buffer, 0..) |*msg, i| {
                                const remaining_data_buffer = recv.data_buffer[data_i..];
                                storage.netReceiveOne(sock, msg, remaining_data_buffer, recv.flags) catch |err| switch (err) {
                                    error.WouldBlock => {
                                        if (i > 0) break :nr .{ null, i };

                                        polls.add(gpa, b, sock, .{
                                            .in = true,
                                        }) catch |e| switch (e) {
                                            error.OutOfMemory => {
                                                if (concurrency) return error.ConcurrencyUnavailable;
                                                break :grab_poll;
                                            },
                                        };
                                        break :nb;
                                    },
                                    else => |e| break :nr .{ e, i },
                                };

                                data_i += msg.data.len;
                            }

                            break :nr .{ null, recv.message_buffer.len };
                        },
                    },
                };
                defer completions += 1;

                switch (prev_index) {
                    .none => b.submitted.head = next_index,
                    else => b.storage[prev_index.toIndex()].submission.node.next = next_index,
                }

                if (next_index == .none) b.submitted.tail = prev_index;

                switch (b.completed.tail) {
                    .none => b.completed.head = index,
                    else => |tail| b.storage[tail.toIndex()].completion.node.next = index,
                }

                b_storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
                b.completed.tail = index;
            }
        }
    }

    if (completions > 0) return;

    const soc = storage.net.soc;
    const maybe_until = timeout.toTimestamp(io);

    while (true) {
        var maybe_polled: SocketUser.E.Maybe = soc.sendPoll(polls.buf[0..polls.len], 0) catch |err| switch (err) {
            else => if (concurrency) return error.ConcurrencyUnavailable else blk: {
                // HACK: when not concurrent just say that the first fd completed, we'll block on that later with `operate`.
                polls.buf[0].events = @bitCast(@as(u32, std.math.maxInt(u32)));
                break :blk @enumFromInt(1);
            },
        };

        poll_result: switch (maybe_polled.errno()) {
            .SUCCESS => {
                const polled = @intFromEnum(maybe_polled);

                if (polled == 0) {
                    if (b.completed.head != .none) return;

                    if (maybe_until) |until| {
                        const duration = until.durationFromNow(io);

                        if (duration.raw.nanoseconds < socket_busy_loop_workaround_ns) return error.Timeout;
                    }

                    horizon.sleepThread(socket_busy_loop_workaround_ns);
                    continue;
                }

                var prev_index: Io.Operation.OptionalIndex = .none;
                var index = b.submitted.head;
                for (polls.buf[0..polls.len]) |poll| {
                    const b_storage = &b.storage[index.toIndex()];
                    const submission = &b_storage.submission;
                    const next_index = submission.node.next;
                    defer index = next_index;

                    if (poll.events.isEmpty()) continue;

                    const result = try storage.operate(io, submission.operation);

                    switch (prev_index) {
                        .none => b.submitted.head = next_index,
                        else => b.storage[prev_index.toIndex()].submission.node.next = next_index,
                    }

                    if (next_index == .none) b.submitted.tail = prev_index;

                    switch (b.completed.tail) {
                        .none => b.completed.head = index,
                        else => |tail| b.storage[tail.toIndex()].completion.node.next = index,
                    }

                    b_storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
                    b.completed.tail = index;
                }

                return;
            },
            else => if (concurrency) return error.ConcurrencyUnavailable else {
                polls.buf[0].events = @bitCast(@as(u32, std.math.maxInt(u32)));
                maybe_polled = @enumFromInt(1); // see above
                continue :poll_result .SUCCESS;
            },
        }
    }
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
pub fn openPath(storage: *Storage, io: std.Io, gpa: std.mem.Allocator, parent_dir: Descriptor, sub_path: []const u8, opts: OpenFlags) OpenPathError!Descriptor {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;
    if (opts.create != .none) std.debug.assert(opts.allow == .file);

    const fd = try storage.allocateDescription(io, gpa);
    errdefer storage.closeUninitialized(io, fd);

    const maybe_mnt_idx, const mnt_path = try storage.splitParsePath(sub_path);
    const maybe_dir_stored, const maybe_dir_mnt_idx = (try storage.getDirectoryDescription(io, parent_dir)) orelse .{ null, null };

    const description: Description = des: {
        const mnt_idx = maybe_mnt_idx orelse maybe_dir_mnt_idx orelse return error.NoDevice;
        const mnt = &storage.filesystem.mounts.items[mnt_idx];

        switch (mnt.data) {
            .romfs => |rfs| {
                if (opts.create != .none) return error.ReadOnlyFileSystem;

                const parent: romfs.View.Directory = if (Io.Dir.path.isAbsolutePosix(mnt_path))
                    .root
                else
                    maybe_dir_stored.?.romfs.asDirectory(); // We already return NoDevice above

                var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
                const utf16_device_path = utf16_device_path_buffer[0 .. std.unicode.utf8ToUtf16Le(&utf16_device_path_buffer, mnt_path) catch return error.BadPathName];
                const entry = try rfs.openAny(parent, utf16_device_path);

                if ((opts.allow == .file or opts.mode != .read_only) and entry.kind == .directory) return error.IsDir;
                if ((opts.allow == .directory) and entry.kind == .file) return error.NotDir;
                if (opts.mode != .read_only) return error.ReadOnlyFileSystem; // XXX: pluh... and ReadOnlyFileSystem?

                break :des .{
                    .ref = .init(1),
                    .stored = .{ .romfs = entry },
                    .flags = .{
                        .mount = mnt_idx,
                        .kind = switch (entry.kind) {
                            .file => .file,
                            .directory => .directory,
                        },
                    },
                    .extra = switch (entry.kind) {
                        .file => .{ .seek = .init(0) },
                        .directory => .{ .dir = .{ .romfs = entry.asDirectory().iterator(rfs.view) } },
                    },
                };
            },
            .archive => |archive| {
                const fs = storage.filesystem.fs;

                var builder: Builder = .init;
                const path_z = try storage.buildPath(&builder, io, mnt_path, maybe_dir_stored);

                if (std.mem.eql(u16, path_z, Builder.root)) break :des .{
                    .ref = .init(1),
                    .stored = .{ .path = .invalid },
                    .flags = .{
                        .mount = mnt_idx,
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
                            .mount = mnt_idx,
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
                        .mount = mnt_idx,
                        .kind = .directory,
                    },
                    .extra = .{ .dir = .{ .archive = .none } },
                };
            },
        }
    };

    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        storage.getDescription(fd).* = description;
    }

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

pub const AccessPathError = error{
    ReadOnlyFileSystem,
    FileNotFound,
    NameTooLong,
    BadPathName,
    AccessDenied,
    NoDevice,
    Unexpected,
};

/// Assumes `lock` is held as non-shareable.
pub fn accessPath(storage: *Storage, io: std.Io, parent_dir: Descriptor, sub_path: []const u8, read: bool, write: bool) AccessPathError!void {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;

    const maybe_mnt_idx, const device_path = try storage.splitParsePath(sub_path);
    const maybe_dir_stored, const maybe_dir_device = (try storage.getDirectoryDescription(io, parent_dir)) orelse .{ null, null };
    const mnt = maybe_mnt_idx orelse maybe_dir_device orelse return error.NoDevice;

    switch (storage.filesystem.mounts.items[mnt].data) {
        .romfs => |rfs| {
            const parent: romfs.View.Directory = if (Io.Dir.path.isAbsolutePosix(device_path))
                .root
            else
                maybe_dir_stored.?.romfs.asDirectory(); // We already return NoDevice above

            var utf16_device_path_buffer: [Io.Dir.max_path_bytes]u16 = undefined;
            const utf16_device_path = utf16_device_path_buffer[0 .. std.unicode.utf8ToUtf16Le(&utf16_device_path_buffer, device_path) catch return error.BadPathName];
            _ = try rfs.openAny(parent, utf16_device_path);

            if (write) return error.ReadOnlyFileSystem;
        },
        .archive => |archive| {
            const fs = storage.filesystem.fs;

            var builder: Builder = .init;
            const path_z = try storage.buildPath(&builder, io, device_path, maybe_dir_stored);

            if (std.mem.eql(u16, path_z, Builder.root)) return if (write) error.AccessDenied;

            var current_read = read;

            while (true) {
                if (fs.sendOpenFile(0, archive, .utf16, @ptrCast(path_z), .{
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

pub const ModifyError = error{
    ReadOnlyFileSystem,
    FileNotFound,
    PathAlreadyExists,
    NameTooLong,
    BadPathName,
    IsDir,
    NotDir,
    NoDevice,
    Unexpected,
};

/// Assumes `lock` is held as non-shareable.
pub fn modifyPath(storage: *Storage, io: std.Io, parent_dir: Descriptor, sub_path: []const u8, operation: ModifyPathOperation) ModifyError!void {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;

    const maybe_mnt_idx, const device_path = try storage.splitParsePath(sub_path);
    const maybe_dir_stored, const maybe_dir_device = (try storage.getDirectoryDescription(io, parent_dir)) orelse .{ null, null };
    const mnt = maybe_mnt_idx orelse maybe_dir_device orelse return error.NoDevice;

    switch (storage.filesystem.mounts.items[mnt].data) {
        .romfs => return error.ReadOnlyFileSystem,
        .archive => |archive| {
            const fs = storage.filesystem.fs;

            var builder: Builder = .init;
            const path_z = try storage.buildPath(&builder, io, device_path, maybe_dir_stored);

            switch (operation) {
                .create_dir => fs.sendCreateDirectory(0, archive, .utf16, @ptrCast(path_z), .{}) catch |err| switch (err) {
                    error.FileNotFound, error.PathAlreadyExists => |e| return e,
                    else => return error.Unexpected,
                },
                .delete_dir => fs.sendDeleteDirectory(0, archive, .utf16, @ptrCast(path_z)) catch |err| switch (err) {
                    error.FileNotFound, error.NotDir => |e| return e,
                    else => return error.Unexpected,
                },
                .delete_file => fs.sendDeleteFile(0, archive, .utf16, @ptrCast(path_z)) catch |err| switch (err) {
                    error.FileNotFound, error.IsDir => |e| return e,
                    else => return error.Unexpected,
                },
            }
        },
    }
}

/// Assumes `lock` is held as non-shareable.
pub fn renamePath(storage: *Storage, io: std.Io, src_parent_dir: Descriptor, src_path: []const u8, dst_parent_dir: Descriptor, dst_path: []const u8, preserve: bool) Io.Dir.RenamePreserveError!void {
    if (src_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (src_path.len == 0) return error.BadPathName;
    if (dst_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (dst_path.len == 0) return error.BadPathName;

    const maybe_src_stored, const maybe_src_dir_device = (try storage.getDirectoryDescription(io, src_parent_dir)) orelse .{ null, null };
    const maybe_dst_stored, const maybe_dst_dir_device = (try storage.getDirectoryDescription(io, dst_parent_dir)) orelse .{ null, null };

    const maybe_src_mnt, const src_device_path = try storage.splitParsePath(src_path);
    const src_mnt = maybe_src_mnt orelse maybe_src_dir_device orelse return error.NoDevice;

    const maybe_dst_mnt, const dst_device_path = try storage.splitParsePath(dst_path);
    const dst_mnt = maybe_dst_mnt orelse maybe_dst_dir_device orelse return error.NoDevice;

    const src_mnt_data = &storage.filesystem.mounts.items[src_mnt].data;
    const dst_mnt_data = &storage.filesystem.mounts.items[dst_mnt].data;

    switch (src_mnt_data.*) {
        .romfs => return error.ReadOnlyFileSystem,
        .archive => |archive| {
            if (dst_mnt_data.* != .archive) return error.CrossDevice;

            const fs = storage.filesystem.fs;
            const src_archive = archive;
            const dst_archive = dst_mnt_data.archive;

            var src_builder: Builder = .init;
            const src_path_z = try storage.buildPath(&src_builder, io, src_device_path, maybe_src_stored);

            var dst_builder: Builder = .init;
            const dst_path_z = try storage.buildPath(&dst_builder, io, dst_device_path, maybe_dst_stored);

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

pub fn createDirPath(storage: *Storage, io: std.Io, parent_dir: Descriptor, sub_path: []const u8) Io.Dir.CreateDirPathError!Io.Dir.CreatePathStatus {
    if (sub_path.len > Io.Dir.max_path_bytes) return error.NameTooLong;
    if (sub_path.len == 0) return error.BadPathName;

    const maybe_mnt_idx, const device_path = try storage.splitParsePath(sub_path);
    const maybe_dir_stored, const maybe_dir_device = (try storage.getDirectoryDescription(io, parent_dir)) orelse .{ null, null };
    const mnt = maybe_mnt_idx orelse maybe_dir_device orelse return error.NoDevice;

    switch (storage.filesystem.mounts.items[mnt].data) {
        .romfs => return error.ReadOnlyFileSystem,
        .archive => |archive| {
            const fs = storage.filesystem.fs;

            const parent: []const u16 = if (Io.Dir.path.isAbsolutePosix(device_path))
                Builder.root
            else switch (maybe_dir_stored.?.path) { // We already return NoDevice above
                .invalid => Builder.root,
                _ => |open| storage.paths.list.items[@intFromEnum(open)].value,
            };

            // + 1 for the NUL-terminator
            if (parent.len + device_path.len + 1 > Io.Dir.max_path_bytes) return error.NameTooLong;

            var builder: Builder = .init;
            try builder.appendRaw(parent[0 .. parent.len - 1]); // Remove the NULL terminator as we don't need it here.
            const parent_end = builder.end;
            try builder.append(device_path);

            const path_z = try builder.nullTerminate();
            const path: []const u16 = builder.path();

            var it: Io.Dir.path.ComponentIterator(.posix, u16) = .init(path[parent_end..]);
            var status: Io.Dir.CreatePathStatus = .existed;
            var component = it.last() orelse return error.BadPathName;

            while (true) {
                // NOTE: This looks weird (and is brittle...) but this way we don't have to allocate an intermediate buffer!
                const current_path_z = path_z[0 .. parent_end + component.path.len + 1];

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

pub fn netListen(storage: *Storage, io: std.Io, gpa: Allocator, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.ListenOptions) Io.net.IpAddress.ListenError!Io.net.Socket {
    if (storage.net.soc.session == horizon.Session.Client.none) return error.NetworkDown;
    if (address.* != .ip4) return error.AddressFamilyUnsupported;

    switch (opts.protocol) {
        .tcp => switch (opts.mode) {
            .stream => {},
            else => return error.SocketModeUnsupported,
        },
        else => return error.ProtocolUnsupportedBySystem,
    }

    const soc = storage.net.soc;
    const addr = address.ip4;

    const fd = try storage.allocateDescription(io, gpa);
    errdefer storage.closeUninitialized(io, fd);

    const sock: SocketUser.Descriptor = sock: {
        const maybe_sock = (soc.sendSocket(.inet, .stream, .any) catch |err| switch (err) {
            else => return error.Unexpected,
        });

        break :sock switch (maybe_sock.errno()) {
            .SUCCESS => @enumFromInt(@intFromEnum(maybe_sock)),
            .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        };
    };
    errdefer sock.close(soc);

    try setSocketNonBlocking(soc, sock, true);

    var soc_address: SocketUser.IpAddress = .{ .ip4 = address4ToSoc(addr) };

    // TODO: proper error handling, we'll see them while we develop
    if (opts.reuse_address) {
        switch ((soc.sendSetSockOpt(sock, .socket, .{ .socket = .reuse_address }, @ptrCast(&@as(u32, 1))) catch |err| switch (err) {
            else => return error.Unexpected,
        }).errno()) {
            .SUCCESS => {},
            else => |e| return unexpectedSocErrno(e),
        }
    }

    // NOTE: workaround as it seems the 3ds doesn't support ephemeral ports
    while (true) {
        if (addr.port == 0) soc_address.ip4.port = std.mem.nativeToBig(u16, randomEphemeralPort(io));

        switch ((soc.sendBind(sock, &soc_address) catch |err| switch (err) {
            else => return error.Unexpected,
        }).errno()) {
            .SUCCESS => break,
            .ADDRINUSE => if (soc_address.ip4.port != 0) return error.AddressInUse,
            else => |e| return unexpectedSocErrno(e),
        }
    }

    switch ((soc.sendListen(sock, opts.kernel_backlog) catch |err| switch (err) {
        else => return error.Unexpected,
    }).errno()) {
        .SUCCESS => {},
        // XXX: Can happen spuriously with valid handles???
        .BADF => {},
        .ADDRINUSE => return error.AddressInUse,
        else => |e| return unexpectedSocErrno(e),
    }

    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        storage.getDescription(fd).* = .initSocket(sock);
    }

    return .{
        .handle = fd,
        .address = .{ .ip4 = .{
            .bytes = addr.bytes,
            .port = std.mem.bigToNative(u16, soc_address.ip4.port),
        } },
    };
}

pub fn netBind(storage: *Storage, io: std.Io, gpa: Allocator, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.BindOptions) Io.net.IpAddress.BindError!Io.net.Socket {
    if (storage.net.soc.session == horizon.Session.Client.none) return error.NetworkDown;
    if (opts.ip6_only or address.* != .ip4) return error.AddressFamilyUnsupported;

    const proto = opts.protocol orelse .udp;

    switch (proto) {
        .udp => switch (opts.mode) {
            .dgram => {},
            else => return error.SocketModeUnsupported,
        },
        else => return error.ProtocolUnsupportedBySystem,
    }

    const soc = storage.net.soc;
    const addr = address.ip4;

    const fd = try storage.allocateDescription(io, gpa);
    errdefer storage.closeUninitialized(io, fd);

    var port: u16 = 0;
    io.random(@ptrCast(&port));

    const sock: SocketUser.Descriptor = sock: {
        const maybe_sock = (soc.sendSocket(.inet, .dgram, .any) catch |err| switch (err) {
            else => return error.Unexpected,
        });

        break :sock switch (maybe_sock.errno()) {
            .SUCCESS => @enumFromInt(@intFromEnum(maybe_sock)),
            .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        };
    };
    errdefer sock.close(soc);

    try setSocketNonBlocking(soc, sock, true);

    var soc_address: SocketUser.IpAddress = .{ .ip4 = address4ToSoc(addr) };

    // NOTE: workaround as it seems the 3ds doesn't support ephemeral ports
    while (true) {
        if (addr.port == 0) soc_address.ip4.port = std.mem.nativeToBig(u16, randomEphemeralPort(io));

        switch ((soc.sendBind(sock, &soc_address) catch |err| switch (err) {
            else => return error.Unexpected,
        }).errno()) {
            .SUCCESS => break,
            .ADDRINUSE => if (soc_address.ip4.port != 0) return error.AddressInUse,
            else => |e| return unexpectedSocErrno(e),
        }
    }

    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        storage.getDescription(fd).* = .initSocket(sock);
    }

    return .{
        .handle = fd,
        .address = .{ .ip4 = .{
            .bytes = addr.bytes,
            .port = std.mem.bigToNative(u16, soc_address.ip4.port),
        } },
    };
}

pub fn netAccept(storage: *Storage, io: std.Io, gpa: Allocator, handle: Descriptor, opts: Io.net.Server.AcceptOptions) Io.net.Server.AcceptError!Io.net.Socket {
    _ = opts;
    const desc = storage.getDescription(handle);
    std.debug.assert(desc.flags.kind == .socket);

    const soc = storage.net.soc;
    const sock = desc.stored.socket;

    const fd = try storage.allocateDescription(io, gpa);
    errdefer storage.closeUninitialized(io, fd);

    var soc_address: SocketUser.IpAddress = undefined;

    const accepted_sock: SocketUser.Descriptor = blk: while (true) {
        const maybe_accepted_sock = soc.sendAccept(sock, &soc_address) catch |err| switch (err) {
            else => return error.Unexpected,
        };

        switch (maybe_accepted_sock.errno()) {
            .SUCCESS => break :blk @enumFromInt(@intFromEnum(maybe_accepted_sock)),
            .AGAIN => horizon.sleepThread(socket_busy_loop_workaround_ns),
            .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        }
    };
    errdefer accepted_sock.close(soc);

    // NOTE: We get the description again as we weren't holding the read lock.
    // We don't want to hold the lock while we're waiting for a connection!
    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        storage.getDescription(fd).* = .initSocket(accepted_sock);
    }

    return .{
        .handle = fd,
        .address = addressFromSoc(soc_address),
    };
}

pub fn netConnect(storage: *Storage, io: std.Io, gpa: Allocator, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.ConnectOptions) Io.net.IpAddress.ConnectError!Io.net.Socket {
    if (storage.net.soc.session == horizon.Session.Client.none) return error.NetworkDown;
    if (address.* != .ip4) return error.AddressFamilyUnsupported;
    if (opts.timeout != .none) @panic("TODO: Timeout");

    const proto: Io.net.Protocol = opts.protocol orelse .tcp;

    switch (proto) {
        .tcp => switch (opts.mode) {
            .stream => {},
            else => return error.SocketModeUnsupported,
        },
        else => return error.ProtocolUnsupportedBySystem,
    }

    const soc = storage.net.soc;
    const addr = address.ip4;

    const fd = try storage.allocateDescription(io, gpa);
    errdefer storage.closeUninitialized(io, fd);

    const sock: SocketUser.Descriptor = sock: {
        const maybe_sock = (soc.sendSocket(.inet, .stream, .any) catch |err| switch (err) {
            else => return error.Unexpected,
        });

        break :sock switch (maybe_sock.errno()) {
            .SUCCESS => @enumFromInt(@intFromEnum(maybe_sock)),
            .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        };
    };
    errdefer sock.close(soc);

    try setSocketNonBlocking(soc, sock, true);

    var soc_address: SocketUser.IpAddress = .{
        .ip4 = .{
            .bytes = addr.bytes,
            .port = std.mem.nativeToBig(u16, addr.port),
        },
    };

    const deadline = opts.timeout.toTimestamp(io);

    var poll_fd: SocketUser.Descriptor.Poll = .{
        .fd = sock,
        .poll = .{
            .out = true,
        },
        .events = .{},
    };

    switch ((soc.sendConnect(sock, &soc_address) catch |err| switch (err) {
        else => return error.Unexpected,
    }).errno()) {
        .SUCCESS => {},
        .NETUNREACH => return error.NetworkUnreachable,
        .AFNOSUPPORT => return error.AddressFamilyUnsupported,
        .CONNRESET => return error.ConnectionResetByPeer,
        .INPROGRESS, .ALREADY => while (true) {
            if (deadline) |d| {
                const duration = d.durationFromNow(io);

                if (duration.raw.nanoseconds <= 0) return error.Timeout;
            }

            horizon.sleepThread(socket_busy_loop_workaround_ns);

            const maybe_poll = soc.sendPoll((&poll_fd)[0..1], 0) catch |err| switch (err) {
                else => return error.Unexpected,
            };

            switch (maybe_poll.errno()) {
                .SUCCESS => {
                    const polled: u32 = @intCast(@intFromEnum(maybe_poll));

                    if (polled == 0) continue;
                    if (poll_fd.events.out) break; // gtg

                    // TODO: inspect SO_ERROR
                    return error.Unexpected;
                },
                .NOMEM => return error.SystemResources,
                else => |e| return unexpectedSocErrno(e),
            }
        },
        .NOMEM => return error.SystemResources,
        else => |e| return unexpectedSocErrno(e),
    }

    switch ((soc.sendGetSockName(sock, &soc_address) catch |err| switch (err) {
        else => return error.Unexpected,
    }).errno()) {
        .SUCCESS => {},
        .NOMEM => return error.SystemResources,
        else => |e| return unexpectedSocErrno(e),
    }

    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        storage.getDescription(fd).* = .initSocket(sock);
    }

    return .{
        .handle = fd,
        .address = addressFromSoc(soc_address),
    };
}

fn setSocketNonBlocking(soc: SocketUser, sock: SocketUser.Descriptor, non_blocking: bool) !void {
    const maybe_flags = soc.sendFcntl(sock, .get_flags, .{ .none = {} }) catch |err| switch (err) {
        else => return error.Unexpected,
    };

    const flags: SocketUser.Descriptor.Flags = switch (maybe_flags.errno()) {
        .SUCCESS => @bitCast(@intFromEnum(maybe_flags)),
        else => |e| return unexpectedSocErrno(e),
    };

    switch ((soc.sendFcntl(sock, .set_flags, .{ .flags = .{
        ._unknown0 = flags._unknown0,
        .non_block = non_blocking,
        ._unknown1 = flags._unknown1,
    } }) catch |err| switch (err) {
        else => return error.Unexpected,
    }).errno()) {
        .SUCCESS => {},
        .NOMEM => return error.SystemResources,
        else => |e| return unexpectedSocErrno(e),
    }
}

pub fn netShutdown(storage: *Storage, io: std.Io, handle: Descriptor, how: Io.net.ShutdownHow) Io.net.ShutdownError!void {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);
    const soc = storage.net.soc;

    return switch (flags.kind) {
        .directory, .file => error.Unexpected,
        .socket => switch ((soc.sendShutdown(stored.socket, switch (how) {
            .recv => .recv,
            .send => .send,
            .both => .both,
        }) catch |err| switch (err) {
            else => return error.Unexpected,
        }).errno()) {
            .SUCCESS => {},
            .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        },
    };
}

pub fn netLookup(storage: *Storage, io: std.Io, gpa: Allocator, host_name: Io.net.HostName, resolved: *Io.Queue(Io.net.HostName.LookupResult), opts: Io.net.HostName.LookupOptions) Io.net.HostName.LookupError!void {
    defer resolved.close(io); // "Closes `resolved`, even on error."

    if (storage.net.soc.session == horizon.Session.Client.none) return error.NetworkDown;

    // NOTE: it seems soc:u doesn't handle localhost
    if (std.mem.eql(u8, "localhost", host_name.bytes)) {
        resolved.putOne(io, .{ .address = .{ .ip4 = .loopback(opts.port) } }) catch |err| switch (err) {
            error.Closed => unreachable,
            error.Canceled => |e| return e,
        };

        return;
    }

    const soc = storage.net.soc;

    var name_buffer: [Io.net.HostName.max_len + 1]u8 = undefined;
    var port_buffer: [8]u8 = undefined;

    const port_c = std.fmt.bufPrint(&port_buffer, "{d}\x00", .{opts.port}) catch unreachable;
    const name_c = std.fmt.bufPrint(&name_buffer, "{s}\x00", .{host_name.bytes}) catch unreachable;

    const hints: SocketUser.AddressInfo = .{
        .flags = .{
            .numeric_service = true,
        },
        .family = .unspec,
        .type = .any,
        .protocol = .any,
        .address_len = undefined,
        .canonical_name = undefined,
        .address = undefined,
    };

    // XXX: we cannot use empty to get all results first, azahar expects at least one or we have a segmentation fault!
    // If that is fixed we can let this be empty and get all the entries in 2 calls.
    var results = std.ArrayList(SocketUser.AddressInfo).initCapacity(gpa, 2) catch return error.SystemResources;
    defer results.deinit(gpa);

    _ = results.addManyAsSliceAssumeCapacity(2);

    while (true) {
        const maybe, const resolved_results_len = soc.sendGetAddrInfo(name_c, port_c, &hints, results.items) catch |err| switch (err) {
            else => return error.Unexpected,
        };

        switch (maybe.errno()) {
            .SUCCESS => {},
            .AGAIN => continue,
            .AI_FAMILY => return error.AddressFamilyUnsupported,
            .AI_NONAME => return error.UnknownHostName,
            else => |e| return unexpectedSocErrno(e),
        }

        if (results.items.len == resolved_results_len) break;

        results.resize(gpa, resolved_results_len) catch return error.SystemResources;
    }

    var canonical_name = false;
    for (results.items) |entry| {
        const address: Io.net.IpAddress = addressFromSoc(entry.address);

        resolved.putOne(io, .{ .address = address }) catch |err| switch (err) {
            error.Closed => unreachable,
            error.Canceled => |e| return e,
        };

        if (opts.canonical_name_buffer) |canonical_name_buf| if (!canonical_name) {
            const name = entry.canonical_name[0 .. std.mem.findScalar(u8, &entry.canonical_name, 0) orelse entry.canonical_name.len];
            if (name.len == 0) continue;

            @memcpy(canonical_name_buf[0..name.len], name);
            resolved.putOne(io, .{ .canonical_name = .{ .bytes = canonical_name_buf[0..name.len] } }) catch |err| switch (err) {
                error.Closed => unreachable,
                error.Canceled => |e| return e,
            };
            canonical_name = true;
        };
    }
}

/// Assumes `lock` is held as shareable.
pub fn readDir(storage: *Storage, io: std.Io, r: *Io.Dir.Reader, entries: []Io.Dir.Entry) Io.Dir.Reader.Error!usize {
    std.debug.assert(r.buffer.len > @sizeOf(Description.Extra.Directory.NameBuffer));

    const handle = r.dir.handle;
    const flags = blk: {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        break :blk storage.getDescription(handle).flags;
    };

    return switch (flags.kind) {
        .socket, .file => error.Unexpected,
        .directory => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => |rfs| {
                storage.lock.lockSharedUncancelable(io);
                defer storage.lock.unlockShared(io);

                const desc = storage.getDescription(handle);

                switch (r.state) {
                    .finished => return 0,
                    .reset => {
                        desc.extra.dir.romfs = desc.stored.romfs.asDirectory().iterator(rfs.view);

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
                    const e = desc.extra.dir.romfs.next(rfs.view) orelse {
                        r.state = .finished;
                        break;
                    };

                    const utf16_name = e.name(rfs.view);
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
            .archive => |archive| {
                const fs = storage.filesystem.fs;
                const path_z, var dir = blk: {
                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    const desc = storage.getDescription(handle);
                    break :blk .{ switch (desc.stored.path) {
                        .invalid => Builder.root,
                        _ => |idx| storage.paths.list.items[@intFromEnum(idx)].value,
                    }, @atomicLoad(FilesystemSrv.Directory, &desc.extra.dir.archive, .monotonic) };
                };

                switch (r.state) {
                    .finished => return 0,
                    .reset => {
                        if (dir != FilesystemSrv.Directory.none) {
                            dir.close();

                            storage.lock.lockSharedUncancelable(io);
                            defer storage.lock.unlockShared(io);

                            @atomicStore(FilesystemSrv.Directory, &storage.getDescription(handle).extra.dir.archive, .none, .monotonic);
                        }

                        r.state = .reading;
                        r.end = @sizeOf(Description.Extra.Directory.NameBuffer);
                        r.index = r.end;
                    },
                    .reading => {},
                }

                if (dir == FilesystemSrv.Directory.none) {
                    dir = fs.sendOpenDirectory(archive, .utf16, @ptrCast(path_z)) catch |err| switch (err) {
                        // This can happen if the directory is deleted while iterating.
                        error.FileNotFound => {
                            r.state = .finished;
                            return 0;
                        },
                        else => return error.Unexpected,
                    };

                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    @atomicStore(FilesystemSrv.Directory, &storage.getDescription(handle).extra.dir.archive, dir, .monotonic);
                }

                const bytes = r.buffer[0..@sizeOf(Description.Extra.Directory.NameBuffer)];

                var consumed: usize = 0;
                var i: usize = 0;
                while (i < entries.len) {
                    if (r.end - r.index < @sizeOf(FilesystemSrv.Directory.Entry)) {
                        const entries_buf: []align(@alignOf(usize)) FilesystemSrv.Directory.Entry = buf: {
                            const remaining = r.buffer[@sizeOf(Description.Extra.Directory.NameBuffer)..];
                            // NOTE: This is always aligned as it has @alignOf(u32) and the name buffer is aligned to 4 bytes.
                            const entry_ptr: [*]align(@alignOf(usize)) FilesystemSrv.Directory.Entry = @ptrCast(@alignCast(remaining.ptr));
                            break :buf entry_ptr[0..(remaining.len / @sizeOf(FilesystemSrv.Directory.Entry))];
                        };

                        const read = dir.sendRead(entries_buf) catch return error.Unexpected;

                        if (read == 0) {
                            r.state = .finished;
                            r.end = 0;
                            r.index = r.end;

                            dir.close();

                            storage.lock.lockSharedUncancelable(io);
                            defer storage.lock.unlockShared(io);

                            @atomicStore(FilesystemSrv.Directory, &storage.getDescription(handle).extra.dir.archive, .none, .monotonic);
                            return 0;
                        }

                        r.end = @sizeOf(Description.Extra.Directory.NameBuffer) + read * @sizeOf(FilesystemSrv.Directory.Entry);
                        r.index = @sizeOf(Description.Extra.Directory.NameBuffer);
                    }

                    const entry: *align(@alignOf(usize)) FilesystemSrv.Directory.Entry = @ptrCast(@alignCast(r.buffer[r.index..][0..@sizeOf(FilesystemSrv.Directory.Entry)]));
                    const utf16_name = entry.utf16_name[0 .. std.mem.findScalar(u16, &entry.utf16_name, 0) orelse entry.utf16_name.len];
                    if (utf16_name.len * 2 > (bytes.len - consumed)) break;

                    const name_len = std.unicode.utf16LeToUtf8(bytes[consumed..], utf16_name) catch return error.Unexpected;

                    entries[i] = .{
                        .name = bytes[consumed..][0..name_len],
                        .inode = {},
                        .kind = if (entry.attributes.directory) .directory else .file,
                    };

                    r.index += @sizeOf(FilesystemSrv.Directory.Entry);
                    consumed += name_len;
                    i += 1;
                }

                return i;
            },
        },
    };
}

pub fn length(storage: *Storage, io: std.Io, handle: Descriptor) Io.File.LengthError!u64 {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    return switch (flags.kind) {
        .socket => return error.Streaming,
        .directory => 0,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => |rfs| stored.romfs.asFile().stat(rfs.view).size,
            .archive => stored.file.sendGetSize() catch return error.Unexpected,
        },
    };
}

pub fn stat(storage: *Storage, io: std.Io, handle: Descriptor) Io.File.StatError!Io.File.Stat {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    return switch (flags.kind) {
        .socket => return error.Unexpected,
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
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => |rfs| .{
                .inode = {},
                .nlink = 0,
                .size = stored.romfs.asFile().stat(rfs.view).size, // No lock because this is initialized if we're here.
                .permissions = .default_file,
                .kind = .file,
                .atime = null,
                .mtime = .fromNanoseconds(0),
                .ctime = .fromNanoseconds(0),
                .block_size = 512,
            },
            .archive => .{
                .inode = {},
                .nlink = 0,
                .size = stored.file.sendGetSize() catch return error.Unexpected,
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

pub fn setLength(storage: *Storage, io: std.Io, handle: Descriptor, new_length: u64) Io.File.SetLengthError!void {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    return switch (flags.kind) {
        .socket, .directory => return error.NonResizable,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => return error.NonResizable,
            .archive => stored.file.sendSetSize(new_length) catch return error.Unexpected,
        },
    };
}

pub fn readPositional(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []u8, offset: u64) Io.File.ReadPositionalError!usize {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    return switch (flags.kind) {
        .socket => return error.Unseekable,
        .directory => error.IsDir,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => |rfs| rfs.readPositional(stored.romfs.asFile(), offset, buffer) catch |e| switch (e) {
                else => error.Unexpected,
            },
            .archive => stored.file.sendRead(offset, buffer) catch |e| switch (e) {
                else => error.Unexpected,
            },
        },
    };
}

pub fn writePositional(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []const u8, offset: u64) Io.File.WritePositionalError!usize {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    return switch (flags.kind) {
        .socket => return error.Unseekable,
        .directory => error.NotOpenForWriting,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => error.NotOpenForWriting,
            .archive => stored.file.sendWrite(offset, buffer, .{}) catch |e| switch (e) {
                else => error.Unexpected,
            },
        },
    };
}

/// Assumes `lock` is held as shareable.
pub fn readStreaming(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []u8) Io.Operation.FileReadStreaming.Result {
    const flags = blk: {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        break :blk storage.getDescription(handle).flags;
    };

    // NOTE: This is NOT fully atomic, its the user's fault if seek races occur.
    // I only guarantee that the 64-bit stores and loads are atomic.

    const initial_offset, const read = switch (flags.kind) {
        .directory => return error.IsDir,
        .socket => return error.Unexpected,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => |rfs| blk: {
                const file, const initial_offset = seek: {
                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    const desc = storage.getDescription(handle);
                    break :seek .{ desc.stored.romfs.asFile(), desc.extra.seek.load() };
                };

                break :blk .{
                    initial_offset,
                    rfs.readPositional(file, initial_offset, buffer) catch |e| switch (e) {
                        else => return error.Unexpected,
                    },
                };
            },
            .archive => blk: {
                const file, const initial_offset = seek: {
                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    const desc = storage.getDescription(handle);
                    break :seek .{ desc.stored.file, desc.extra.seek.load() };
                };

                break :blk .{
                    initial_offset,
                    file.sendRead(initial_offset, buffer) catch |e| switch (e) {
                        else => return error.Unexpected,
                    },
                };
            },
        },
    };

    if (read == 0) return error.EndOfStream;

    {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        const desc = storage.getDescription(handle);

        while (true) {
            _ = desc.extra.seek.load();
            if (!desc.extra.seek.store(initial_offset + read)) break;
        }
    }

    return read;
}

pub fn writeStreaming(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []const u8) Io.Operation.FileWriteStreaming.Result {
    const flags = blk: {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        break :blk storage.getDescription(handle).flags;
    };

    return switch (flags.kind) {
        .directory => error.NotOpenForWriting,
        .socket => error.Unexpected,
        .file => switch (storage.filesystem.mounts.items[flags.mount].data) {
            .romfs => error.NotOpenForWriting,
            .archive => blk: {
                const file, const initial_offset = seek: {
                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    const desc = storage.getDescription(handle);
                    break :seek .{ desc.stored.file, desc.extra.seek.load() };
                };

                const written = file.sendWrite(initial_offset, buffer, .{}) catch |e| switch (e) {
                    else => return error.Unexpected,
                };

                {
                    storage.lock.lockSharedUncancelable(io);
                    defer storage.lock.unlockShared(io);

                    const desc = storage.getDescription(handle);

                    while (true) {
                        _ = desc.extra.seek.load();
                        if (!desc.extra.seek.store(initial_offset + written)) break;
                    }
                }

                break :blk written;
            },
        },
    };
}

pub fn netRead(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []u8) Io.net.Stream.Reader.Error!usize {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    if (flags.kind != .socket) return error.Unexpected;

    const soc = storage.net.soc;
    const sock = stored.socket;

    while (true) {
        const maybe_received = soc.sendReceiveFromMapped(sock, .{}, buffer, null) catch |err| switch (err) {
            else => return error.Unexpected,
        };

        switch (maybe_received.errno()) {
            .SUCCESS => return @intCast(@intFromEnum(maybe_received)),
            .AGAIN => horizon.sleepThread(socket_busy_loop_workaround_ns),
            .NOMEM => return error.SystemResources,
            .CONNRESET => return error.ConnectionResetByPeer,
            else => |e| return unexpectedSocErrno(e),
        }
    }
}

fn netReceive(storage: *Storage, sock: SocketUser.Descriptor, msgs: []Io.net.IncomingMessage, data: []u8, flags: Io.net.ReceiveFlags) Io.Operation.NetReceive.Result {
    var message_i: usize = 0;
    var data_i: usize = 0;

    while (true) {
        if (message_i == msgs.len) return .{ null, message_i };
        if (data_i == data.len) return .{ null, message_i };

        const msg = &msgs[message_i];
        const remaining_data_buffer = data[data_i..];

        recv_one: while (true) {
            storage.netReceiveOne(sock, msg, remaining_data_buffer, flags) catch |err| switch (err) {
                error.WouldBlock => {
                    if (message_i > 0) return .{ null, message_i };

                    horizon.sleepThread(socket_busy_loop_workaround_ns);
                    continue :recv_one;
                },
                else => |e| return .{ e, message_i },
            };

            message_i += 1;
            data_i += msg.data.len;
        }
    }
}

const NetReceiveOneError = Io.UnexpectedError || error{
    SystemResources,
    WouldBlock,
};

fn netReceiveOne(storage: *Storage, sock: SocketUser.Descriptor, msg: *Io.net.IncomingMessage, data: []u8, flags: Io.net.ReceiveFlags) NetReceiveOneError!void {
    const soc = storage.net.soc;
    var src_address: SocketUser.IpAddress = undefined;

    msg_recvd: while (true) {
        // XXX: MSG_TRUNC not supported
        const maybe_recvd = soc.sendReceiveFromMapped(sock, .{
            .out_of_band = flags.oob,
            .peek = flags.peek,
            .dont_wait = true,
        }, data, &src_address) catch |err| switch (err) {
            else => return error.Unexpected,
        };

        switch (maybe_recvd.errno()) {
            .SUCCESS => {
                const recvd: u32 = @intCast(@intFromEnum(maybe_recvd));
                const recvd_written = @min(data.len, recvd);

                msg.* = .{
                    .from = addressFromSoc(src_address),
                    .data = data[0..recvd_written],
                    .control = &.{},
                    .flags = .{
                        .eor = false,
                        .trunc = recvd > recvd_written,
                        .ctrunc = false,
                        .oob = false,
                        .errqueue = false,
                    },
                };
                break :msg_recvd;
            },
            .AGAIN => return error.WouldBlock,
            .NOBUFS, .NOMEM => return error.SystemResources,
            else => |e| return unexpectedSocErrno(e),
        }
    }
}

pub fn netWrite(storage: *Storage, io: std.Io, handle: Descriptor, buffer: []const u8) Io.net.Stream.Writer.Error!usize {
    const stored, const flags = storage.getDescriptionStoredFlags(io, handle);

    if (flags.kind != .socket) return error.Unexpected;

    const soc = storage.net.soc;
    const sock = stored.socket;

    while (true) {
        const maybe_sent = soc.sendSendToMapped(sock, .{}, buffer, null) catch |err| switch (err) {
            else => return error.Unexpected,
        };

        switch (maybe_sent.errno()) {
            .SUCCESS => return @intCast(@intFromEnum(maybe_sent)),
            .AGAIN => horizon.sleepThread(socket_busy_loop_workaround_ns),
            .NOMEM => return error.SystemResources,
            .CONNRESET => return error.ConnectionResetByPeer,
            else => |e| return unexpectedSocErrno(e),
        }
    }
}

pub fn netSend(storage: *Storage, io: std.Io, handle: Descriptor, messages: []Io.net.OutgoingMessage, flags: Io.net.SendFlags) struct { ?Io.net.Socket.SendError, usize } {
    const stored, const desc_flags = storage.getDescriptionStoredFlags(io, handle);

    if (desc_flags.kind != .socket) return .{ error.Unexpected, 0 };

    const soc = storage.net.soc;
    const sock = stored.socket;

    for (messages, 0..) |mes, i| {
        if (mes.address.* != .ip4) return .{ error.AddressFamilyUnsupported, i };

        const addr: SocketUser.IpAddress = .{ .ip4 = address4ToSoc(mes.address.ip4) };

        msg_sent: while (true) {
            const maybe_sent = soc.sendSendToMapped(sock, .{
                .out_of_band = flags.oob,
            }, mes.data_ptr[0..mes.data_len], &addr) catch |err| switch (err) {
                else => return .{ error.Unexpected, i },
            };

            switch (maybe_sent.errno()) {
                .SUCCESS => break :msg_sent,
                .AGAIN => horizon.sleepThread(socket_busy_loop_workaround_ns),
                else => |e| return .{ unexpectedSocErrno(e), i },
            }
        }
    }

    return .{ null, messages.len };
}

pub fn seekBy(storage: *Storage, io: std.Io, handle: Descriptor, offset: i64) Io.File.SeekError!void {
    storage.lock.lockSharedUncancelable(io);
    defer storage.lock.unlockShared(io);

    const desc = storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .socket, .directory => error.Unseekable,
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

pub fn seekTo(storage: *Storage, io: std.Io, handle: Descriptor, offset: u64) Io.File.SeekError!void {
    storage.lock.lockSharedUncancelable(io);
    defer storage.lock.unlockShared(io);

    const desc = storage.getDescription(handle);

    return switch (desc.flags.kind) {
        .socket, .directory => error.Unseekable,
        .file => while (true) {
            const seek = &desc.extra.seek;
            _ = seek.load();
            if (!seek.store(offset)) break;
        },
    };
}

/// Assumes `lock` is held as non-shareable.
pub fn close(storage: *Storage, io: std.Io, gpa: std.mem.Allocator, handle: Descriptor) void {
    const index = switch (handle) {
        .invalid, .cwd => programmerBug("invalid fd") catch return, // cwd is only valid in open
        _ => blk: {
            storage.lock.lockUncancelable(io);
            defer storage.lock.unlock(io);
            defer storage.fds.items[@intFromEnum(handle)] = .invalid;

            break :blk storage.fds.items[@intFromEnum(handle)];
        },
    };

    storage.closeDescription(io, gpa, index);
}

/// Assumes `lock` is held as non-shareable.
pub fn setCurrentDir(storage: *Storage, io: std.Io, gpa: std.mem.Allocator, handle: Descriptor) error{Unexpected}!void {
    const last_cwd = last: {
        storage.lock.lockUncancelable(io);
        defer storage.lock.unlock(io);

        const index = switch (handle) {
            .invalid, .cwd => return programmerBug("invalid fd"), // cwd is only valid in open
            _ => storage.fds.items[@intFromEnum(handle)],
        };

        const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
        std.debug.assert(desc.flags.kind == .directory);
        std.debug.assert(desc.ref.fetchAdd(1, .monotonic) > 0);

        const last_cwd = storage.cwd;
        storage.cwd = index;

        log.debug("cwd {} -> {}", .{ last_cwd, storage.cwd });

        break :last last_cwd;
    };

    switch (last_cwd) {
        .invalid => {},
        _ => |open| storage.closeDescription(io, gpa, open),
    }
}

fn address4ToSoc(address: Io.net.Ip4Address) SocketUser.Ip4Address {
    return .{ .bytes = address.bytes, .port = std.mem.nativeToBig(u16, address.port) };
}

fn address4FromSoc(address: SocketUser.Ip4Address) Io.net.Ip4Address {
    return .{ .bytes = address.bytes, .port = std.mem.bigToNative(u16, address.port) };
}

fn address6FromSoc(address: SocketUser.Ip6Address) Io.net.Ip6Address {
    return .{
        .bytes = address.bytes,
        .port = std.mem.bigToNative(u16, address.port),
        .flow = address.flow,
        .interface = .{ .index = 1 },
    };
}

fn addressFromSoc(address: SocketUser.IpAddress) Io.net.IpAddress {
    return switch (address.header.family) {
        .inet => .{ .ip4 = address4FromSoc(address.ip4) },
        .inet6 => .{ .ip6 = address6FromSoc(address.ip6) },
        else => unreachable,
    };
}

fn randomEphemeralPort(io: std.Io) u16 {
    var ephemeral: [2]u8 = undefined;
    io.random(&ephemeral);

    return @as(u16, 60000) + std.mem.readPackedInt(u12, &ephemeral, 0, .native);
}

fn splitParsePath(storage: *Storage, path: []const u8) error{BadPathName}!struct { ?u8, []const u8 } {
    return if (std.mem.findScalar(u8, path, '/')) |first_slash| dev: {
        break :dev if (std.mem.findScalar(u8, path[0..first_slash], ':')) |first_colon| {
            if (first_colon != first_slash - 1) return error.BadPathName;

            break :dev .{ storage.filesystem.find(path[0..first_colon]), path[(first_colon + 1)..] };
        } else .{ null, path };
    } else .{ null, path };
}

/// Buils a full path, returns the final path from `Builder.nullTerminator`
fn buildPath(storage: *Storage, builder: *Builder, io: std.Io, device_path: []const u8, stored: ?Description.Stored) error{ NameTooLong, BadPathName }![]u16 {
    const parent: []const u16 = if (Io.Dir.path.isAbsolutePosix(device_path))
        Builder.root
    else switch (stored.?.path) { // We already return NoDevice above
        .invalid => Builder.root,
        _ => |open| blk: {
            storage.lock.lockSharedUncancelable(io);
            defer storage.lock.unlockShared(io);

            break :blk storage.paths.list.items[@intFromEnum(open)].value;
        },
    };

    // + 1 for the NUL-terminator
    if (parent.len + device_path.len + 1 > Io.Dir.max_path_bytes) return error.NameTooLong;

    try builder.appendRaw(parent[0 .. parent.len - 1]); // Remove the NULL terminator as we don't need it
    try builder.append(device_path);

    return try builder.nullTerminate();
}

/// Returned description is `undefined` and must be initialized or freed with `closeUninitialized`
fn allocateDescription(storage: *Storage, io: std.Io, gpa: Allocator) error{SystemResources}!Descriptor {
    storage.lock.lockUncancelable(io);
    defer storage.lock.unlock(io);

    const fd = storage.allocateLowestDescriptor(gpa) catch return error.SystemResources;
    errdefer storage.fds.items[@intFromEnum(fd)] = .invalid;

    const free_desc = storage.descriptions.allocateOne(gpa) catch return error.SystemResources;
    errdefer storage.descriptions.free(free_desc);

    storage.fds.items[@intFromEnum(fd)] = free_desc;

    const desc = &storage.descriptions.list.items[@intFromEnum(free_desc)];
    desc.* = .{ .value = undefined };

    return fd;
}

/// Closes a `handle` pointing to a partial description.
fn closeUninitialized(storage: *Storage, io: std.Io, handle: Descriptor) void {
    storage.lock.lockUncancelable(io);
    defer storage.lock.unlock(io);

    const fd = &storage.fds.items[@intFromEnum(handle)];

    storage.descriptions.free(fd.*);
    fd.* = .invalid;
}

fn getDescriptionStoredFlags(storage: *Storage, io: std.Io, handle: Descriptor) struct { Description.Stored, Description.Flags } {
    storage.lock.lockSharedUncancelable(io);
    defer storage.lock.unlockShared(io);

    const desc = storage.getDescription(handle);
    // NOTE: These are basically RO after a description is created.
    return .{ desc.stored, desc.flags };
}

/// Assumes `lock` is held as shareable while the pointer is alive.
fn getDescription(storage: *Storage, handle: Descriptor) *Description {
    return switch (handle) {
        .invalid, .cwd => unreachable, // cwd is only valid in open
        _ => switch (storage.fds.items[@intFromEnum(handle)]) {
            .invalid => unreachable,
            else => |idx| &storage.descriptions.list.items[@intFromEnum(idx)].value,
        },
    };
}

/// May return null if `cwd` is unlinked
fn getDirectoryDescription(storage: *Storage, io: std.Io, handle: Descriptor) Io.UnexpectedError!?struct { Description.Stored, u8 } {
    storage.lock.lockSharedUncancelable(io);
    defer storage.lock.unlockShared(io);

    const dir_index = switch (handle) {
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
            break :blk .{ desc.stored, desc.flags.mount };
        },
    };
}

fn closeDescription(storage: *Storage, io: std.Io, gpa: Allocator, index: Description.Table.Index) void {
    std.debug.assert(index != .invalid); // UAF

    const free, const flags, const stored, const extra = blk: {
        storage.lock.lockSharedUncancelable(io);
        defer storage.lock.unlockShared(io);

        const desc = &storage.descriptions.list.items[@intFromEnum(index)].value;
        std.debug.assert(desc.ref.load(.monotonic) > 0);

        break :blk .{
            desc.ref.fetchSub(1, .monotonic) == 1,
            desc.flags,
            desc.stored,
            desc.extra,
        };
    };

    if (free) {
        switch (flags.kind) {
            .socket => stored.socket.close(storage.net.soc),
            .file, .directory => switch (storage.filesystem.mounts.items[flags.mount].data) {
                .romfs => {},
                .archive => switch (flags.kind) {
                    .socket => unreachable,
                    .file => stored.file.close(),
                    .directory => free: {
                        if (extra.dir.archive != FilesystemSrv.Directory.none) extra.dir.archive.close();

                        const path = blk: {
                            storage.lock.lockUncancelable(io);
                            defer storage.lock.unlock(io);

                            const idx = switch (stored.path) {
                                .invalid => break :free,
                                _ => |idx| idx,
                            };
                            defer storage.paths.free(idx);

                            break :blk storage.paths.list.items[@intFromEnum(idx)].value;
                        };

                        gpa.free(path);
                    },
                },
            },
        }

        {
            storage.lock.lockUncancelable(io);
            defer storage.lock.unlock(io);

            storage.descriptions.free(index);
        }

        log.debug("description {d} closed ({}, {})", .{ @intFromEnum(index), flags.mount, flags.kind });
    }
}

/// Assumes `lock` is held as non-shareable.
fn allocateLowestDescriptor(storage: *Storage, gpa: Allocator) Allocator.Error!Descriptor {
    for (storage.fds.items, 0..) |item, i| if (item == .invalid) {
        return @enumFromInt(i);
    };

    _ = try storage.fds.addOne(gpa);
    return @enumFromInt(storage.fds.items.len - 1);
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
                },
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

fn unexpectedSocErrno(errno: SocketUser.E) Io.UnexpectedError {
    log.err("unexpected errno: {}", .{errno});
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
const FilesystemSrv = horizon.services.Filesystem;
const SocketUser = horizon.services.SocketUser;
