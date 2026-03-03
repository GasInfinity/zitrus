//! std.Io and std.fs tests ~yoinked~ imported from std (as we can't test it directly)
//!
//! omits tests which will always be skipped (e.g we don't have symlinks) or are irrelevant.

// NOTE: INode is void but it seems zig expects that it is an integer, wouldn't it be better for it to be an u0?

test "write a file, read it, then delete it" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var data: [1024]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(testing.random_seed);
    const random = prng.random();
    random.bytes(data[0..]);
    const tmp_file_name = "temp_test_file.txt";
    {
        var file = try tmp.dir.createFile(io, tmp_file_name, .{});
        defer file.close(io);

        var file_writer = file.writer(io, &.{});
        const st = &file_writer.interface;
        try st.print("begin", .{});
        try st.writeAll(&data);
        try st.print("end", .{});
        try st.flush();
    }

    {
        // Make sure the exclusive flag is honored.
        try expectError(Io.File.OpenError.PathAlreadyExists, tmp.dir.createFile(io, tmp_file_name, .{ .exclusive = true }));
    }

    {
        var file = try tmp.dir.openFile(io, tmp_file_name, .{});
        defer file.close(io);

        const file_size = try file.length(io);
        const expected_file_size: u64 = "begin".len + data.len + "end".len;
        try expectEqual(expected_file_size, file_size);

        var file_buffer: [1024]u8 = undefined;
        var file_reader = file.reader(io, &file_buffer);
        const contents = try file_reader.interface.allocRemaining(testing.allocator, .limited(2 * 1024));
        defer testing.allocator.free(contents);

        try expect(mem.eql(u8, contents[0.."begin".len], "begin"));
        try expect(mem.eql(u8, contents["begin".len .. contents.len - "end".len], &data));
        try expect(mem.eql(u8, contents[contents.len - "end".len ..], "end"));
    }
    try tmp.dir.deleteFile(io, tmp_file_name);
}

test "File.Writer.seekTo" {
    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const io = testing.io;

    var data: [8192]u8 = undefined;
    @memset(&data, 0x55);

    const tmp_file_name = "temp_test_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    var fw = file.writerStreaming(io, &.{});

    try fw.interface.writeAll(&data);
    try expect(fw.logicalPos() == try file.length(io));
    try fw.seekTo(1234);
    try expect(fw.logicalPos() == 1234);
}

test "File.setLength" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const tmp_file_name = "temp_test_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    var fw = file.writerStreaming(io, &.{});

    // Verify that the file size changes and the file offset is not moved
    try expect((try file.length(io)) == 0);
    try expect(fw.logicalPos() == 0);
    try file.setLength(io, 8192);
    try expect((try file.length(io)) == 8192);
    try expect(fw.logicalPos() == 0);
    try fw.seekTo(100);
    try file.setLength(io, 4096);
    try expect((try file.length(io)) == 4096);
    try expect(fw.logicalPos() == 100);
    try file.setLength(io, 0);
    try expect((try file.length(io)) == 0);
    try expect(fw.logicalPos() == 100);
}

test "legacy setLength" {
    // https://github.com/ziglang/zig/issues/20747 (open fd does not have write permission)
    if (builtin.os.tag == .wasi and builtin.link_libc) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64() and (builtin.abi == .gnuabin32 or builtin.abi == .muslabin32)) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/23806

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const file_name = "afile.txt";
    try tmp.dir.writeFile(io, .{ .sub_path = file_name, .data = "ninebytes" });
    const f = try tmp.dir.openFile(io, file_name, .{ .mode = .read_write });
    defer f.close(io);

    const initial_size = try f.length(io);
    var buffer: [32]u8 = undefined;
    var reader = f.reader(io, &.{});

    {
        try f.setLength(io, initial_size);
        try expectEqual(initial_size, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(initial_size, try reader.interface.readSliceShort(&buffer));
        try expectEqualStrings("ninebytes", buffer[0..@intCast(initial_size)]);
    }

    {
        const larger = initial_size + 4;
        try f.setLength(io, larger);
        try expectEqual(larger, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(larger, try reader.interface.readSliceShort(&buffer));
        // NOTE: Horizon fills the length with 0x55 so this is not portable!
        // try expectEqualStrings("ninebytes\x00\x00\x00\x00", buffer[0..@intCast(larger)]);
    }

    {
        const smaller = initial_size - 5;
        try f.setLength(io, smaller);
        try expectEqual(smaller, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(smaller, try reader.interface.readSliceShort(&buffer));
        try expectEqualStrings("nine", buffer[0..@intCast(smaller)]);
    }

    try f.setLength(io, 0);
    try expectEqual(0, try f.length(io));
    try reader.seekTo(0);
    try expectEqual(0, try reader.interface.readSliceShort(&buffer));
}

test "Dir.Iterator" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.array_list.Managed(Dir.Entry).init(allocator);

    // Create iterator.
    var iter = tmp_dir.dir.iterate();
    while (try iter.next(io)) |entry| {
        // We cannot just store `entry` as on Windows, we're re-using the name buffer
        // which means we'll actually share the `name` pointer between entries!
        const name = try allocator.dupe(u8, entry.name);
        try entries.append(Dir.Entry{ .name = name, .kind = entry.kind, .inode = {} });
    }

    try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
    try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = {} }));
    try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = {} }));
}

