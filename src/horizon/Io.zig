pub const File = struct {
    pub const Handle = Storage.Descriptor;
    pub const Flags = void;

    pub const Permissions = enum(u0) {
        default_file = 0,

        pub const default_dir: @This() = .default_file;
        pub const executable_file: @This() = .default_file;
        pub const has_executable_bit = false;
    };

    pub const stdin = @compileError("stdin is not supported");
    pub const stdout = @compileError("stdout is not supported");
    pub const stderr = @compileError("stderr is not supported");
};

pub const Dir = struct {
    pub const Handle = Storage.Descriptor;

    pub const max_path_bytes = 255;
    pub const max_name_bytes = max_path_bytes;

    pub fn cwd() Io.Dir {
        return .{ .handle = .cwd };
    }

    pub const Reader = struct {
        pub const min_buffer_len = Storage.Description.Extra.Directory.min_reader_buffer_len;
    };
};

pub const Operation = struct {
    pub const DeviceIoControl = noreturn;
};

pub const net = struct {
    pub const has_unix_sockets = false;

    pub const Socket = struct {
        pub const Handle = Storage.Descriptor;
    };
};

pub const LockedStderr = struct {
    term: Io.Terminal,

    pub fn terminal(ls: LockedStderr) Io.Terminal {
        return ls.term;
    }

    pub fn clear(ls: LockedStderr, buffer: []u8) Cancelable!void {
        ls.term.writer.flush() catch unreachable; // NOTE: Uncancelable & never fails
        ls.term.writer.buffer = buffer;
    }
};

var global_backing: horizon.Io = .{
    .gpa = .failing,
    .arbiter = .none,
    .debug_mutex_lock_count = 0,
    .debug_mutex_holder = std.math.maxInt(u32),
    .debug_mutex = .init,
    .debug_writer = horizon.outputDebugWriter(&.{}),
    .rng_mutex = .init,
    .rng = blk: {
        @setEvalBranchQuota(8000);
        break :blk .init(@splat(6_7));
    },
    .parking_futex = .init,
    .storage = .empty,
};

/// When using the horizon juicy main, this will be the backing memory of the `std.Io`
/// you and `std.debug` will get (via `debug_io`), as such you SHOULD initialize it if not using juicy main.
///
/// Not initializing it means calling any function is allowed to cause IB with these exceptions:
///
/// These functions are safe:
///     - tryLockStderr
///     - now, clockResolution, sleep
///
/// These functions are safe with caveats:
///     - lockStderr, unlockStderr -> IB if contended, as we do not have an `AddressArbiter`
///     - random -> seed is a known constant (67), IB if contended, as we do not have an `AddressArbiter`
pub const global: *horizon.Io = &global_backing;

/// See the doc-comment in `global`, same restrictions apply!
pub const debug_io = global.io();

/// A simple futex implementation based on `AddressArbiter` thread `Parker`s.
///
/// Fullfills the futex interface and is adapted from the implementation
/// in `std.Io.Threaded`. Instead of using multiple buckets we use one as
/// we know we'll have a very small number of threads, though it can be
/// incremented if proved wrong.
const ParkingFutex = struct {
    pub const init: ParkingFutex = .{};
    const Waiter = struct {
        address: usize,
        parker: AddressArbiter.Parker,
        node: std.DoublyLinkedList.Node,
    };

    /// Protects `waiters`
    mutex: AddressArbiter.Mutex = .{},
    num_waiters: std.atomic.Value(u32) = .init(0),
    waiters: std.DoublyLinkedList = .{},

    pub fn waitTimeout(fut: *ParkingFutex, arbiter: AddressArbiter, ptr: *const u32, expect: u32, timeout: horizon.Timeout) error{Timeout}!void {
        var waiter: Waiter = .{
            .address = @intFromPtr(ptr),
            .parker = .init,
            .node = .{},
        };

        {
            fut.mutex.lock(arbiter);
            defer fut.mutex.unlock(arbiter);

            _ = fut.num_waiters.fetchAdd(1, .acquire);

            if (@atomicLoad(u32, ptr, .monotonic) != expect) {
                std.debug.assert(fut.num_waiters.fetchSub(1, .monotonic) > 0);
                return;
            }

            fut.waiters.append(&waiter.node);
        }

        if (waiter.parker.parkTimeout(arbiter, timeout)) {
            // Nothing more to do, `wake` unparked us successfully and removed us from the waitlist.
        } else |err| switch (err) {
            error.Timeout => {
                if (@atomicLoad(usize, &waiter.address, .monotonic) != 0) {
                    fut.mutex.lock(arbiter);
                    defer fut.mutex.unlock(arbiter);

                    fut.waiters.remove(&waiter.node);
                    std.debug.assert(fut.num_waiters.fetchSub(1, .monotonic) > 0);
                    return error.Timeout;
                }

                // We raced with `wake`, who is going to unpark us right now so wait for that.
                waiter.parker.park(arbiter) catch |e| switch (e) {
                    error.Timeout => unreachable,
                };
            },
        }
    }

    pub fn wake(fut: *ParkingFutex, arbiter: AddressArbiter, ptr: *const u32, max_waiters: u32) void {
        if (max_waiters == 0) return;

        if (fut.num_waiters.fetchAdd(0, .release) == 0) {
            @branchHint(.likely);
            return;
        }

        // SinglyLinkedList of waiters to be unparked
        var waiters_head: ?*std.DoublyLinkedList.Node = null;
        {
            fut.mutex.lock(arbiter);
            defer fut.mutex.unlock(arbiter);

            var removed: u32 = 0;
            var it: ?*std.DoublyLinkedList.Node = fut.waiters.first;
            while (removed < max_waiters) {
                const waiter: *Waiter = @alignCast(@fieldParentPtr("node", it orelse break));
                it = waiter.node.next;
                if (waiter.address != @intFromPtr(ptr)) continue;
                // We're waking this waiter. Remove them from the bucket and add them to our local list.
                fut.waiters.remove(&waiter.node);
                waiter.node.next = waiters_head;
                waiters_head = &waiter.node;
                removed += 1;
                // Signal to `waiter` that they're about to be unparked, in case we're racing with their
                // timeout. See corresponding logic in `wake`.
                @atomicStore(usize, &waiter.address, 0, .monotonic);
            }

            _ = fut.num_waiters.fetchSub(removed, .monotonic);
        }

        while (waiters_head) |unparking| {
            waiters_head = unparking.next;

            const waiter: *Waiter = @alignCast(@fieldParentPtr("node", unparking));
            waiter.parker.unpark(arbiter);
        }
    }
};

