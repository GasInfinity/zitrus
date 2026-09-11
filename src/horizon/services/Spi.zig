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

pub const Device = enum(u4) {
    power_management,
    wifi_flash,
    dsi_tsc,
    @"3ds_tsc",
    _,
};

pub const BusRate = hardware.spi.Bus.Rate;
pub const NewBusRate = hardware.spi.NewBus.Rate;

session: ClientSession,

pub fn open(service: Service, srv: ServiceManager) !Spi {
    return .{ .session = try srv.getService(service.name(), .wait) };
}

pub fn close(spi: Spi) void {
    spi.session.close();
}

pub fn sendInitDeviceRate(spi: Spi, device: Device, rate: BusRate) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(spi.session, command.InitDeviceRate, .{
        .device = device,
        .rate = rate,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendSendCommandRead(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    std.debug.assert(cmd.len <= 4);
    std.debug.assert(buffer.len <= 64);

    const data = tls.get();
    var req: command.SendCommandRead.Request = .{
        .device = device,
        .command = undefined,
        .command_len = 4,
        .buffer_len = buffer.len,
    };
    @memcpy(&req.command, cmd);

    data.ipc.writeRequest(command.SendCommandRead, req, .{});
    try spi.session.sendRequest();
    const code = try data.ipc.checkResponse(command.SendCommandRead);
    const response_bytes: []u8 = @ptrCast(&data.ipc.packed_command.parameters[1..]);

    if (!code.isSuccess()) return mapFailedResult(code);
    @memcpy(buffer, response_bytes[0..buffer.len]);
}

pub fn sendSendCommandWrite(spi: Spi, device: Device, cmd: []const u8, buffer: []const u8) !void {
    std.debug.assert(cmd.len <= 4);
    std.debug.assert(buffer.len <= 64);

    const data = tls.get();
    var req: command.SendCommandWrite.Request = .{
        .device = device,
        .command = undefined,
        .command_len = 4,
        .buffer = undefined,
        .buffer_len = buffer.len,
    };
    @memcpy(&req.command, cmd);
    @memcpy(&req.buffer, buffer);

    return switch ((try data.ipc.sendRequest(spi.session, command.SendCommandWrite, req, .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommand(spi: Spi, device: Device, cmd: []const u8) !void {
    std.debug.assert(cmd.len <= 4);

    const data = tls.get();
    var req: command.SendCommandWrite.Request = .{
        .device = device,
        .command = undefined,
        .command_len = 4,
    };
    @memcpy(&req.command, cmd);

    return switch ((try data.ipc.sendRequest(spi.session, command.SendCommand, req, .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommandReadMapped(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    std.debug.assert(cmd.len <= 4);
    std.debug.assert(buffer.len <= 64);

    const data = tls.get();
    var req: command.SendCommandReadMapped.Request = .{
        .device = device,
        .command = undefined,
        .command_len = 4,
        .buffer_len = buffer.len,
        .buffer = .mapped(buffer),
    };
    @memcpy(&req.command, cmd);

    return switch ((try data.ipc.sendRequest(spi.session, command.SendCommandReadMapped, req, .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendSendCommandWriteMapped(spi: Spi, device: Device, cmd: []const u8, buffer: []u8) !void {
    std.debug.assert(cmd.len <= 4);
    std.debug.assert(buffer.len <= 64);

    const data = tls.get();
    var req: command.SendCommandWriteMapped.Request = .{
        .device = device,
        .command = undefined,
        .command_len = 4,
        .buffer_len = buffer.len,
        .buffer = .mapped(buffer),
    };
    @memcpy(&req.command, cmd);

    return switch ((try data.ipc.sendRequest(spi.session, command.SendCommandWriteMapped, req, .{})).cases()) {
        .success => {},
        .failure => |c| mapFailedResult(c),
    };
}

pub fn sendEnableNewBusRate(spi: Spi, device: Device, enable: bool, rate: NewBusRate) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(spi.session, command.EnableNewBusWithRate, .{
        .device = device,
        .enable = enable,
        .rate = rate,
    }, .{})).cases()) {
        .success => {},
        // Literally cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendEnableNewBus2(spi: Spi, enable: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(spi.session, command.EnableNewBus2, .{ .enable = enable }, .{})).cases()) {
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
    pub const InitDeviceRate = ipc.Command(Id, .init_device_rate, struct {
        device: Device,
        rate: BusRate,
    }, struct {});
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandRead = ipc.Command(Id, .send_command_read, struct {
        device: Device,
        command: [4]u8,
        command_len: u32,
        buffer_len: u32,
    }, struct {
        data: [64]u8,
    });
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandWrite = ipc.Command(Id, .send_command_write, struct {
        device: Device,
        command: [4]u8,
        command_len: u32,
        buffer: [64]u8,
        buffer_len: u32,
    }, struct {});
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommand = ipc.Command(Id, .send_command, struct {
        device: Device,
        command: [4]u8,
        command_len: u32,
    }, struct {});
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandReadMapped = ipc.Command(Id, .send_command_read_mapped, struct {
        device: Device,
        command: [4]u8,
        command_len: u32,
        buffer_len: u32,
        buffer: ipc.Mapped(.w),
    }, struct {
        buffer: ipc.Mapped(.w),
    });
    /// May fail with 0xc8a03ff8 (spi_not_initialized) or 0xe0e03ffd (spi_out_of_range)
    pub const SendCommandWriteMapped = ipc.Command(Id, .send_command_write_mapped, struct {
        device: Device,
        command: [4]u8,
        command_len: u32,
        buffer_len: u32,
        buffer: ipc.Mapped(.r),
    }, struct {
        buffer: ipc.Mapped(.r),
    });
    /// Cannot fail
    pub const EnableNewBusWithRate = ipc.Command(Id, .enable_new_bus_with_rate, struct {
        device: Device,
        enable: bool,
        rate: NewBusRate,
    }, struct {});
    /// Cannot fail
    pub const EnableNewBus2 = ipc.Command(Id, .enable_new_bus2, struct {
        enable: bool,
    }, struct {});

    pub const Id = enum(u16) {
        init_device_rate = 0x0001,
        send_command_read = 0x0003,
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
