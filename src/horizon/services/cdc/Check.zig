//! `cdc:CHK`

pub const service = "cdc:CHK";

pub const Line = zitrus.hardware.i2s.Line;
pub const Gain = zitrus.hardware.codec.i2s.Gain;

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const ReadDsiTsc = ipc.Command(Id, .read_dsi_tsc, struct {
        pub const StaticOutput = struct { buffer: []u8 };
        page: u8,
        register: u8,
        size: u32,
    }, ipc.Static(u8, 0));
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const Read3dsTsc = ipc.Command(Id, .read_3ds_tsc, struct {
        pub const StaticOutput = struct { buffer: []u8 };
        page: u8,
        register: u8,
        size: u32,
    }, ipc.Static(u8, 0));
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const WriteDsiTsc = ipc.Command(Id, .write_dsi_tsc, struct {
        page: u8,
        register: u8,
        size: u32,
        buffer: ipc.Static(u8, 0),
    }, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const Write3dsTsc = ipc.Command(Id, .write_3ds_tsc, struct {
        page: u8,
        register: u8,
        size: u32,
        buffer: ipc.Static(u8, 0),
    }, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const ReadPowerManagement = ipc.Command(Id, .read_power_management, struct {
        index: u8,
    }, u8);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const WritePowerManagement = ipc.Command(Id, .read_power_management, struct {
        index: u8,
        value: u8,
    }, void);
    /// May return 0xc9403800 (sleeping, nothing changed)
    pub const SetI2sVolume = ipc.Command(Id, .set_i2s_volume, struct {
        line: Line,
        gain: Gain,
    }, void);

    pub const Id = enum(u16) {
        read_dsi_tsc = 0x0001,
        read_3ds_tsc,
        write_dsi_tsc,
        write_3ds_tsc,
        read_power_management,
        write_power_management,
        set_i2s_volume,
    };
};

const Check = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