/// Implements a POSIXY file descriptor layer.
pub const Storage = @import("Io/Storage.zig");

gpa: std.mem.Allocator,
arbiter: AddressArbiter,

debug_mutex_lock_count: usize,
debug_mutex_holder: horizon.Thread.Impl.Id,
debug_mutex: AddressArbiter.Mutex,
debug_writer: std.Io.Writer,

rng_mutex: AddressArbiter.Mutex,
rng: std.Random.DefaultCsprng,

parking_futex: ParkingFutex,
storage: Storage,

/// All handles must live until `deinit`
pub fn init(
    gpa: std.mem.Allocator,
    arbiter: AddressArbiter,
) HIo {
    const tick = horizon.getSystemTick();

    return .{
        .gpa = gpa,
        .arbiter = arbiter,
        .debug_mutex_lock_count = 0,
        .debug_mutex_holder = std.math.maxInt(u32),
        .debug_mutex = .init,
        .debug_writer = horizon.outputDebugWriter(&.{}),
        .rng_mutex = .init,
        .rng = blk: {
            var seed: [32]u8 = undefined;
            var expand: std.Random.SplitMix64 = .init(tick);
            seed[0..8].* = @bitCast(expand.next());
            seed[8..16].* = @bitCast(expand.next());
            seed[16..24].* = @bitCast(expand.next());
            seed[24..32].* = @bitCast(expand.next());
            break :blk .init(seed);
        },
        .parking_futex = .init,
        .storage = .empty,
    };
}

/// Initializes `hio.storage`, owning the specified backends.
/// Will be closed on `deinit`.
pub fn initStorage(hio: *HIo, srv: horizon.ServiceManager, backends: enum { fs, soc, both }, soc_buffer_len: usize) !void {
    if (backends != .soc) {
        const fs = try Filesystem.open(.user, srv);
        errdefer fs.close();

        try fs.sendInitialize();
        try hio.initFilesystem(.{ .fs = fs, .extra = .owned });
    }
    errdefer hio.deinitFilesystem();

    if (backends != .fs) {
        const soc = try SocketUser.open(srv);
        errdefer soc.close();

        try hio.initNetwork(.{ .soc = soc, .extra = .{ .owned = soc_buffer_len } });
    }
    errdefer hio.deinitNetwork();
}

pub fn initFilesystem(hio: *HIo, opts: Storage.Filesystem.Init) !void {
    try hio.storage.filesystem.init(opts);
}

pub fn initNetwork(hio: *HIo, opts: Storage.Network.Init) !void {
    try hio.storage.net.init(hio.gpa, opts);
}

pub fn deinitFilesystem(hio: *HIo) void {
    hio.storage.filesystem.deinit(hio.gpa);
}

pub fn deinitNetwork(hio: *HIo) void {
    hio.storage.net.deinit(hio.gpa);
}

pub fn mountArchive(hio: *HIo, name: []const u8, id: Filesystem.ArchiveId, path_type: Filesystem.PathType, path: []const u8) !void {
    try hio.storage.filesystem.mountArchive(hio.gpa, name, id, path_type, path);
}

pub fn mountSelfRomFs(hio: *HIo, name: []const u8) !void {
    try hio.storage.filesystem.mountSelfRomFs(hio.gpa, name);
}

pub fn umount(hio: *HIo, name: []const u8) void {
    hio.storage.filesystem.umount(hio.gpa, name);
}

pub fn unlinkCurrentDir(hio: *HIo) void {
    hio.storage.unlinkCurrentDir(hio.io(), hio.gpa);
}

pub fn deinit(hio: *HIo) void {
    hio.storage.deinit(hio.io(), hio.gpa);
    hio.* = undefined;
}

pub fn io(hio: *HIo) Io {
    return .{
        .userdata = hio,
        .vtable = if (std.Io.VTable == VTable) &.default else comptime unreachable, // We depend on our zig fork currently
    };
}