test "Dir.Iterator many entries" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    const num = 32; // 1024; // We're not stress-testing the 3ds (it still works however!)
    var i: usize = 0;
    var buf: [4]u8 = undefined; // Enough to store "1024".
    while (i < num) : (i += 1) {
        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
        const file = try tmp_dir.dir.createFile(io, name, .{});
        file.close(io);
    }

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.array_list.Managed(Dir.Entry).init(allocator);

    // Create iterator.
    var iter = tmp_dir.dir.iterate();
    while (try iter.next(io)) |entry| {
        // We cannot just store `entry` as on Windows, we're re-using the name buffer
        // which means we'll actually share the `name` pointer between entries!
        const name = try allocator.dupe(u8, entry.name);
        try entries.append(.{ .name = name, .kind = entry.kind, .inode = {} });
    }

    i = 0;
    while (i < num) : (i += 1) {
        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
        try expect(contains(&entries, .{ .name = name, .kind = .file, .inode = {} }));
    }
}

test "Dir.Iterator twice" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var i: u8 = 0;
    while (i < 2) : (i += 1) {
        var entries = std.array_list.Managed(Dir.Entry).init(allocator);

        // Create iterator.
        var iter = tmp_dir.dir.iterate();
        while (try iter.next(io)) |entry| {
            // We cannot just store `entry` as on Windows, we're re-using the name buffer
            // which means we'll actually share the `name` pointer between entries!
            const name = try allocator.dupe(u8, entry.name);
            try entries.append(Dir.Entry{ .name = name, .kind = entry.kind, .inode = {} });
        }

        try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
        try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = {} }));
        try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = {} }));
    }
}

test "Dir.Iterator reset" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create iterator.
    var iter = tmp_dir.dir.iterate();

    var i: u8 = 0;
    while (i < 2) : (i += 1) {
        var entries = std.array_list.Managed(Dir.Entry).init(allocator);

        while (try iter.next(io)) |entry| {
            // We cannot just store `entry` as on Windows, we're re-using the name buffer
            // which means we'll actually share the `name` pointer between entries!
            const name = try allocator.dupe(u8, entry.name);
            try entries.append(.{ .name = name, .kind = entry.kind, .inode = {} });
        }

        try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
        try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = {} }));
        try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = {} }));

        iter.reader.reset();
    }
}

test "Dir.Iterator but dir is deleted during iteration" {
    const io = testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create directory and setup an iterator for it
    var subdir = try tmp.dir.createDirPathOpen(io, "subdir", .{ .open_options = .{ .iterate = true } });
    defer subdir.close(io);

    var iterator = subdir.iterate();

    // Create something to iterate over within the subdir
    try tmp.dir.createDirPath(io, "subdir" ++ Dir.path.sep_str ++ "b");

    // Then, before iterating, delete the directory that we're iterating.
    // This is a contrived reproduction, but this could happen outside of the program, in another thread, etc.
    // If we get an error while trying to delete, we can skip this test (this will happen on platforms
    // like Windows which will give FileBusy if the directory is currently open for iteration).
    tmp.dir.deleteTree(io, "subdir") catch return error.SkipZigTest;

    // Now, when we try to iterate, the next call should return null immediately.
    const entry = try iterator.next(io);
    try testing.expect(entry == null);
}

test "createDirPathOpen parent dirs do not exist" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{});
    defer tmp_dir.cleanup();

    var dir = try tmp_dir.dir.createDirPathOpen(io, "root_dir/parent_dir/some_dir", .{});
    dir.close(io);

    // double check that the full directory structure was created
    var dir_verification = try tmp_dir.dir.openDir(io, "root_dir/parent_dir/some_dir", .{});
    dir_verification.close(io);
}

