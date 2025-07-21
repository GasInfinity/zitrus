/// Header of an ExeFS files as defined in https://www.3dbrew.org/wiki/ExeFS
pub const Header = extern struct {
    pub const max_files = 10;

    pub const FileHeader = extern struct {
        name: [8]u8,
        /// Offset in bytes
        offset: u32,
        /// Size in bytes
        size: u32,
    };

    files: [max_files]FileHeader,
    _reserved0: [0x20]u8 = @splat(0),
    /// SHA256 hashes over the entire files, stored in reverse order.
    file_hashes: [max_files][0x20]u8,
};

pub const File = struct { name: []const u8, data: []const u8 };
pub const CreationError = error{ InvalidFilename, InvalidFileSize, OutOfFiles, OutOfFileMemory };

// TODO: Easy method to create the ExeFS data
