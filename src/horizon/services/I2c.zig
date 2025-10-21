pub const Service = enum(u2) {
    mcu,
    camera,
    lcd,
    debug,
    hid,
    ir,
    eeprom,
    nfc,
    qtm,

    pub fn name(service: Service) [:0]const u8 {
        return switch (service) {
            .mcu => "i2c::MCU",
            .camera => "i2c::CAM",
            .lcd => "i2c::LCD",
            .debug => "i2c::DEB",
            .hid => "i2c::HID",
            .ir => "i2c::IR",
            .eeprom => "i2c::EEP",
            .nfc => "i2c::NFC",
            .qtm => "i2c::QTM",
        };
    }
};

session: ClientSession,

pub fn open(service: Service, srv: ServiceManager) !I2c {
    return .{ .session = try srv.getService(service.name(), .wait) };
}

pub fn close(i2c: I2c) void {
    i2c.session.close();
}

pub const command = struct {
    pub const Id = enum(u16) {
        set_register_bits8 = 0x0001,
        enable_register_bits8,
        disable_register_bits8,
        multi_set_register_bits16,
        write_register8,
        write_command8,
        write_register16,
        multi_write_register16,
        read_register8,
        read_register16,
        write_register_buffer8,
        write_register_buffer16,
        read_register_buffer8,
        write_register_buffer,
        read_register_buffer,
        read_eeprom,
        write_register_buffer2,
        read_register_buffer2,
        read_device_raw8,
        write_device_raw,
        read_device_raw,
    };
};

const I2c = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