test "rename" {
    const io = testing.io;

    var tmp_dir1 = tmpDir(.{});
    defer tmp_dir1.cleanup();

    var tmp_dir2 = tmpDir(.{});
    defer tmp_dir2.cleanup();

    // Renaming files
    const test_file_name = "test_file";
    const renamed_test_file_name = "test_file_renamed";
    var file = try tmp_dir1.dir.createFile(io, test_file_name, .{ .read = true });
    file.close(io);
    try Dir.rename(tmp_dir1.dir, test_file_name, tmp_dir2.dir, renamed_test_file_name, io);

    // ensure the file was renamed
    try expectError(error.FileNotFound, tmp_dir1.dir.openFile(io, test_file_name, .{}));
    file = try tmp_dir2.dir.openFile(io, renamed_test_file_name, .{});
    file.close(io);
}

test "createDirPath in a directory that no longer exists" {
    if (native_os == .windows) return error.SkipZigTest; // Windows returns FileBusy if attempting to remove an open dir
    if (native_os == .dragonfly) return error.SkipZigTest; // DragonflyBSD does not produce error (hammer2 fs)

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();
    try tmp.parent_dir.deleteTree(io, &tmp.sub_path);

    try expectError(error.FileNotFound, tmp.dir.createDirPath(io, "sub-path"));
}

test "createDirPath but sub_path contains pre-existing file" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "foo", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "foo/bar", .data = "" });

    try expectError(error.NotDir, tmp.dir.createDirPath(io, "foo/bar/baz"));
}

fn expectDir(io: Io, dir: Dir, path: []const u8) !void {
    var d = try dir.openDir(io, path, .{});
    d.close(io);
}

test "makepath existing directories" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "A", .default_dir);
    var tmpA = try tmp.dir.openDir(io, "A", .{});
    defer tmpA.close(io);
    try tmpA.createDir(io, "B", .default_dir);

    const testPath = "A" ++ Dir.path.sep_str ++ "B" ++ Dir.path.sep_str ++ "C";
    try tmp.dir.createDirPath(io, testPath);

    try expectDir(io, tmp.dir, testPath);
}

test "makepath relative walks" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const relPath = try Dir.path.join(testing.allocator, &.{
        "first", "..", "second", "..", "third", "..", "first", "A", "..", "B", "..", "C",
    });
    defer testing.allocator.free(relPath);

    try tmp.dir.createDirPath(io, relPath);

    // How .. is handled is different on Windows than non-Windows
    switch (native_os) {
        .@"3ds", .windows => {
            // On Windows, .. is resolved before passing the path to NtCreateFile,
            // meaning everything except `first/C` drops out.

            // On 3ds we also have that behavior
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "C");
            try expectError(error.FileNotFound, tmp.dir.access(io, "second", .{}));
            try expectError(error.FileNotFound, tmp.dir.access(io, "third", .{}));
        },
        else => {
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "A");
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "B");
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "C");
            try expectDir(io, tmp.dir, "second");
            try expectDir(io, tmp.dir, "third");
        },
    }
}

test "makepath ignores '.'" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Path to create, with "." elements:
    const dotPath = try Dir.path.join(testing.allocator, &.{
        "first", ".", "second", ".", "third",
    });
    defer testing.allocator.free(dotPath);

    // Path to expect to find:
    const expectedPath = try Dir.path.join(testing.allocator, &.{
        "first", "second", "third",
    });
    defer testing.allocator.free(expectedPath);

    try tmp.dir.createDirPath(io, dotPath);

    try expectDir(io, tmp.dir, expectedPath);
}

test "writev, readv" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const line1 = "line1\n";
    const line2 = "line2\n";

    var buf1: [line1.len]u8 = undefined;
    var buf2: [line2.len]u8 = undefined;
    var write_vecs: [2][]const u8 = .{ line1, line2 };
    var read_vecs: [2][]u8 = .{ &buf2, &buf1 };

    var src_file = try tmp.dir.createFile(io, "test.txt", .{ .read = true });
    defer src_file.close(io);

    var writer = src_file.writerStreaming(io, &.{});

    try writer.interface.writeVecAll(&write_vecs);
    try writer.interface.flush();
    try expectEqual(@as(u64, line1.len + line2.len), try src_file.length(io));

    var reader = writer.moveToReader();
    try reader.seekTo(0);
    try reader.interface.readVecAll(&read_vecs);
    try expectEqualStrings(&buf1, "line2\n");
    try expectEqualStrings(&buf2, "line1\n");
    try expectError(error.EndOfStream, reader.interface.readSliceAll(&buf1));
}

