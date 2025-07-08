// TODO: fs:USER

pub const MediaType = enum(u8) {
    nand,
    sd,
    game_card,
};

pub const File = packed struct(u32) {
    session: ClientSession,

    pub const command = struct {
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
    session: ClientSession,

    pub const command = struct {
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

pub const command = struct {
    pub const Id = enum(u16) {
    };
};

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.ResultCode;
const ClientSession = horizon.ClientSession;