pub const VTable = enum(u0) {
    default,

    // TODO: async will always be run synchronously, spawning threads here doesn't make much sense.
    // We don't want a lot of context switches unless it's necessary (concurrent!)
    pub fn async(
        _: VTable,
        _: ?*anyopaque,
        result: []u8,
        _: std.mem.Alignment,
        context: []const u8,
        _: std.mem.Alignment,
        start: *const fn (context: *const anyopaque, result: *anyopaque) void,
    ) ?*Io.AnyFuture {
        start(context.ptr, result.ptr);
        return null;
    }

    pub fn concurrent(
        _: VTable,
        _: ?*anyopaque,
        _: usize,
        _: std.mem.Alignment,
        _: []const u8,
        _: std.mem.Alignment,
        _: *const fn (context: *const anyopaque, result: *anyopaque) void,
    ) Io.ConcurrentError!*Io.AnyFuture {
        return error.ConcurrencyUnavailable;
    }

    pub fn await(
        _: VTable,
        _: ?*anyopaque,
        _: *Io.AnyFuture,
        _: []u8,
        _: std.mem.Alignment,
    ) void {
        unreachable; // TODO: Nothing to await
    }

    pub fn cancel(
        _: VTable,
        _: ?*anyopaque,
        _: *Io.AnyFuture,
        _: []u8,
        _: std.mem.Alignment,
    ) void {
        unreachable; // TODO: Nothing to cancel
    }

    // TODO: group* not implemented

    pub fn groupAsync(
        _: VTable,
        _: ?*anyopaque,
        _: *Io.Group,
        context: []const u8,
        _: std.mem.Alignment,
        start: *const fn (context: *const anyopaque) void,
    ) void {
        start(context.ptr);
    }

    pub fn groupAwait(_: VTable, _: ?*anyopaque, _: *Io.Group, _: *anyopaque) Cancelable!void {
        // TODO: Nothing to cancel
    }

    pub fn groupCancel(_: VTable, _: ?*anyopaque, _: *Io.Group, _: *anyopaque) void {
        // TODO: Nothing to cancel
    }

    pub fn recancel(_: VTable, _: ?*anyopaque) void {}

    pub fn swapCancelProtection(_: VTable, _: ?*anyopaque, _: CancelProtection) CancelProtection {
        return .blocked; // NOTE: We cannot cancel (AFAIK) so we're always blocked
    }

    pub fn checkCancel(_: VTable, ud: ?*anyopaque) Cancelable!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        _ = hio;
    }

    pub fn futexWait(_: VTable, ud: ?*anyopaque, ptr: *const u32, expected: u32, timeout: Io.Timeout) Cancelable!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const h_timeout: horizon.Timeout = blk: {
            const duration = timeout.toDurationFromNow(hio.io()) orelse break :blk .none;
            break :blk .fromNanoseconds(std.math.lossyCast(u63, duration.raw.toNanoseconds()));
        };

        hio.parking_futex.waitTimeout(hio.arbiter, ptr, expected, h_timeout) catch |err| switch (err) {
            error.Timeout => {},
        };
    }

    pub fn futexWaitUncancelable(_: VTable, ud: ?*anyopaque, ptr: *const u32, expected: u32) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        hio.parking_futex.waitTimeout(hio.arbiter, ptr, expected, .none) catch |err| switch (err) {
            error.Timeout => unreachable,
        };
    }

    pub fn futexWake(_: VTable, ud: ?*anyopaque, ptr: *const u32, max_waiters: u32) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        hio.parking_futex.wake(hio.arbiter, ptr, max_waiters);
    }

    pub fn operate(_: VTable, ud: ?*anyopaque, operation: Io.Operation) Cancelable!Io.Operation.Result {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return try hio.storage.operate(hio.io(), operation);
    }

    pub fn batchAwaitAsync(_: VTable, ud: ?*anyopaque, b: *Io.Batch) Cancelable!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return try hio.storage.batchAwaitAsync(hio.io(), hio.gpa, b);
    }

    pub fn batchAwaitConcurrent(_: VTable, ud: ?*anyopaque, b: *Io.Batch, timeout: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return try hio.storage.batchAwaitConcurrent(hio.io(), hio.gpa, b, timeout);
    }

    pub fn batchCancel(_: VTable, ud: ?*anyopaque, b: *Io.Batch) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return hio.storage.batchCancel(hio.gpa, b);
    }

    pub fn dirCreateDir(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, _: Io.Dir.Permissions) Io.Dir.CreateDirError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.modifyPath(hio.io(), dir.handle, path, .create_dir) catch |err| switch (err) {
            error.IsDir => unreachable,
            else => |e| return e,
        };
    }

    pub fn dirCreateDirPath(_: VTable, ud: ?*anyopaque, dir: Io.Dir, sub_path: []const u8, _: Io.Dir.Permissions) Io.Dir.CreateDirPathError!Io.Dir.CreatePathStatus {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.createDirPath(hio.io(), dir.handle, sub_path);
    }

    pub fn dirCreateDirPathOpen(_: VTable, ud: ?*anyopaque, dir: Io.Dir, sub_path: []const u8, _: Io.Dir.Permissions, opts: Io.Dir.OpenOptions) Io.Dir.CreateDirPathOpenError!Io.Dir {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        try dir.createDirPath(hio.io(), sub_path);
        return try dir.openDir(hio.io(), sub_path, opts);
    }

    pub fn dirOpenDir(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, opts: Io.Dir.OpenOptions) Io.Dir.OpenError!Io.Dir {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        _ = opts;

        return .{
            .handle = hio.storage.openPath(hio.io(), hio.gpa, dir.handle, path, .{
                .mode = .read_only,
                .allow = .directory,
            }) catch |err| switch (err) {
                error.IsDir, error.PathAlreadyExists => unreachable,
                error.ReadOnlyFileSystem => return error.AccessDenied, // XXX: see dirOpenFile
                else => |e| return e,
            },
        };
    }

    pub fn dirStat(_: VTable, ud: ?*anyopaque, dir: Io.Dir) Io.Dir.StatError!Io.Dir.Stat {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.stat(hio.io(), dir.handle);
    }

    pub fn dirStatFile(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, opts: Io.Dir.StatFileOptions) Io.Dir.StatFileError!Io.File.Stat {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const file = try dir.openFile(hio.io(), path, .{ .follow_symlinks = opts.follow_symlinks });
        defer file.close(hio.io());

        return file.stat(hio.io());
    }

    pub fn dirAccess(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, opts: Io.Dir.AccessOptions) Io.Dir.AccessError!void {
        if (opts.execute) return error.PermissionDenied;
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.accessPath(hio.io(), dir.handle, path, opts.read, opts.write) catch |err| switch (err) {
            error.NoDevice => return error.InputOutput,
            else => |e| return e,
        };
    }

    pub fn dirCreateFile(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, opts: Io.File.CreateFlags) Io.File.OpenError!Io.File {
        if (opts.lock == .exclusive) return error.FileLocksUnsupported;

        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const file: Io.File = .{
            .handle = hio.storage.openPath(hio.io(), hio.gpa, dir.handle, path, .{
                .mode = if (opts.read) .read_write else .write_only,
                .create = if (opts.exclusive) .exclusive else .create,
                .allow = .file,
            }) catch |err| switch (err) {
                error.NotDir => unreachable,
                error.ReadOnlyFileSystem => return error.AccessDenied,
                else => |e| return e,
            },
            .flags = {},
        };
        errdefer file.close(hio.io());

        if (opts.truncate) file.setLength(hio.io(), 0) catch |err| switch (err) {
            error.NonResizable, error.InputOutput => unreachable, // NOTE: we never return these for writeable files
            else => |e| return e,
        };
        return file;
    }

    pub fn dirCreateFileAtomic(_: VTable, ud: ?*anyopaque, dir: Io.Dir, sub_path: []const u8, opts: Io.Dir.CreateFileAtomicOptions) Io.Dir.CreateFileAtomicError!Io.File.Atomic {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        // NOTE: Atomic files are emulated but we leave the path handling to storage.
        return try Storage.createFileAtomic(hio.io(), dir, sub_path, opts);
    }

    pub fn dirOpenFile(_: VTable, ud: ?*anyopaque, dir: Io.Dir, path: []const u8, opts: Io.File.OpenFlags) Io.File.OpenError!Io.File {
        if (opts.lock == .exclusive) return error.FileLocksUnsupported;

        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return .{
            .handle = hio.storage.openPath(hio.io(), hio.gpa, dir.handle, path, .{
                .mode = opts.mode,
                .allow = if (opts.allow_directory) .any else .file,
            }) catch |err| switch (err) {
                error.NotDir => unreachable,
                error.ReadOnlyFileSystem => return error.AccessDenied, // XXX: ... we should have this in OpenError
                else => |e| return e,
            },
            .flags = {},
        };
    }

    pub fn dirClose(_: VTable, ud: ?*anyopaque, dirs: []const Io.Dir) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        for (dirs) |dir| hio.storage.close(hio.io(), hio.gpa, dir.handle);
    }

    pub fn dirRead(_: VTable, ud: ?*anyopaque, r: *Io.Dir.Reader, entries: []Io.Dir.Entry) Io.Dir.Reader.Error!usize {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return try hio.storage.readDir(hio.io(), r, entries);
    }

    pub fn dirRealPath(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []u8) Io.Dir.RealPathError!usize {
        return error.OperationUnsupported; // TODO: This *could* be supported
    }

    pub fn dirRealPathFile(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: []u8) Io.Dir.RealPathFileError!usize {
        return error.OperationUnsupported; // TODO: This *could* be supported
    }

    pub fn dirDeleteFile(_: VTable, ud: ?*anyopaque, dir: Io.Dir, sub_path: []const u8) Io.Dir.DeleteFileError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.modifyPath(hio.io(), dir.handle, sub_path, .delete_file) catch |err| switch (err) {
            error.PathAlreadyExists => unreachable,
            error.NoDevice => return error.FileSystem,
            else => |e| return e,
        };
    }

    pub fn dirDeleteDir(_: VTable, ud: ?*anyopaque, dir: Io.Dir, sub_path: []const u8) Io.Dir.DeleteDirError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.modifyPath(hio.io(), dir.handle, sub_path, .delete_dir) catch |err| switch (err) {
            error.PathAlreadyExists => unreachable,
            error.NoDevice => return error.FileSystem,
            error.IsDir => unreachable,
            else => |e| return e,
        };
    }

    pub fn dirRename(_: VTable, ud: ?*anyopaque, src_dir: Io.Dir, src_path: []const u8, dst_dir: Io.Dir, dst_path: []const u8) Io.Dir.RenameError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.renamePath(hio.io(), src_dir.handle, src_path, dst_dir.handle, dst_path, false) catch |err| switch (err) {
            error.PathAlreadyExists, error.OperationUnsupported, error.AccessDenied => unreachable,
            else => |e| return e,
        };
    }

    pub fn dirRenamePreserve(_: VTable, ud: ?*anyopaque, src_dir: Io.Dir, src_path: []const u8, dst_dir: Io.Dir, dst_path: []const u8) Io.Dir.RenamePreserveError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.renamePath(hio.io(), hio.gpa, src_dir.handle, src_path, dst_dir.handle, dst_path, true);
    }

    pub fn dirSymLink(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: []const u8, _: Io.Dir.SymLinkFlags) Io.Dir.SymLinkError!void {
        return error.FileSystem; // symlinks not supported
    }

    pub fn dirReadLink(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: []u8) Io.Dir.ReadLinkError!usize {
        return error.NotLink;
    }

    pub fn dirSetOwner(_: VTable, _: ?*anyopaque, _: Io.Dir, _: ?Io.File.Uid, _: ?Io.File.Gid) Io.Dir.SetOwnerError!void {
        return error.PermissionDenied;
    }

    pub fn dirSetFileOwner(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: ?Io.File.Uid, _: ?Io.File.Gid, _: Io.Dir.SetFileOwnerOptions) Io.Dir.SetFileOwnerError!void {
        return error.PermissionDenied;
    }

    pub fn dirSetPermissions(_: VTable, _: ?*anyopaque, _: Io.Dir, _: Io.Dir.Permissions) Io.Dir.SetPermissionsError!void {
        return error.PermissionDenied;
    }

    pub fn dirSetFilePermissions(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.File.Permissions, _: Io.Dir.SetFilePermissionsOptions) Io.Dir.SetFilePermissionsError!void {
        return error.PermissionDenied;
    }

    pub fn dirSetTimestamps(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir.SetTimestampsOptions) Io.Dir.SetTimestampsError!void {}

    pub fn dirHardLink(_: VTable, _: ?*anyopaque, _: Io.Dir, _: []const u8, _: Io.Dir, _: []const u8, _: Io.Dir.HardLinkOptions) Io.Dir.HardLinkError!void {
        return error.OperationUnsupported;
    }

    pub fn fileStat(_: VTable, ud: ?*anyopaque, file: Io.File) Io.File.StatError!Io.File.Stat {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.stat(hio.io(), file.handle);
    }

    pub fn fileLength(_: VTable, ud: ?*anyopaque, file: Io.File) Io.File.LengthError!u64 {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.length(hio.io(), file.handle);
    }

    pub fn fileClose(_: VTable, ud: ?*anyopaque, files: []const Io.File) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        for (files) |file| hio.storage.close(hio.io(), hio.gpa, file.handle);
    }

    pub fn fileWritePositional(_: VTable, ud: ?*anyopaque, file: Io.File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) Io.File.WritePositionalError!usize {
        const buf = if (header.len != 0)
            header
        else buf: for (data[0 .. data.len - 1]) |buf| {
            if (buf.len == 0) continue;
            break :buf buf;
        } else if (data[data.len - 1].len > 0 and splat > 0)
            data[data.len - 1]
        else
            return 0;

        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.writePositional(hio.io(), file.handle, buf, offset);
    }

    pub fn fileWriteFileStreaming(_: VTable, _: ?*anyopaque, _: Io.File, _: []const u8, _: *Io.File.Reader, _: Io.Limit) Io.File.Writer.WriteFileError!usize {
        return error.Unimplemented;
    }

    pub fn fileWriteFilePositional(_: VTable, _: ?*anyopaque, _: Io.File, _: []const u8, _: *Io.File.Reader, _: Io.Limit, _: u64) Io.File.WriteFilePositionalError!usize {
        return error.Unimplemented;
    }

    pub fn fileReadPositional(_: VTable, ud: ?*anyopaque, file: Io.File, data: []const []u8, offset: u64) Io.File.ReadPositionalError!usize {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        for (data) |buf| {
            if (buf.len == 0) continue;

            return try hio.storage.readPositional(hio.io(), file.handle, buf, offset);
        }

        return 0;
    }

    pub fn fileSeekBy(_: VTable, ud: ?*anyopaque, file: Io.File, offset: i64) Io.File.SeekError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.seekBy(hio.io(), file.handle, offset);
    }

    pub fn fileSeekTo(_: VTable, ud: ?*anyopaque, file: Io.File, offset: u64) Io.File.SeekError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.seekTo(hio.io(), file.handle, offset);
    }

    pub fn fileSync(_: VTable, _: ?*anyopaque, _: Io.File) Io.File.SyncError!void {}

    pub fn fileIsTty(_: VTable, _: ?*anyopaque, _: Io.File) Cancelable!bool {
        return false; // A file can never be a tty
    }

    pub fn fileEnableAnsiEscapeCodes(_: VTable, _: ?*anyopaque, _: Io.File) Io.File.EnableAnsiEscapeCodesError!void {
        return error.NotTerminalDevice;
    }

    pub fn fileSupportsAnsiEscapeCodes(_: VTable, _: ?*anyopaque, _: Io.File) Cancelable!bool {
        return false;
    }

    pub fn fileSetLength(_: VTable, ud: ?*anyopaque, file: Io.File, new_length: u64) Io.File.SetLengthError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.setLength(hio.io(), file.handle, new_length);
    }

    pub fn fileSetOwner(_: VTable, _: ?*anyopaque, _: Io.File, _: ?Io.File.Uid, _: ?Io.File.Gid) Io.File.SetOwnerError!void {
        return error.PermissionDenied;
    }

    pub fn fileSetPermissions(_: VTable, _: ?*anyopaque, _: Io.File, _: Io.File.Permissions) Io.File.SetPermissionsError!void {
        return error.PermissionDenied;
    }

    pub fn fileSetTimestamps(_: VTable, _: ?*anyopaque, _: Io.File, _: Io.File.SetTimestampsOptions) Io.File.SetTimestampsError!void {}

    pub fn fileLock(_: VTable, _: ?*anyopaque, _: Io.File, _: Io.File.Lock) Io.File.LockError!void {
        return error.FileLocksUnsupported;
    }

    pub fn fileTryLock(_: VTable, _: ?*anyopaque, _: Io.File, _: Io.File.Lock) Io.File.LockError!bool {
        return error.FileLocksUnsupported;
    }

    pub fn fileUnlock(_: VTable, _: ?*anyopaque, _: Io.File) void {}

    pub fn fileDowngradeLock(_: VTable, _: ?*anyopaque, _: Io.File) Io.File.DowngradeLockError!void {
        unreachable;
    }

    pub fn fileRealPath(_: VTable, _: ?*anyopaque, _: Io.File, _: []u8) Io.File.RealPathError!usize {
        return error.OperationUnsupported; // TODO: This *could* be supported.
    }

    pub fn fileHardLink(_: VTable, _: ?*anyopaque, _: Io.File, _: Io.Dir, _: []const u8, _: Io.File.HardLinkOptions) Io.File.HardLinkError!void {
        return error.OperationUnsupported;
    }

    pub fn fileMemoryMapCreate(_: VTable, ud: ?*anyopaque, file: Io.File, options: Io.File.MemoryMap.CreateOptions) Io.File.MemoryMap.CreateError!Io.File.MemoryMap {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const gpa = hio.gpa;

        const offset = options.offset;
        const len = options.len;

        const page_size = std.heap.pageSize();
        const alignment: std.mem.Alignment = .fromByteUnits(page_size);
        const memory = m: {
            const ptr = gpa.rawAlloc(len, alignment, @returnAddress()) orelse return error.OutOfMemory;
            break :m ptr[0..len];
        };
        errdefer gpa.rawFree(memory, alignment, @returnAddress());

        if (!options.undefined_contents) try file.readPositionalAll(hio.io(), memory, offset);

        return .{
            .file = file,
            .offset = offset,
            .memory = @alignCast(memory),
            .section = null,
        };
    }

    pub fn fileMemoryMapDestroy(_: VTable, ud: ?*anyopaque, mm: *Io.File.MemoryMap) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const gpa = hio.gpa;

        gpa.rawFree(mm.memory, .fromByteUnits(std.heap.pageSize()), @returnAddress());
        mm.* = undefined;
    }

    pub fn fileMemoryMapSetLength(_: VTable, ud: ?*anyopaque, mm: *Io.File.MemoryMap, new_len: usize) Io.File.MemoryMap.SetLengthError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const gpa = hio.gpa;
        const page_size = std.heap.pageSize();
        const alignment: std.mem.Alignment = .fromByteUnits(page_size);
        const old_memory = mm.memory;

        if (gpa.rawRemap(old_memory, alignment, new_len, @returnAddress())) |new_ptr| {
            mm.memory = @alignCast(new_ptr[0..new_len]);
        } else {
            const new_ptr: [*]align(horizon.heap.page_size) u8 = @alignCast(
                gpa.rawAlloc(new_len, alignment, @returnAddress()) orelse return error.OutOfMemory,
            );
            const copy_len = @min(new_len, old_memory.len);
            @memcpy(new_ptr[0..copy_len], old_memory[0..copy_len]);
            mm.memory = new_ptr[0..new_len];
            gpa.rawFree(old_memory, alignment, @returnAddress());
        }
    }

    pub fn fileMemoryMapRead(_: VTable, ud: ?*anyopaque, mm: *Io.File.MemoryMap) Io.File.ReadPositionalError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        try mm.file.readPositionalAll(hio.io(), mm.memory, mm.offset);
    }

    pub fn fileMemoryMapWrite(_: VTable, ud: ?*anyopaque, mm: *Io.File.MemoryMap) Io.File.WritePositionalError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        try mm.file.writePositionalAll(hio.io(), mm.memory, mm.offset);
    }

    pub fn processExecutableOpen(_: VTable, _: ?*anyopaque, _: Io.File.OpenFlags) std.process.OpenExecutableError!Io.File {
        return error.OperationUnsupported; // XXX: This could be supported but useless as we're either in a NCCH or 3dsx.
    }

    pub fn processExecutablePath(_: VTable, _: ?*anyopaque, _: []u8) std.process.ExecutablePathError!usize {
        return error.OperationUnsupported;
    }

    pub fn lockStderr(_: VTable, ud: ?*anyopaque, _: ?Io.Terminal.Mode) Cancelable!LockedStderr {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const current_id = horizon.Thread.Impl.getCurrentId();

        if (@atomicLoad(horizon.Thread.Impl.Id, &hio.debug_mutex_holder, .unordered) != current_id) {
            hio.debug_mutex.lock(hio.arbiter);
            std.debug.assert(hio.debug_mutex_lock_count == 0);
            @atomicStore(horizon.Thread.Impl.Id, &hio.debug_mutex_holder, current_id, .unordered);
        }
        hio.debug_mutex_lock_count += 1;

        return .{
            .term = .{
                .writer = &hio.debug_writer,
                .mode = .no_color,
            },
        };
    }

    pub fn tryLockStderr(_: VTable, ud: ?*anyopaque, _: ?Io.Terminal.Mode) Cancelable!?LockedStderr {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const current_id = horizon.Thread.Impl.getCurrentId();

        if (@atomicLoad(horizon.Thread.Impl.Id, &hio.debug_mutex_holder, .unordered) != current_id) {
            if (!hio.debug_mutex.tryLock()) return null;
            std.debug.assert(hio.debug_mutex_lock_count == 0);
            @atomicStore(horizon.Thread.Impl.Id, &hio.debug_mutex_holder, current_id, .unordered);
        }
        hio.debug_mutex_lock_count += 1;

        return .{
            .term = .{
                .writer = &hio.debug_writer,
                .mode = .no_color,
            },
        };
    }

    pub fn unlockStderr(_: VTable, ud: ?*anyopaque) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        hio.debug_writer.flush() catch unreachable; // NOTE: uncancelable & cannot fail

        hio.debug_mutex_lock_count -= 1;
        if (hio.debug_mutex_lock_count == 0) {
            @atomicStore(horizon.Thread.Impl.Id, &hio.debug_mutex_holder, std.math.maxInt(u32), .unordered);
            hio.debug_mutex.unlock(hio.arbiter);
        }
    }

    pub fn processCurrentPath(_: VTable, _: ?*anyopaque, buffer: []u8) std.process.CurrentPathError!usize {
        if (buffer.len == 0) return error.NameTooLong;
        return error.CurrentDirUnlinked; // TODO: We can support this!
    }

    pub fn processSetCurrentDir(_: VTable, ud: ?*anyopaque, dir: Io.Dir) std.process.SetCurrentDirError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.setCurrentDir(hio.io(), hio.gpa, dir.handle);
    }

    pub fn processSetCurrentPath(_: VTable, ud: ?*anyopaque, path: []const u8) std.process.SetCurrentPathError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        const h_io = hio.io();

        const dir = Io.Dir.cwd().openDir(h_io, path, .{}) catch |err| switch (err) {
            error.PermissionDenied,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.NetworkNotFound,
            => unreachable, // NOTE: We don't even return these
            else => |e| return e,
        };
        defer dir.close(h_io);

        return std.process.setCurrentDir(h_io, dir) catch |err| switch (err) {
            error.UnrecognizedVolume => unreachable, // NOTE: same
            else => |e| return e,
        };
    }

    pub fn processReplace(_: VTable, _: ?*anyopaque, _: std.process.ReplaceOptions) std.process.ReplaceError {
        return error.OperationUnsupported;
    }

    pub fn processReplacePath(_: VTable, _: ?*anyopaque, _: Io.Dir, _: std.process.ReplaceOptions) std.process.ReplaceError {
        return error.OperationUnsupported;
    }

    pub fn processSpawn(_: VTable, _: ?*anyopaque, _: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
        return error.OperationUnsupported;
    }

    pub fn processSpawnPath(_: VTable, _: ?*anyopaque, _: Io.Dir, _: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
        return error.OperationUnsupported;
    }

    pub fn childWait(_: VTable, _: ?*anyopaque, _: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term {
        unreachable; // No child to wait
    }

    pub fn childKill(_: VTable, _: ?*anyopaque, _: *std.process.Child) void {
        unreachable; // No child to kill
    }

    pub fn progressParentFile(_: VTable, _: ?*anyopaque) std.Progress.ParentFileError!Io.File {
        return error.UnsupportedOperation;
    }

    pub fn now(_: VTable, _: ?*anyopaque, clock: Clock) Io.Timestamp {
        return switch (clock) {
            .awake, .boot => .fromNanoseconds(@intCast(horizon.time.getSystemNanoseconds())),
            .real => @panic("TODO: now(real)"),
            .cpu_process, .cpu_thread => .fromNanoseconds(0),
        };
    }

    pub fn clockResolution(_: ?*anyopaque, clock: Clock) Clock.ResolutionError!Io.Duration {
        return switch (clock) {
            .awake, .boot => .fromNanoseconds(1),
            .real => .fromMilliseconds(1),
            .cpu_process, .cpu_thread => error.ClockUnavailable,
        };
    }

    pub fn sleep(_: VTable, ud: ?*anyopaque, timeout: Io.Timeout) Cancelable!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        if (timeout.toDurationFromNow(hio.io())) |duration| {
            horizon.sleepThread(std.math.lossyCast(i64, duration.raw.toNanoseconds()));
        } else horizon.sleepThread(std.math.maxInt(i64));
    }

    pub fn random(_: VTable, ud: ?*anyopaque, buffer: []u8) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        hio.rng_mutex.lock(hio.arbiter);
        defer hio.rng_mutex.unlock(hio.arbiter);

        hio.rng.fill(buffer);
    }

    pub fn randomSecure(_: VTable, _: ?*anyopaque, _: []u8) Io.RandomSecureError!void {
        return error.EntropyUnavailable; // XXX: Is there any truly random entropy source in hos?
    }

    pub fn netListenIp(_: VTable, ud: ?*anyopaque, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.ListenOptions) Io.net.IpAddress.ListenError!Io.net.Socket {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.netListen(hio.io(), hio.gpa, address, opts);
    }

    pub fn netAccept(_: VTable, ud: ?*anyopaque, handle: Io.net.Socket.Handle, opts: Io.net.Server.AcceptOptions) Io.net.Server.AcceptError!Io.net.Socket {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.netAccept(hio.io(), hio.gpa, handle, opts);
    }

    pub fn netBindIp(_: VTable, ud: ?*anyopaque, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.BindOptions) Io.net.IpAddress.BindError!Io.net.Socket {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.netBind(hio.io(), hio.gpa, address, opts);
    }

    pub fn netConnectIp(_: VTable, ud: ?*anyopaque, address: *const Io.net.IpAddress, opts: Io.net.IpAddress.ConnectOptions) Io.net.IpAddress.ConnectError!Io.net.Socket {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.netConnect(hio.io(), hio.gpa, address, opts);
    }

    pub fn netListenUnix(_: VTable, _: ?*anyopaque, _: *const Io.net.UnixAddress, _: Io.net.UnixAddress.ListenOptions) Io.net.UnixAddress.ListenError!Io.net.Socket.Handle {
        return error.AddressFamilyUnsupported;
    }

    pub fn netConnectUnix(_: VTable, _: ?*anyopaque, _: *const Io.net.UnixAddress) Io.net.UnixAddress.ConnectError!Io.net.Socket.Handle {
        return error.AddressFamilyUnsupported;
    }

    pub fn netSocketCreatePair(_: VTable, _: ?*anyopaque, _: Io.net.Socket.CreatePairOptions) Io.net.Socket.CreatePairError![2]Io.net.Socket {
        return error.OperationUnsupported;
    }

    pub fn netSend(_: VTable, ud: ?*anyopaque, handle: Io.net.Socket.Handle, messages: []Io.net.OutgoingMessage, flags: Io.net.SendFlags) struct { ?Io.net.Socket.SendError, usize } {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return hio.storage.netSend(hio.io(), handle, messages, flags);
    }

    pub fn netRead(_: VTable, ud: ?*anyopaque, handle: Io.net.Socket.Handle, data: [][]u8) Io.net.Stream.Reader.Error!usize {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        for (data) |buf| {
            if (buf.len == 0) continue;

            return try hio.storage.netRead(hio.io(), handle, buf);
        }

        return 0;
    }

    pub fn netWrite(_: VTable, ud: ?*anyopaque, handle: Io.net.Socket.Handle, header: []const u8, data: []const []const u8, splat: usize) Io.net.Stream.Writer.Error!usize {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        const buf = if (header.len != 0)
            header
        else buf: for (data[0 .. data.len - 1]) |buf| {
            if (buf.len == 0) continue;
            break :buf buf;
        } else if (data[data.len - 1].len > 0 and splat > 0)
            data[data.len - 1]
        else
            return 0;

        return try hio.storage.netWrite(hio.io(), handle, buf);
    }

    pub fn netWriteFile(_: VTable, _: ?*anyopaque, _: Io.net.Socket.Handle, _: []const u8, _: *Io.File.Reader, _: Io.Limit) Io.net.Stream.Writer.WriteFileError!usize {
        @panic("TODO");
    }

    pub fn netClose(_: VTable, ud: ?*anyopaque, sockets: []const Io.net.Socket.Handle) void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        for (sockets) |handle| hio.storage.close(hio.io(), hio.gpa, handle);
    }

    pub fn netShutdown(_: VTable, ud: ?*anyopaque, handle: Io.net.Socket.Handle, how: Io.net.ShutdownHow) Io.net.ShutdownError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));

        return try hio.storage.netShutdown(hio.io(), handle, how);
    }

    pub fn netInterfaceNameResolve(_: VTable, _: ?*anyopaque, name: *const Io.net.Interface.Name) Io.net.Interface.Name.ResolveError!Io.net.Interface {
        return if (std.mem.eql(u8, name.bytes[0 .. std.mem.findScalar(u8, name.bytes, 0) orelse name.bytes.len], "wlan0"))
            .{ .index = 1 }
        else
            error.InterfaceNotFound;
    }

    pub fn netInterfaceName(_: VTable, _: ?*anyopaque, iface: Io.net.Interface) Io.net.Interface.NameError!Io.net.Interface.Name {
        std.debug.assert(iface.index == 1);
        return .fromSliceUnchecked("wlan0");
    }

    pub fn netLookup(_: VTable, ud: ?*anyopaque, host_name: Io.net.HostName, results: *Io.Queue(Io.net.HostName.LookupResult), opts: Io.net.HostName.LookupOptions) Io.net.HostName.LookupError!void {
        const hio: *HIo = @ptrCast(@alignCast(ud.?));
        return try hio.storage.netLookup(hio.io(), hio.gpa, host_name, results, opts);
    }
};

comptime {
    _ = Storage;
    _ = ParkingFutex;

    if (builtin.os.tag == .@"3ds") _ = @import("Io/test.zig");
}

// a.k.a "Horizon Io"
const HIo = @This();

const builtin = @import("builtin");

const Cancelable = Io.Cancelable;
const CancelProtection = Io.CancelProtection;
const Clock = Io.Clock;
const std = @import("std");
const Io = std.Io;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const romfs = horizon.fmt.ncch.romfs;

const AddressArbiter = horizon.AddressArbiter;
const services = horizon.services;

const Filesystem = services.Filesystem;
const SocketUser = services.SocketUser;