test "pwritev, preadv" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const line1 = "line1\n";
    const line2 = "line2\n";
    var lines: [2][]const u8 = .{ line1, line2 };
    var buf1: [line1.len]u8 = undefined;
    var buf2: [line2.len]u8 = undefined;
    var read_vecs: [2][]u8 = .{ &buf2, &buf1 };

    var src_file = try tmp.dir.createFile(io, "test.txt", .{ .read = true });
    defer src_file.close(io);

    var writer = src_file.writer(io, &.{});

    try writer.seekTo(16);
    try writer.interface.writeVecAll(&lines);
    try writer.interface.flush();
    try expectEqual(@as(u64, 16 + line1.len + line2.len), try src_file.length(io));

    var reader = writer.moveToReader();
    try reader.seekTo(16);
    try reader.interface.readVecAll(&read_vecs);
    try expectEqualStrings(&buf1, "line2\n");
    try expectEqualStrings(&buf2, "line1\n");
    try expectError(error.EndOfStream, reader.interface.readSliceAll(&buf1));
}

test "walker" {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // iteration order of walker is undefined, so need lookup maps to check against

    const expected_paths = std.StaticStringMap(usize).initComptime(.{
        .{ "dir1", 1 },
        .{ "dir2", 1 },
        .{ "dir3", 1 },
        .{ "dir4", 1 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub1", 2 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub2", 2 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub2" ++ Dir.path.sep_str ++ "subsub1", 3 },
    });

    const expected_basenames = std.StaticStringMap(void).initComptime(.{
        .{"dir1"},
        .{"dir2"},
        .{"dir3"},
        .{"dir4"},
        .{"sub1"},
        .{"sub2"},
        .{"subsub1"},
    });

    for (expected_paths.keys()) |key| {
        try tmp.dir.createDirPath(io, key);
    }

    var walker = try tmp.dir.walk(testing.allocator);
    defer walker.deinit();

    var num_walked: usize = 0;
    while (try walker.next(io)) |entry| {
        expect(expected_basenames.has(entry.basename)) catch |err| {
            std.debug.print("found unexpected basename: {f}\n", .{std.ascii.hexEscape(entry.basename, .lower)});
            return err;
        };
        expect(expected_paths.has(entry.path)) catch |err| {
            std.debug.print("found unexpected path: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        expectEqual(expected_paths.get(entry.path).?, entry.depth()) catch |err| {
            std.debug.print("path reported unexpected depth: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        // make sure that the entry.dir is the containing dir
        var entry_dir = try entry.dir.openDir(io, entry.basename, .{});
        defer entry_dir.close(io);
        num_walked += 1;
    }
    try expectEqual(expected_paths.kvs.len, num_walked);
}

test "selective walker, skip entries that start with ." {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const paths_to_create: []const []const u8 = &.{
        "dir1/foo/.git/ignored",
        ".hidden/bar",
        "a/b/c",
        "a/baz",
    };

    // iteration order of walker is undefined, so need lookup maps to check against

    const expected_paths = std.StaticStringMap(usize).initComptime(.{
        .{ "dir1", 1 },
        .{ "dir1" ++ Dir.path.sep_str ++ "foo", 2 },
        .{ "a", 1 },
        .{ "a" ++ Dir.path.sep_str ++ "b", 2 },
        .{ "a" ++ Dir.path.sep_str ++ "b" ++ Dir.path.sep_str ++ "c", 3 },
        .{ "a" ++ Dir.path.sep_str ++ "baz", 2 },
    });

    const expected_basenames = std.StaticStringMap(void).initComptime(.{
        .{"dir1"},
        .{"foo"},
        .{"a"},
        .{"b"},
        .{"c"},
        .{"baz"},
    });

    for (paths_to_create) |path| {
        try tmp.dir.createDirPath(io, path);
    }

    var walker = try tmp.dir.walkSelectively(testing.allocator);
    defer walker.deinit();

    var num_walked: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.basename[0] == '.') continue;
        if (entry.kind == .directory) {
            try walker.enter(io, entry);
        }

        expect(expected_basenames.has(entry.basename)) catch |err| {
            std.debug.print("found unexpected basename: {f}\n", .{std.ascii.hexEscape(entry.basename, .lower)});
            return err;
        };
        expect(expected_paths.has(entry.path)) catch |err| {
            std.debug.print("found unexpected path: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        expectEqual(expected_paths.get(entry.path).?, entry.depth()) catch |err| {
            std.debug.print("path reported unexpected depth: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };

        // make sure that the entry.dir is the containing dir
        var entry_dir = try entry.dir.openDir(io, entry.basename, .{});
        defer entry_dir.close(io);
        num_walked += 1;
    }
    try expectEqual(expected_paths.kvs.len, num_walked);
}

// XXX: leaks memory?
// test "walker without fully iterating" {
//     const io = testing.io;
//
//     var tmp = tmpDir(.{ .iterate = true });
//     defer tmp.cleanup();
//
//     var walker = try tmp.dir.walk(testing.allocator);
//     defer walker.deinit();
//
//     // Create 2 directories inside the tmp directory, but then only iterate once before breaking.
//     // This ensures that walker doesn't try to close the initial directory when not fully iterating.
//
//     try tmp.dir.createDirPath(io, "a");
//     try tmp.dir.createDirPath(io, "b");
//
//     var num_walked: usize = 0;
//     while (try walker.next(io)) |_| {
//         num_walked += 1;
//         break;
//     }
//     try expectEqual(@as(usize, 1), num_walked);
// }

test "read file non vectored" {
    const io = std.testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const contents = "hello, world!\n";

    const file = try tmp_dir.dir.createFile(io, "input.txt", .{ .read = true });
    defer file.close(io);
    {
        var file_writer: File.Writer = .init(file, io, &.{});
        try file_writer.interface.writeAll(contents);
        try file_writer.interface.flush();
    }

    var file_reader: std.Io.File.Reader = .init(file, io, &.{});

    var write_buffer: [100]u8 = undefined;
    var w: std.Io.Writer = .fixed(&write_buffer);

    var i: usize = 0;
    while (true) {
        i += file_reader.interface.stream(&w, .limited(3)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
    }
    try expectEqualStrings(contents, w.buffered());
    try expectEqual(contents.len, i);
}

test "seek keeping partial buffer" {
    const io = std.testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const contents = "0123456789";

    const file = try tmp_dir.dir.createFile(io, "input.txt", .{ .read = true });
    defer file.close(io);
    {
        var file_writer: File.Writer = .init(file, io, &.{});
        try file_writer.interface.writeAll(contents);
        try file_writer.interface.flush();
    }

    var read_buffer: [3]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &read_buffer);

    try expectEqual(0, file_reader.logicalPos());

    var buf: [4]u8 = undefined;
    try file_reader.interface.readSliceAll(&buf);

    if (file_reader.interface.bufferedLen() != 3) {
        // Pass the test if the OS doesn't give us vectored reads.
        return;
    }

    try expectEqual(4, file_reader.logicalPos());
    try expectEqual(7, file_reader.pos);
    try file_reader.seekTo(6);
    try expectEqual(6, file_reader.logicalPos());
    try expectEqual(7, file_reader.pos);

    try expectEqualStrings("0123", &buf);

    const n = try file_reader.interface.readSliceShort(&buf);
    try expectEqual(4, n);

    try expectEqualStrings("6789", &buf);
}

test "seekBy" {
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "blah.txt", .data = "let's test seekBy" });
    const f = try tmp_dir.dir.openFile(io, "blah.txt", .{ .mode = .read_only });
    defer f.close(io);
    var reader = f.readerStreaming(io, &.{});
    try reader.seekBy(2);

    var buffer: [20]u8 = undefined;
    const n = try reader.interface.readSliceShort(&buffer);
    try expectEqual(15, n);
    try expectEqualStrings("t's test seekBy", buffer[0..15]);
}

test "seekTo flushes buffered data" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;

    const contents = "data";

    const file = try tmp.dir.createFile(io, "seek.bin", .{ .read = true });
    defer file.close(io);
    {
        var buf: [16]u8 = undefined;
        var file_writer = file.writer(io, &buf);

        try file_writer.interface.writeAll(contents);
        try file_writer.seekTo(8);
        try file_writer.interface.flush();
    }

    var read_buffer: [16]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(file, io, &read_buffer);

    var buf: [4]u8 = undefined;
    try file_reader.interface.readSliceAll(&buf);
    try expectEqualStrings(contents, &buf);
}

test "File.Writer sendfile with buffered contents" {
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        try tmp_dir.dir.writeFile(io, .{ .sub_path = "a", .data = "bcd" });
        const in = try tmp_dir.dir.openFile(io, "a", .{});
        defer in.close(io);
        const out = try tmp_dir.dir.createFile(io, "b", .{});
        defer out.close(io);

        var in_buf: [2]u8 = undefined;
        var in_r = in.reader(io, &in_buf);
        _ = try in_r.getSize(); // Catch seeks past end by populating size
        try in_r.interface.fill(2);

        var out_buf: [1]u8 = undefined;
        var out_w = out.writerStreaming(io, &out_buf);
        try out_w.interface.writeByte('a');
        try expectEqual(3, try out_w.interface.sendFileAll(&in_r, .unlimited));
        try out_w.interface.flush();
    }

    var check = try tmp_dir.dir.openFile(io, "b", .{});
    defer check.close(io);
    var check_buf: [4]u8 = undefined;
    var check_r = check.reader(io, &check_buf);
    try expectEqualStrings("abcd", try check_r.interface.take(4));
    try expectError(error.EndOfStream, check_r.interface.takeByte());
}

test "isatty" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "foo", .{});
    defer file.close(io);

    try expectEqual(false, try file.isTty(io));
}

