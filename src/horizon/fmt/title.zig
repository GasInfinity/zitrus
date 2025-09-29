//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Titles

pub const Platform = enum(u16) { @"3ds" = 4 };

pub const Category = packed struct(u16) {
    pub const normal: Category = .{};
    pub const contents: Category = .{ .demo = true, .download_play_child = true };
    pub const patch: Category = .{ .demo = true, .add_on_contents = true };

    download_play_child: bool = false,
    demo: bool = false,
    add_on_contents: bool = false,
    cannot_execute: bool = false,
    system: bool = false,
    requires_batch_update: bool = false,
    dont_require_user_approval: bool = false,
    dont_require_right_for_mount: bool = false,
    _unused0: u7 = 0,
    twl: bool = false,
};

pub const Id = packed struct(u64) {
    variation: u8,
    unique: u24,
    category: Category,
    platform: Platform,
};

pub const Version = packed struct(u16) {
    build: u4,
    minor: u6,
    major: u6,
};
