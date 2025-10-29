pub const magic = "CRO0";

pub const Location = packed struct(u32) {
    pub const none: Location = .{ .index = .none, .offset = 0xFFFFFFF };
    pub const Segment = enum(u4) { text, rodata, data, bss, none = 0xF, _ };

    index: Segment,
    offset: u28,
};

pub const Blob = extern struct {
    offset: u32,
    size: u32,
};

pub const Header = extern struct {
    /// SHA-256 hashes of:
    /// - [0x80, CodeOffset]
    /// - [CodeOffset, ModuleNameOffset]
    /// - [ModuleNameOffset, DataOffset]
    /// - [DataOffset, End]
    hashes: [4][0x20]u8,
    magic: [magic.len]u8 = magic.*,
    name_offset: u32,
    next: u32 = 0,
    previous: u32 = 0,
    file_size: u32,
    bss_size: u32,
    fixed_size: u32,
    _unknown0: u32,
    control_tag: Location,
    on_load: Location,
    on_exit: Location,
    on_unresolved: Location,
    text: Blob,
    data: Blob,
    module_name: Blob,
    segment_table: Blob,
    exported_named_symbol: Blob,
    exported_indexed_symbol: Blob,
    exported_strings: Blob,
    exported_name_tree: Blob,
    exported_module_table: Blob,
    exported_patch_table: Blob,
    imported_named_symbol: Blob,
    imported_indexed_symbol: Blob,
    imported_anonymous_symbol: Blob,
    imported_strings: Blob,
    static_anonymous_symbol: Blob,
    internal_patch_table: Blob,
    static_anonymous_patch: Blob,
};