test "read positional empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pread_empty", .{ .read = true });
    defer file.close(io);

    var buffer: [0]u8 = undefined;
    try expectEqual(0, try file.readPositional(io, &.{&buffer}, 0));
}

test "write streaming empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "write_empty", .{});
    defer file.close(io);

    const buffer: [0]u8 = .{};
    try file.writeStreamingAll(io, &buffer);
}

test "write positional empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pwrite_empty", .{});
    defer file.close(io);

    const buffer: [0]u8 = .{};
    try expectEqual(0, try file.writePositional(io, &.{&buffer}, 0));
}

test "access smoke test" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    {
        // Create some file using `open`.
        const file = try tmp.dir.createFile(io, "some_file", .{ .read = true, .exclusive = true });
        file.close(io);
    }

    {
        // Try to access() the file
        if (native_os == .windows) {
            try tmp.dir.access(io, "some_file", .{});
        } else {
            try tmp.dir.access(io, "some_file", .{ .read = true, .write = true });
        }
    }

    {
        // Try to access() a non-existent file - should fail with error.FileNotFound
        try expectError(error.FileNotFound, tmp.dir.access(io, "some_other_file", .{}));
    }

    {
        // Create some directory
        try tmp.dir.createDir(io, "some_dir", .default_dir);
    }

    {
        // Try to access() the directory
        try tmp.dir.access(io, "some_dir", .{});
    }
}

