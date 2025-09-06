const service_names = [_][]const u8{ "fs:LDR", "fs:USER" };

pub const CardType = enum(u8) {
    ctr,
    twl,
};

pub const MediaType = enum(u8) {
    nand,
    sd,
    game_card,
};

pub const PathType = enum(u32) {
    @"error" = -1,
    invalid = 0,
    empty,
    binary,
    ascii,
    utf16,
};

pub const OpenFlags = packed struct(u32) {
    read: bool,
    write: bool,
    create: bool,
    _unused0: u29 = 0,
};

pub const ArchiveId = enum(u32) {
    self_ncch = 0x00000003,
    save_data = 0x00000004,
    ext_save_data = 0x00000006,
    shared_ext_save_data,
    system_save_data,
    sdmc,
    sdmc_write_only,
    boss_ext_save_data = 0x12345678,
    card_spi_fs,
    nand_rw = 0x1234567D,
    nand_ro,

    // TODO: finish this with fs accesible archives
};

pub const Archive = enum(u64) { _ };

pub const ArchiveResource = extern struct {
    sector_byte_size: usize,
    cluster_byte_size: usize,
    cluster_partition_capcity: usize,
    available_free_cluster_space: usize,
};

pub const WriteOptions = extern struct {
    flush: bool,
    update_timestamp: bool,
    _reserved0: [2]u8 = @splat(0),
};

pub const Attributes = extern struct {
    directory: bool,
    hidden: bool,
    archive: bool,
    read_only: bool,
};

pub const ControlArchiveAction = enum(u32) {
    commit_save_data,
    retrieve_last_modified_timestamp,
    unknown_calls_fspxi_0x0056,
};

// TODO: Move this to FilesystemPxi
pub const ProductInfo = extern struct {
    product_code: [16]u8,
    company_code: [2]u8,
    remaster_version: u16,
};

pub const ProgramInfo = extern struct {
    title_id: u64,
    media_type: MediaType,
    _padding0: [7]u8,
};

