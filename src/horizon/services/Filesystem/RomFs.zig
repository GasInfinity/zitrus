//! High-level RomFs abstraction handling the difference between
//! 3DSX and NCCH-based executables.
//!
//! The 3DSX's RomFS is NOT in `SelfNCCH` as we would be opening the app's RomFS.
//!
//! We're given in argv our 'sdmc:' path so I think its clear we must open it
//! ourselves.
//!
//! TODO: Can that path NOT start with 'smdc:'?
//!
//! If we're in a 3DSX environment (e.g: when loaded with Luma3DS) we must load
//! the 'Self3DSX' by hand, if not we must open it from SelfNCCH.

view: romfs.View,
data_offset: u32,
file: Filesystem.File,

pub fn initSelf(fs: Filesystem, gpa: std.mem.Allocator) !RomFs {
    return if (environment.program_meta.is3dsx()) .initSelf3dsx(fs, gpa) else .initSelfBase(fs, gpa);
}

/// Initializes a RomFS from a file.
pub fn initFile(file: Filesystem.File, gpa: std.mem.Allocator) !RomFs {
    var hdr: romfs.Header = undefined;
    const hdr_read = try file.sendRead(0, @ptrCast(&hdr));

    if (hdr_read < @sizeOf(romfs.Header)) return error.NoRomFs;

    try hdr.check();

    const directories = try gpa.alloc(u32, @divExact(hdr.directory_info.meta_table_size, @sizeOf(u32)));
    errdefer gpa.free(directories);

    const files = try gpa.alloc(u32, @divExact(hdr.file_info.meta_table_size, @sizeOf(u32)));
    errdefer gpa.free(files);

    const directory_hashes = try gpa.alloc(romfs.meta.DirectoryOffset, @divExact(hdr.directory_info.hash_table_size, @sizeOf(u32)));
    errdefer gpa.free(directory_hashes);

    const file_hashes = try gpa.alloc(romfs.meta.FileOffset, @divExact(hdr.file_info.hash_table_size, @sizeOf(u32)));
    errdefer gpa.free(file_hashes);

    if (try file.sendRead(hdr.directory_info.hash_table_offset, std.mem.sliceAsBytes(directory_hashes)) != hdr.directory_info.hash_table_size) return error.InvalidRomFs;
    if (try file.sendRead(hdr.file_info.hash_table_offset, std.mem.sliceAsBytes(file_hashes)) != hdr.file_info.hash_table_size) return error.InvalidRomFs;
    if (try file.sendRead(hdr.directory_info.meta_table_offset, std.mem.sliceAsBytes(directories)) != hdr.directory_info.meta_table_size) return error.InvalidRomFs;
    if (try file.sendRead(hdr.file_info.meta_table_offset, std.mem.sliceAsBytes(files)) != hdr.file_info.meta_table_size) return error.InvalidRomFs;

    return .{
        .view = .init(.init(directories), .init(files), directory_hashes, file_hashes),
        .data_offset = hdr.file_data_offset,
        .file = file,
    };
}

pub fn deinit(fs: RomFs, gpa: std.mem.Allocator) void {
    fs.view.deinit(gpa);
    fs.file.sendClose();
}

pub fn openHorizonSubFile(fs: RomFs, file: romfs.View.File) !Filesystem.File {
    const stat = file.stat(fs.view);
    return try fs.file.sendOpenSubFile(fs.data_offset + stat.offset, stat.size);
}

pub fn readPositional(fs: RomFs, file: romfs.View.File, position: u64, buffer: []u8) !usize {
    const stat = file.stat(fs.view);
    const read_buffer = if (position + buffer.len >= stat.size) buffer[0..@intCast(stat.size - position)] else buffer;

    return fs.file.sendRead(fs.data_offset + stat.offset, read_buffer);
}

pub fn openAny(fs: RomFs, parent: romfs.View.Directory, path: [:0]const u16) !romfs.View.Entry {
    return fs.view.openAny(parent, path);
}

pub fn openFile(fs: RomFs, parent: romfs.View.Directory, path: [:0]const u16) !romfs.View.File {
    return fs.view.openFile(parent, path);
}

/// Initializes a RomFS from the base RomFS of the current NCCH.
pub fn initSelfBase(fs: Filesystem, gpa: std.mem.Allocator) !RomFs {
    return .initFile(try fs.sendOpenFileDirectly(0, .self_ncch, .empty, &.{0}, .binary, @ptrCast(&Filesystem.PathType.SelfNcch.romfs_base), .r, .{}), gpa);
}

fn initSelf3dsx(fs: Filesystem, gpa: std.mem.Allocator) !RomFs {
    const Location = enum {
        sdmc,
    };

    const program_path = pro: {
        var arg_it = environment.program_meta.argumentListIterator();
        break :pro arg_it.next() orelse return error.MissingLocation;
    };

    const first_slash = std.mem.indexOfScalar(u8, program_path, '/') orelse return error.InvalidPath;

    const location: Location, const path: [:0]const u8 = if (first_slash == 0)
        .{ .sdmc, program_path } // NOTE: Assume sdmc?
    else blk: {
        if (program_path[first_slash - 1] != ':') {
            return error.InvalidPath;
        }

        const location = program_path[0..(first_slash - 1)];

        break :blk if (std.mem.eql(u8, location, "sdmc"))
            .{ .sdmc, program_path[first_slash.. :0] }
        else
            return error.UnknownLocation;
    };

    const file: Filesystem.File = switch (location) {
        // TODO: I think I must convert to utf16 just in case?
        .sdmc => try fs.sendOpenFileDirectly(0, .sdmc, .empty, &.{}, .ascii, path[0 .. path.len + 1], .r, .{}),
    };
    defer file.sendClose();

    var hdr_3dsx: extern struct {
        hdr: @"3dsx".Header,
        exhdr: @"3dsx".ExtendedHeader,
    } = undefined;

    const hdr_3dsx_read = try file.sendRead(0, @ptrCast(&hdr_3dsx));

    if (hdr_3dsx_read < @sizeOf(@"3dsx".Header) + @sizeOf(@"3dsx".ExtendedHeader)) return error.Invalid3dsx;
    if (hdr_3dsx.hdr.header_size == @sizeOf(@"3dsx".Header)) return error.No3dsxExtendedHeader;

    const available = try file.sendGetAvailable(hdr_3dsx.exhdr.romfs_offset, std.math.maxInt(u64));
    const romfs_file = try file.sendOpenSubFile(hdr_3dsx.exhdr.romfs_offset, available);

    return .initFile(romfs_file, gpa);
}

const RomFs = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;

const @"3dsx" = zitrus.fmt.@"3dsx";
const romfs = horizon.fmt.ncch.romfs;
const Filesystem = horizon.services.Filesystem;
