//! Driving SPI devices, did you think otherwise?
//!
//! Based on GBATEK & the implementation `3ds_spi` by `@luigoalma` under `The Unlicense`:
//! - https://github.com/luigoalma/3ds_spi
//! - https://www.problemkaputt.de/gbatek-3ds-spi-devices.htm

pub const Service = enum {
    nor,
    cd2,
    cs2,
    cs3,
    def,

    pub fn name(service: Service) [:0]const u8 {
        return switch (service) {
            .nor => "SPI::NOR",
            .cd2 => "SPI::CD2",
            .cs2 => "SPI::CS2",
            .cs3 => "SPI::CS3",
            .def => "SPI::DEF",
        };
    }
};

pub const Device = enum(u8) {
    power_management,
    wifi_flash,
    dsi_tsc,
    @"3ds_tsc",
    _,
};

pub const Rate = hardware.spi.Bus.Rate;
pub const NewRate = hardware.spi.NewBus.Rate;

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openServiceMulti;
pub const openWithResult = horizon.services.Methods(@This()).openServiceMultiWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendInitDeviceWithRate(spi: Spi, device: Device, rate: Rate) !void {
    return switch ((try spi.send(.InitDeviceWithRate, .init(device, rate), .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendDeinitDevice(spi: Spi, device: Device) !void {
    return switch ((try spi.send(.DeinitDevice, device, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendSendCommandRead(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    return switch ((try spi.send(.SendCommandRead, .init(device, cmd, buffer.len), .{})).cases()) {
        .success => |r| @memcpy(buffer, r.value.slice[0..buffer.len]),
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommandWrite(spi: Spi, device: Device, cmd: []const u8, buffer: []const u8) !void {
    return switch ((try spi.send(.SendCommandWrite, .init(device, cmd, buffer), .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommand(spi: Spi, device: Device, cmd: []const u8) !void {
    return switch ((try spi.send(.SendCommand, .init(device, cmd), .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommandReadMapped(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    return switch ((try spi.send(.SendCommandReadMapped, .init(device, cmd, buffer), .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommandWriteMapped(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    return switch ((try spi.send(.SendCommandWriteMapped, .init(device, cmd, buffer), .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendEnableNewBusWithRate(spi: Spi, device: Device, enable: bool, rate: NewRate) !void {
    return switch ((try spi.send(.EnableNewBusWithRate, .init(device, enable, rate), .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendEnableNewBus2(spi: Spi, enable: bool) !void {
    return switch ((try spi.send(.EnableNewBus2, enable, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn mapFailedResult(c: horizon.result.Code) error{Unexpected}!void {
    return switch (c) {
        .spi_out_of_range, .spi_not_initialized => horizon.resultBug(c),
        else => horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    /// Cannot fail
    pub const InitDeviceWithRate = ipc.Command(Id, .init_device_with_rate, struct {
        device: Device,
        rate: Rate,

        pub fn init(dev: Device, rate: Rate) @This() {
            return .{ .device = dev, .rate = rate };
        }
    }, void);
    // Literally does nothing, but it's 100% deinit device as it's called when tearing down things
    pub const DeinitDevice = ipc.Command(Id, .deinit_device, Device, void);
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandRead = ipc.Command(Id, .send_command_read, struct {
        device: Device,
        command: ipc.Embedded(4, u8, .post),
        buffer_len: u32,

        pub fn init(dev: Device, cmd: []const u8, len: u32) @This() {
            return .{ .device = dev, .command = .embedded(cmd), .buffer_len = len };
        }
    }, ipc.Embedded(64, u8, .none));
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandWrite = ipc.Command(Id, .send_command_write, struct {
        device: Device,
        command: ipc.Embedded(4, u8, .post),
        buffer: ipc.Embedded(64, u8, .post),

        pub fn init(dev: Device, cmd: []const u8, buffer: []const u8) @This() {
            return .{ .device = dev, .command = .embedded(cmd), .buffer = .embedded(buffer) };
        }
    }, void);
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommand = ipc.Command(Id, .send_command, struct {
        device: Device,
        command: ipc.Embedded(4, u8, .post),

        pub fn init(dev: Device, cmd: []const u8) @This() {
            return .{ .device = dev, .command = .embedded(cmd) };
        }
    }, void);
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandReadMapped = ipc.Command(Id, .send_command_read_mapped, struct {
        device: Device,
        command: ipc.Embedded(4, u8, .post),
        buffer_len: u32,
        buffer: ipc.Mapped(u8, .w),

        pub fn init(dev: Device, cmd: []const u8, buffer: []u8) @This() {
            return .{ .device = dev, .command = .embedded(cmd), .buffer_len = buffer.len, .buffer = .mapped(buffer) };
        }
    }, ipc.Mapped(u8, .w));
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandWriteMapped = ipc.Command(Id, .send_command_write_mapped, struct {
        device: Device,
        command: ipc.Embedded(4, u8, .post),
        buffer_len: u32,
        buffer: ipc.Mapped(u8, .r),

        pub fn init(dev: Device, cmd: []const u8, buffer: []const u8) @This() {
            return .{ .device = dev, .command = .embedded(cmd), .buffer_len = buffer.len, .buffer = .mapped(buffer) };
        }
    }, ipc.Mapped(u8, .r));
    /// Cannot fail
    pub const EnableNewBusWithRate = ipc.Command(Id, .enable_new_bus_with_rate, struct {
        device: Device,
        enable: bool,
        rate: NewRate,

        pub fn init(dev: Device, enable: bool, rate: NewRate) @This() {
            return .{ .device = dev, .enable = enable, .rate = rate };
        }
    }, void);
    /// Cannot fail
    pub const EnableNewBus2 = ipc.Command(Id, .enable_new_bus2, bool, void);

    pub const Id = enum(u16) {
        init_device_with_rate = 0x0001,
        deinit_device,
        send_command_read,
        send_command_write,
        send_command,
        send_command_read_mapped,
        send_command_write_mapped,
        enable_new_bus_with_rate,
        enable_new_bus2,
    };
};

const Spi = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;

const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