test "write streaming a long vector" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pwritev", .{});
    defer file.close(io);

    var vecs: [2000][]const u8 = undefined;
    for (&vecs) |*v| v.* = "a";

    const n = try file.writePositional(io, &vecs, 0);
    try expect(n <= vecs.len);
}

test "open smoke test" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    // TODO verify file attributes using `fstat`

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const io = testing.io;

    {
        // Create some file using `open`.
        const file = try tmp.dir.createFile(io, "some_file", .{ .exclusive = true });
        file.close(io);
    }

    // Try this again with the same flags. This op should fail with error.PathAlreadyExists.
    try expectError(
        error.PathAlreadyExists,
        tmp.dir.createFile(io, "some_file", .{ .exclusive = true }),
    );

    {
        // Try opening without exclusive flag.
        const file = try tmp.dir.createFile(io, "some_file", .{});
        file.close(io);
    }

    try expectError(error.NotDir, tmp.dir.openDir(io, "some_file", .{}));
    try tmp.dir.createDir(io, "some_dir", .default_dir);

    {
        const dir = try tmp.dir.openDir(io, "some_dir", .{});
        dir.close(io);
    }

    // Try opening as file which should fail.
    try expectError(error.IsDir, tmp.dir.openFile(io, "some_dir", .{ .allow_directory = false }));
}

test "stat smoke test" {
    if (native_os == .wasi and !builtin.link_libc) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // create dummy file
    const contents = "nonsense";
    try tmp.dir.writeFile(io, .{ .sub_path = "file.txt", .data = contents });

    // fetch file's info on the opened fd directly
    const file = try tmp.dir.openFile(io, "file.txt", .{});
    const stat = try file.stat(io);
    defer file.close(io);

    // now repeat but using directory handle instead
    const statat = try tmp.dir.statFile(io, "file.txt", .{ .follow_symlinks = false });

    try expectEqual(stat.inode, statat.inode);
    try expectEqual(stat.nlink, statat.nlink);
    try expectEqual(stat.size, statat.size);
    try expectEqual(stat.permissions, statat.permissions);
    try expectEqual(stat.kind, statat.kind);
    try expectEqual(stat.atime, statat.atime);
    try expectEqual(stat.mtime, statat.mtime);
    try expectEqual(stat.ctime, statat.ctime);
}

