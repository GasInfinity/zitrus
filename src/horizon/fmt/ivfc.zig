pub const Level = extern struct {
    logical_offset: u64 align(@alignOf(u32)),
    hash_data_size: u64 align(@alignOf(u32)),
    /// In Log2
    block_size: u32,
    _padding0: u32,
};

const std = @import("std");