pub const File = packed struct(u32) {
    session: ClientSession,

    pub fn sendOpenSubFile(file: File, offset: u64, size: u64) !File {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.OpenSubFile, .{ .offset = offset, .size = size }, .{})) {
            .success => |s| s.value.response.file,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendRead(file: File, offset: u64, buffer: []u8) !usize {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.Read, .{ .offset = offset, .size = buffer.len, .buffer = .init(buffer) }, .{})) {
            .success => |s| s.value.response.actual_read,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendWrite(file: File, offset: u64, buffer: []const u8, options: WriteOptions) !usize {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.Write, .{ .offset = offset, .size = buffer.len, .options = options, .buffer = .init(buffer) }, .{})) {
            .success => |s| s.value.response.actual_written,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendGetSize(file: File) !u64 {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.GetSize, .{}, .{})) {
            .success => |s| s.value.response.size,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendSetSize(file: File, size: u64) !void {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.SetSize, .{ .size = size }, .{})) {
            .success => {},
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendGetAttributes(file: File) !Attributes {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.GetAttributes, .{}, .{})) {
            .success => |s| s.value.response.attributes,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendSetAttributes(file: File, attributes: Attributes) !void {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.SetAttributes, .{ .attributes = attributes }, .{})) {
            .success => {},
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn close(file: *File) void {
        const data = tls.getThreadLocalStorage();
        switch (data.ipc.sendRequest(file.session, File.command.Close, .{}, .{}) catch unreachable) {
            .success => {},
            .failure => unreachable,
        }
        _ = horizon.closeHandle(file.session.sync.obj);
        file.* = undefined;
    }

    pub fn sendFlush(file: File) !void {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.Flush, .{}, .{})) {
            .success => {},
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendGetPriority(file: File) !u32 {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.GetPriority, .{}, .{})) {
            .success => |s| s.value.response.priority,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendSetPriority(file: File, priority: u32) !void {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.SetPriority, .{ .priority = priority }, .{})) {
            .success => {},
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendOpenLinkFile(file: File) !File {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.OpenLinkFile, .{}, .{})) {
            .success => |s| s.value.response.clone,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendGetAvailable(file: File, offset: u64, size: u64) !u64 {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(file.session, File.command.GetAvailable, .{ .offset = offset, .size = size }, .{})) {
            .success => |s| s.value.response.available,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub const command = struct {
        pub const OpenSubFile = ipc.Command(Id, .open_sub_file, struct { offset: u64, size: u64 }, struct { file: File });
        pub const Read = ipc.Command(Id, .read, struct { offset: u64, size: usize, buffer: ipc.MappedSlice(.write) }, struct { actual_read: usize });
        pub const Write = ipc.Command(Id, .write, struct { offset: u64, size: usize, options: WriteOptions, buffer: ipc.MappedSlice(.read) }, struct { actual_written: usize });
        pub const GetSize = ipc.Command(Id, .get_size, struct {}, struct { size: u64 });
        pub const SetSize = ipc.Command(Id, .set_size, struct { size: u64 }, struct {});
        pub const GetAttributes = ipc.Command(Id, .get_attributes, struct {}, struct { attributes: Attributes });
        pub const SetAttributes = ipc.Command(Id, .set_attributes, struct { attributes: Attributes }, struct {});
        pub const Close = ipc.Command(Id, .close, struct {}, struct {});
        pub const Flush = ipc.Command(Id, .close, struct {}, struct {});
        pub const SetPriority = ipc.Command(Id, .set_priority, struct { priority: u32 }, struct {});
        pub const GetPriority = ipc.Command(Id, .get_priority, struct {}, struct { priority: u32 });
        pub const OpenLinkFile = ipc.Command(Id, .open_link_file, struct {}, struct { clone: File });
        pub const GetAvailable = ipc.Command(Id, .get_available, struct { offset: u64, size: u64 }, struct { available: u64 });

        pub const Id = enum(u16) {
            dummy1 = 0x0001,
            control = 0x0401,
            open_sub_file = 0x0801,
            read,
            write,
            get_size,
            set_size,
            get_attributes,
            set_attributes,
            close,
            flush,
            set_priority,
            get_priority,
            open_link_file,
            get_available,
        };
    };
};

pub const Directory = packed struct(u32) {
    pub const Entry = extern struct {
        utf16_name: [262]u16,
        short_name: [10]u8,
        short_extension: [4]u8,
        _unused0: u8 = 1,
        _reserved0: u8 = 0,
        attributes: Attributes,
        size: u64,
    };

    session: ClientSession,

    pub fn sendRead(dir: Directory, entries: []Entry) !usize {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(dir.session, Directory.command.Read, .{ .count = entries.len, .buffer = .init(std.mem.asBytes(entries)) }, .{})) {
            .success => |s| s.value.response.actual_entries,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn close(dir: *Directory) void {
        const data = tls.getThreadLocalStorage();
        switch (data.ipc.sendRequest(dir.session, Directory.command.Close, .{}, .{}) catch unreachable) {
            .success => {},
            .failure => unreachable,
        }
        _ = horizon.closeHandle(dir.session.sync.obj);
        dir.* = undefined;
    }

    pub fn sendGetPriority(dir: Directory) !u32 {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(dir.session, Directory.command.GetPriority, .{}, .{})) {
            .success => |s| s.value.response.priority,
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub fn sendSetPriority(dir: Directory, priority: u32) !void {
        const data = tls.getThreadLocalStorage();
        return switch (try data.ipc.sendRequest(dir.session, Directory.command.SetPriority, .{ .priority = priority }, .{})) {
            .success => {},
            .failure => |code| horizon.unexpectedResult(code),
        };
    }

    pub const command = struct {
        pub const Read = ipc.Command(Id, .read, struct { count: usize, entries_bytes: ipc.MappedSlice(.write) }, struct { actual_entries: usize });
        pub const Close = ipc.Command(Id, .close, struct {}, struct {});
        pub const SetPriority = ipc.Command(Id, .set_priority, struct { priority: u32 }, struct {});
        pub const GetPriority = ipc.Command(Id, .get_priority, struct {}, struct { priority: u32 });

        pub const Id = enum(u16) {
            dummy1 = 0x0001,
            control = 0x0401,
            read = 0x0801,
            close,
            set_priority,
            get_priority,
        };
    };
};

session: ClientSession,

pub fn open(srv: ServiceManager) !Filesystem {
    var last_error: anyerror = undefined;
    const fs_session = used: for (service_names) |service_name| {
        const fs_session = srv.getService(service_name, .wait) catch |err| {
            last_error = err;
            continue;
        };

        break :used fs_session;
    } else return last_error;

    return .{ .session = fs_session };
}

pub fn close(fs: Filesystem) void {
    fs.session.close();
}

pub fn sendInitialize(fs: Filesystem) void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.Initialize, .{ .process_id = .{} }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendOpenFile(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8, flags: OpenFlags, attributes: Attributes) !File {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.OpenFile, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .flags = flags,
        .attributes = attributes,
        .path = .init(path),
    }, .{})) {
        .success => |s| s.value.response.file,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendOpenFileDirectly(fs: Filesystem, transaction: usize, archive_id: ArchiveId, archive_path_type: PathType, archive_path: []const u8, file_path_type: PathType, file_path: []const u8, flags: OpenFlags, attributes: Attributes) !File {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.OpenFileDirectly, .{
        .transaction = transaction,
        .archive_id = archive_id,
        .archive_path_type = archive_path_type,
        .archive_path_size = archive_path.len,
        .file_path_type = file_path_type,
        .file_path_size = file_path.len,
        .flags = flags,
        .attributes = attributes,
        .archive_path = .init(archive_path),
        .file_path = .init(file_path),
    }, .{})) {
        .success => |s| s.value.response.file,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendDeleteFile(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.DeleteFile, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .path = .init(path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRenameFile(fs: Filesystem, transaction: usize, src_archive: Archive, dst_archive: Archive, src_path_type: PathType, src_path: []const u8, dst_path_type: PathType, dst_path: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.RenameFile, .{
        .transaction = transaction,
        .source_archive = src_archive,
        .source_path_type = src_path_type,
        .soruce_path_size = src_path.len,
        .destination_archive = dst_archive,
        .destination_path_type = dst_path_type,
        .destination_path_size = dst_path.len,
        .source_path = .init(src_path),
        .destination_path = .init(dst_path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendDeleteDirectory(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.DeleteDirectory, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .path = .init(path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendDeleteDirectoryRecursively(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.DeleteDirectoryRecursively, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .path = .init(path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendCreateFile(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8, attributes: Attributes, size: u64) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.CreateFile, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .attributes = attributes,
        .file_size = size,
        .path = .init(path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendCreateDirectory(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8, attributes: Attributes) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.CreateDirectory, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .attributes = attributes,
        .path = .init(path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRenameDirectory(fs: Filesystem, transaction: usize, src_archive: Archive, dst_archive: Archive, src_path_type: PathType, src_path: []const u8, dst_path_type: PathType, dst_path: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.RenameDirectory, .{
        .transaction = transaction,
        .source_archive = src_archive,
        .source_path_type = src_path_type,
        .soruce_path_size = src_path.len,
        .destination_archive = dst_archive,
        .destination_path_type = dst_path_type,
        .destination_path_size = dst_path.len,
        .source_path = .init(src_path),
        .destination_path = .init(dst_path),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendOpenDirectory(fs: Filesystem, transaction: usize, archive: Archive, path_type: PathType, path: []const u8) !Directory {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.OpenDirectory, .{
        .transaction = transaction,
        .archive = archive,
        .path_type = path_type,
        .path_size = path.len,
        .path = .init(path),
    }, .{})) {
        .success => |s| s.value.response.directory,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendOpenArchive(fs: Filesystem, transaction: usize, archive_id: ArchiveId, path_type: PathType, path: []const u8) !Archive {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.OpenArchive, .{
        .transaction = transaction,
        .archive_id = archive_id,
        .path_type = path_type,
        .path_size = path.len,
        .path = .init(path),
    }, .{})) {
        .success => |s| s.value.response.archive,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendControlArchive(fs: Filesystem, transaction: usize, archive: Archive, action: ControlArchiveAction, input: []const u8, output: []u8) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.ControlArchive, .{
        .transaction = transaction,
        .archive = archive,
        .action = action,
        .input_size = input.len,
        .output_size = output.len,
        .input = .init(input),
        .output = .init(output),
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendCloseArchive(fs: Filesystem, transaction: usize, archive: Archive) !void {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(fs.session, command.CloseArchive, .{
        .transaction = transaction,
        .archive = archive,
    }, .{})) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const Initialize = ipc.Command(Id, .initialize, struct { process_id: ipc.ReplaceByProcessId }, struct {});
    pub const OpenFile = ipc.Command(Id, .open_file, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        flags: OpenFlags,
        attributes: Attributes,
        path: ipc.StaticSlice(0),
    }, struct { file: ipc.MoveHandle(File) });
    pub const OpenFileDirectly = ipc.Command(Id, .open_file_directly, struct {
        transaction: usize,
        archive_id: ArchiveId,
        archive_path_type: PathType,
        archive_path_size: usize,
        file_path_type: PathType,
        file_path_size: usize,
        flags: OpenFlags,
        attributes: Attributes,
        archive_path: ipc.StaticSlice(2),
        file_path: ipc.StaticSlice(0),
    }, struct { file: ipc.MoveHandle(File) });
    pub const DeleteFile = ipc.Command(Id, .delete_file, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        path: ipc.StaticSlice(0),
    }, struct {});
    pub const RenameFile = ipc.Command(Id, .rename_file, struct {
        transaction: usize,
        source_archive: Archive,
        source_path_type: PathType,
        source_path_size: usize,
        destination_archive: Archive,
        destination_path_type: PathType,
        destination_path_size: usize,
        source_path: ipc.StaticSlice(1),
        destination_path: ipc.StaticSlice(2),
    }, struct {});
    pub const DeleteDirectory = ipc.Command(Id, .delete_directory, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        path: ipc.StaticSlice(0),
    }, struct {});
    pub const DeleteDirectoryRecursively = ipc.Command(Id, .delete_directory_recursively, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        path: ipc.StaticSlice(0),
    }, struct {});
    pub const CreateFile = ipc.Command(Id, .create_file, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        attributes: Attributes,
        file_size: u64,
        path: ipc.StaticSlice(0),
    }, struct {});
    pub const CreateDirectory = ipc.Command(Id, .create_directory, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        attributes: Attributes,
        path: ipc.StaticSlice(0),
    }, struct {});
    pub const RenameDirectory = ipc.Command(Id, .rename_directory, struct {
        transaction: usize,
        source_archive: Archive,
        source_path_type: PathType,
        source_path_size: usize,
        destination_archive: Archive,
        destination_path_type: PathType,
        destination_path_size: usize,
        source_path: ipc.StaticSlice(1),
        destination_path: ipc.StaticSlice(2),
    }, struct {});
    pub const OpenDirectory = ipc.Command(Id, .open_directory, struct {
        transaction: usize,
        archive: Archive,
        path_type: PathType,
        path_size: usize,
        path: ipc.StaticSlice(0),
    }, struct { directory: ipc.MoveHandle(Directory) });
    pub const OpenArchive = ipc.Command(Id, .open_archive, struct {
        transaction: usize,
        archive_id: ArchiveId,
        path_type: PathType,
        path_size: usize,
        path: ipc.StaticSlice(0),
    }, struct { archive: Archive });
    pub const ControlArchive = ipc.Command(Id, .control_archive, struct {
        transaction: usize,
        archive: Archive,
        action: ControlArchiveAction,
        input_size: usize,
        output_size: usize,
        input: ipc.MappedSlice(.read),
        output: ipc.MappedSlice(.write),
    }, struct {});
    pub const CloseArchive = ipc.Command(Id, .close_archive, struct {
        transaction: usize,
        archive: Archive,
    }, struct {});

    // obsolete Obsoleted_2_0_FormatThisUserSaveData
    // obsolete Obsoleted_3_0_CreateSystemSaveData
    // obsolete Obsoleted_3_0_DeleteSystemSaveData

    pub const GetFreeBytes = ipc.Command(Id, .get_free_bytes, struct { archive: Archive }, struct { free_bytes: u64 });
    pub const GetCardType = ipc.Command(Id, .get_card_type, struct {}, struct { card_type: CardType });
    pub const GetSmdcArchiveResource = ipc.Command(Id, .get_smdc_archive_resource, struct {}, struct { archive_resource: ArchiveResource });
    pub const GetNandArchiveResource = ipc.Command(Id, .get_nand_archive_resource, struct {}, struct { archive_resource: ArchiveResource });
    pub const GetSmdcFatFsError = ipc.Command(Id, .get_smdc_fatfs_error, struct {}, struct { fatfs_error: u32 });
    pub const IsSmdcDetected = ipc.Command(Id, .is_smdc_detected, struct {}, struct { detected: bool });
    pub const IsSmdcWritable = ipc.Command(Id, .is_smdc_writable, struct {}, struct { writable: bool });
    pub const GetSmdcCid = ipc.Command(Id, .get_smdc_cid, struct { buffer_size: usize, buffer: ipc.MappedSlice(.write) }, struct {});
    pub const GetNandCid = ipc.Command(Id, .get_smdc_cid, struct { buffer_size: usize, buffer: ipc.MappedSlice(.write) }, struct {});
    pub const GetSmdcSpeedInfo = ipc.Command(Id, .get_smdc_speed_info, struct {}, struct { speed_info: u32 });
    pub const GetNandSpeedInfo = ipc.Command(Id, .get_nand_speed_info, struct {}, struct { speed_info: u32 });
    pub const GetSmdcLog = ipc.Command(Id, .get_smdc_log, struct { buffer_size: usize, buffer: ipc.MappedSlice(.write) }, struct {});
    pub const GetNandLog = ipc.Command(Id, .get_nand_log, struct { buffer_size: usize, buffer: ipc.MappedSlice(.write) }, struct {});
    pub const ClearSmdcLog = ipc.Command(Id, .clear_smdc_log, struct {}, struct {});
    pub const ClearNandLog = ipc.Command(Id, .clear_smdc_log, struct {}, struct {});
    pub const CardSlotIsInserted = ipc.Command(Id, .card_slot_is_inserted, struct {}, struct { inserted: bool });
    pub const CardSlotPowerOn = ipc.Command(Id, .card_slot_power_on, struct {}, struct { status: u8 });
    pub const CardSlotPowerOff = ipc.Command(Id, .card_slot_power_off, struct {}, struct { status: u8 });
    pub const CardSlotGetCardIfPowerStatus = ipc.Command(Id, .card_slot_get_card_if_power_status, struct {}, struct { powered: bool });

    // TODO: CardNor commands

    pub const GetProductInfo = ipc.Command(Id, .get_product_info, struct { process_id: u32 }, struct { product_info: ProductInfo });
    pub const GetProgramLaunchInfo = ipc.Command(Id, .get_program_launch_info, struct { process_id: u32 }, struct { program_info: ProgramInfo });

    // obsolete Obsoleted_3_0_CreateExtSaveData
    // obsolete Obsoleted_3_0_CreateSharedExtSaveData
    // obsolete Obsoleted_3_0_ReadExtSaveDataIcon
    // obsolete Obsoleted_3_0_EnumerateExtSaveData
    // obsolete Obsoleted_3_0_EnumerateSharedExtSaveData
    // obsolete Obsoleted_3_0_DeleteExtSaveData
    // obsolete Obsoleted_3_0_DeleteSharedExtSaveData

    // TODO: remaining commands

    pub const Id = enum(u16) {
        dummy1 = 0x0001,
        initialize = 0x0401,
        open_file = 0x0801,
        open_file_directly,
        delete_file,
        rename_file,
        delete_directory,
        delete_directory_recursively,
        create_file,
        create_directory,
        rename_directory,
        open_directory,
        open_archive,
        control_archive,
        close_archive,
        obsoleted_2_0_format_this_user_save_data,
        obsoleted_3_0_create_system_save_data,
        obsoleted_3_0_delete_system_save_data,
        get_free_bytes,
        get_card_type,
        get_sdmc_archive_resource,
        get_nand_archive_resource,
        get_sdmc_fatfs_error,
        is_sdmc_detected,
        is_sdmc_writable,
        get_sdmc_cid,
        get_nand_cid,
        get_sdmc_speed_info,
        get_nand_speed_info,
        get_sdmc_log,
        get_nand_log,
        clear_sdmc_log,
        clear_nand_log,
        card_slot_is_inserted,
        card_slot_power_on,
        card_slot_power_off,
        card_slot_get_card_if_power_status,
        card_nor_direct_command,
        card_nor_direct_command_with_address,
        card_nor_direct_read,
        card_nor_direct_read_with_address,
        card_nor_direct_write,
        card_nor_direct_write_with_address,
        card_nor_direct_read_4xio,
        card_nor_direct_cpu_write_without_verify,
        card_nor_direct_sector_erase_without_verify,
        get_product_info,
        get_program_launch_info,
        obsoleted_3_0_create_ext_save_data,
        obsoleted_3_0_create_shared_ext_save_data,
        obsoleted_3_0_read_ext_save_data_icon,
        obsoleted_3_0_enumerate_ext_save_data,
        obsoleted_3_0_enumerate_shared_ext_save_data,
        obsoleted_3_0_delete_ext_save_data,
        obsoleted_3_0_delete_shared_ext_save_data,
        set_card_spi_baud_rate,
        set_card_spi_bus_mode,
        send_initialize_info_to9,
        get_special_content_index,
        get_legacy_rom_header,
        get_legacy_banner_data,
        check_authority_to_access_ext_save_data,
        query_total_quota_size,
        obsoleted_3_0_get_ext_data_block_size,
        abnegate_access_right,
        delete_sdmc_root,
        delete_all_ext_save_data_on_nand,
        initialize_ctr_file_system,
        create_seed,
        get_format_info,
        get_legacy_rom_header2,
        obsoleted_2_0_format_ctr_card_user_save_data,
        get_sdmc_ctr_root_path,
        get_archive_resource,
        export_integrity_verification_seed,
        import_integrity_verification_seed,
        format_save_data,
        get_legacy_sub_banner_data,
        update_sha256_context,
        read_special_file,
        get_special_file_size,
        create_ext_save_data = 0x0851,
        delete_ext_save_data,
        read_ext_save_data_icon,
        get_ext_data_block_size,
        enumerate_ext_save_data,
        create_system_save_data,
        delete_system_save_data,
        start_device_move_as_source,
        start_device_move_as_destination,
        set_archive_priority,
        get_archive_priority,
        set_ctr_card_latency_parameter,
        set_fs_compatibility_info,
        reset_card_compatibility_parameter,
        switch_cleanup_invalid_save_data,
        enumerate_system_save_data,
        initialize_with_sdk_version,
        set_priority,
        get_priority,
        obsoleted_4_0_get_nand_info,
        set_save_data_secure_value = 0x0865,
        get_save_data_secure_value,
        control_secure_save,
        get_media_type,
        obsoleted_4_0_get_nand_erase_count,
        read_nand_report,
        set_other_save_data_secure_value,
        get_other_save_data_secure_value,
        begin_save_data_move,
        set_this_save_data_secure_value,
        get_this_save_data_secure_value,
        check_archive,
        transfer_save_data_cmac,
        register_title_content_overlay,
        unregister_title_content_overlay,
        unregister_all_title_content_overlays,
        set_save_archive_secure_value,
        get_save_archive_secure_value,
        register_special_title_content,
        unregister_special_title_content,
        get_legacy_banner_data_fspxi,
        add_seed,
        get_seed,
        delete_seed,
        get_num_seeds,
        list_seeds,
        title_content_has_seed,
        add_title_tag,
        get_title_tag,
        delete_title_tag,
        get_num_title_tags,
        list_title_tags,
        check_title_seed,
        check_updated_dat,
    };
};

const Filesystem = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.result.Code;
const ClientSession = horizon.ClientSession;

const ServiceManager = zitrus.horizon.ServiceManager;