fn entryEql(lhs: Dir.Entry, rhs: Dir.Entry) bool {
    return mem.eql(u8, lhs.name, rhs.name) and lhs.kind == rhs.kind;
}

fn contains(entries: *const std.array_list.Managed(Dir.Entry), el: Dir.Entry) bool {
    for (entries.items) |entry| {
        if (entryEql(entry, el)) return true;
    }
    return false;
}

test "random" {
    const io = testing.io;

    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;

    io.random(@ptrCast(&a));
    io.random(@ptrCast(&b));
    io.random(@ptrCast(&c));

    try std.testing.expect(a ^ b ^ c != 0);
}

fn testQueue(comptime len: usize) !void {
    const io = testing.io;
    var buf: [len]usize = undefined;
    var queue: Io.Queue(usize) = .init(&buf);
    var begin: usize = 0;
    for (1..len + 1) |n| {
        const end = begin + n;
        for (begin..end) |i| try queue.putOne(io, i);
        for (begin..end) |i| try expect(try queue.getOne(io) == i);
        begin = end;
    }
}

test "Queue" {
    try testQueue(1);
    try testQueue(2);
    try testQueue(3);
    try testQueue(4);
    try testQueue(5);
}

test "Queue.close single-threaded" {
    const io = std.testing.io;

    var buf: [10]u8 = undefined;
    var queue: Io.Queue(u8) = .init(&buf);

    try queue.putAll(io, &.{ 0, 1, 2, 3, 4, 5, 6 });
    try expectEqual(3, try queue.put(io, &.{ 7, 8, 9, 10 }, 0)); // there is capacity for 3 more items

    var get_buf: [4]u8 = undefined;

    // Receive some elements before closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(0, get_buf[0]);
    try expectEqual(1, get_buf[1]);
    try expectEqual(2, get_buf[2]);
    try expectEqual(3, get_buf[3]);
    try expectEqual(4, try queue.getOne(io));

    // ...and add a couple more now there's space
    try queue.putAll(io, &.{ 20, 21 });

    queue.close(io);

    // Receive more elements *after* closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(5, get_buf[0]);
    try expectEqual(6, get_buf[1]);
    try expectEqual(7, get_buf[2]);
    try expectEqual(8, get_buf[3]);
    try expectEqual(9, try queue.getOne(io));

    // Cannot put anything while closed, even if the buffer has space
    try expectError(error.Closed, queue.putOne(io, 100));
    try expectError(error.Closed, queue.putAll(io, &.{ 101, 102 }));
    try expectError(error.Closed, queue.putUncancelable(io, &.{ 103, 104 }, 0));

    // Even if we ask for 3 items, the queue is closed, so we only get the last 2
    try expectEqual(2, try queue.get(io, &get_buf, 4));
    try expectEqual(20, get_buf[0]);
    try expectEqual(21, get_buf[1]);

    // The queue is now empty, so `get` should return `error.Closed` too
    try expectError(error.Closed, queue.getOne(io));
    try expectError(error.Closed, queue.get(io, &get_buf, 0));
    try expectError(error.Closed, queue.putUncancelable(io, &get_buf, 2));
}

test "Event smoke test" {
    const io = testing.io;

    var event: Io.Event = .unset;
    try testing.expectEqual(false, event.isSet());

    // make sure the event gets set
    event.set(io);
    try testing.expectEqual(true, event.isSet());

    // make sure the event gets unset again
    event.reset();
    try testing.expectEqual(false, event.isSet());

    // waits should timeout as there's no other thread to set the event
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .zero,
        .clock = .awake,
    } }));
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .fromMilliseconds(1),
        .clock = .awake,
    } }));

    // set the event again and make sure waits complete
    event.set(io);
    try event.wait(io);
    try event.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } });
    try testing.expectEqual(true, event.isSet());
}

test "Event signaling" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const Context = struct {
        in: Io.Event = .unset,
        out: Io.Event = .unset,
        value: usize = 0,

        fn input(self: *@This()) !void {
            // wait for the value to become 1
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 1);

            // bump the value and wake up output()
            self.value = 2;
            self.out.set(io);

            // wait for output to receive 2, bump the value and wake us up with 3
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 3);

            // bump the value and wake up output() for it to see 4
            self.value = 4;
            self.out.set(io);
        }

        fn output(self: *@This()) !void {
            // start with 0 and bump the value for input to see 1
            try testing.expectEqual(self.value, 0);
            self.value = 1;
            self.in.set(io);

            // wait for input to receive 1, bump the value to 2 and wake us up
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 2);

            // bump the value to 3 for input to see (rhymes)
            self.value = 3;
            self.in.set(io);

            // wait for input to bump the value to 4 and receive no more (rhymes)
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 4);
        }
    };

    var ctx = Context{};

    const thread = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, Context.output, .{&ctx});
    defer thread.join();

    try ctx.input();
}

test "Event broadcast" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const num_threads = 10;
    const Barrier = struct {
        event: Io.Event = .unset,
        counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(num_threads),

        fn wait(self: *@This()) void {
            if (self.counter.fetchSub(1, .acq_rel) == 1) {
                self.event.set(io);
            }
        }
    };

    const Context = struct {
        start_barrier: Barrier = .{},
        finish_barrier: Barrier = .{},

        fn run(self: *@This()) void {
            self.start_barrier.wait();
            self.finish_barrier.wait();
        }
    };

    var ctx = Context{};
    var threads: [num_threads - 1]std.Thread = undefined;

    for (&threads) |*t| t.* = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, Context.run, .{&ctx});
    defer for (threads) |t| t.join();

    ctx.run();
}

test Semaphore {
    if (builtin.single_threaded) return error.SkipZigTest;
    const io = testing.io;

    const TestContext = struct {
        sem: *Semaphore,
        n: *i32,
        fn worker(ctx: *@This()) !void {
            try ctx.sem.wait(io);
            ctx.n.* += 1;
            ctx.sem.post(io);
        }
    };
    const num_threads = 3;
    var sem: Semaphore = .{ .permits = 1 };
    var threads: [num_threads]std.Thread = undefined;
    var n: i32 = 0;
    var ctx = TestContext{ .sem = &sem, .n = &n };

    for (&threads) |*t| t.* = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, TestContext.worker, .{&ctx});
    for (threads) |t| t.join();
    try sem.wait(io);
    try testing.expect(n == num_threads);
}

test "RwLock internal state" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockUncancelable(io);
    rl.unlock(io);
    try testing.expectEqual(rl, Io.RwLock.init);
}

test "RwLock smoke test" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    try testing.expect(rl.tryLock(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    rl.lockSharedUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    try testing.expect(rl.tryLockShared(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    rl.lockUncancelable(io);
    rl.unlock(io);
}

test "RwLock concurrent access" {
    if (builtin.single_threaded) return;

    const io = testing.io;
    const num_writers: usize = 2;
    const num_readers: usize = 4;
    const num_writes: usize = 1000;
    const num_reads: usize = 2000;

    const Runner = struct {
        const Runner = @This();

        io: Io,

        rl: Io.RwLock,
        writes: usize,
        reads: std.atomic.Value(usize),

        val_a: usize,
        val_b: usize,

        fn reader(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockSharedUncancelable(run.io);
                defer run.rl.unlockShared(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.reads.fetchAdd(1, .monotonic) >= num_reads) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *const volatile usize = &run.val_a;
                const b_ptr: *const volatile usize = &run.val_b;

                const old_a = a_ptr.*;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                try testing.expect(old_a == old_b);
            }
        }

        fn writer(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockUncancelable(run.io);
                defer run.rl.unlock(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.writes == num_writes) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *volatile usize = &run.val_a;
                const b_ptr: *volatile usize = &run.val_b;

                const new_val = rnd.int(usize);

                const old_a = a_ptr.*;
                a_ptr.* = new_val;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                b_ptr.* = new_val;
                try testing.expect(old_a == old_b);

                run.writes += 1;
            }
        }
    };

    var run: Runner = .{
        .io = io,
        .rl = .init,
        .writes = 0,
        .reads = .init(0),
        .val_a = 0,
        .val_b = 0,
    };
    var write_threads: [num_writers]std.Thread = undefined;
    var read_threads: [num_readers]std.Thread = undefined;

    for (&write_threads, 0..) |*t, i| t.* = try .spawn(.{
        .allocator = testing.allocator,
    }, Runner.writer, .{ &run, i });
    for (&read_threads, num_writers..) |*t, i| t.* = try .spawn(.{
        .allocator = testing.allocator,
    }, Runner.reader, .{ &run, i });

    for (write_threads) |t| t.join();
    for (read_threads) |t| t.join();

    try testing.expect(run.writes == num_writes);
    try testing.expect(run.reads.raw >= num_reads);
}

comptime {
    _ = @import("net/test.zig");
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual  = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const tmpDir = std.testing.tmpDir;

const native_os = builtin.target.os.tag;

const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const Dir = Io.Dir;
const File = Io.File;
const Semaphore = Io.Semaphore;
const ArenaAllocator = std.heap.ArenaAllocator;
