//! Access I2C hardware
//!
//! Based on 3dbrew & the implementation `3ds_i2c` by `@ZeroSkill1` under `The Unlicense`:
//!  - https://github.com/ZeroSkill1/3ds_i2c
//!  - https://www.3dbrew.org/wiki/I2C_Services

pub const Service = enum {
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

pub const Device = enum(u8) {
    _,
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openServiceMulti;
pub const openWithResult = horizon.services.Methods(@This()).openServiceMultiWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const WriteRegisterMasked8 = ipc.Command(Id, .write_register_masked8, struct {
        device: Device,
        register: u8,
        value: u8,
        mask: u8,
    }, struct {});
    pub const SetRegister8 = ipc.Command(Id, .set_register8, struct {
        device: Device,
        register: u8,
        mask: u8,
    }, struct {});
    pub const ClearRegister8 = ipc.Command(Id, .clear_register8, struct {
        device: Device,
        register: u8,
        mask: u8,
    }, struct {});
    pub const MultiWriteRegisterMasked16 = ipc.Command(Id, .multi_write_register_masked16, struct {
        register: u16,
        value: u16,
        mask: u16,
        devices_len: u32,
        devices: ipc.Static(u8, 0),
    }, struct {});
    pub const WriteRegister8 = ipc.Command(Id, .write_register8, struct {
        device: Device,
        register: u8,
        value: u8,
    }, struct {});
    pub const WriteDevice8 = ipc.Command(Id, .write_device8, struct {
        device: Device,
        value: u8,
    }, struct {});
    pub const WriteRegister16 = ipc.Command(Id, .write_register16, struct {
        device: Device,
        register: u16,
        value: u16,
    }, struct {});
    pub const MultiWriteRegister16 = ipc.Command(Id, .multi_write_register16, struct {
        register: u16,
        value: u16,
        devices_len: u32,
        devices: ipc.Static(u8, 0),
    }, struct {});
    pub const ReadRegister8 = ipc.Command(Id, .read_register8, struct {
        device: Device,
        register: u8,
    }, struct {
        value: u8,
    });
    pub const ReadRegister16 = ipc.Command(Id, .read_register16, struct {
        device: Device,
        register: u16,
    }, struct {
        value: u16,
    });
    pub const WriteRegisters8 = ipc.Command(Id, .write_registers8, struct {
        device: Device,
        register: u8,
        values_len: u32,
        values: ipc.Static(u8, 1),
    }, struct {});
    pub const WriteRegisters16 = ipc.Command(Id, .write_registers16, struct {
        device: Device,
        register: u16,
        values_len: u32,
        values: ipc.Static(u8, 1),
    }, struct {});
    pub const ReadRegisters8 = ipc.Command(Id, .read_registers8, struct {
        pub const StaticOutput = struct { values: []u8 };
        device: Device,
        register: u8,
        values_len: u32,
    }, struct {
        values: ipc.Static(u8, 0),
    });
    // pub const WriteRegisters8_2= ipc.Command(Id, .write_registers8, struct {}, struct {});
    pub const ReadRegisters8Delayed = ipc.Command(Id, .read_registers8_delayed, struct {
        pub const StaticOutput = struct { values: []u8 };

        device: Device,
        register: u8,
        values_len: u32,
    }, struct {
        values: ipc.Static(u8, 0),
    });
    pub const ReadRegisters16 = ipc.Command(Id, .read_registers16, struct {
        pub const StaticOutput = struct { values: []u16 };

        device: Device,
        register: u8,
        values_len: u32,
    }, struct {
        values: ipc.Static(u8, 0),
    });
    pub const WriteRegistersMapped = ipc.Command(Id, .write_registers_mapped, struct {
        device: Device,
        register: u8,
        values_len: u32,
        values: ipc.Mapped(u8, .r),
    }, struct {
        values: ipc.Mapped(u8, .r),
    });
    pub const ReadRegistersMapped = ipc.Command(Id, .read_registers_mapped, struct {
        device: Device,
        register: u8,
        values_len: u32,
        values: ipc.Mapped(u8, .w),
    }, struct {
        values: ipc.Mapped(u8, .w),
    });
    pub const ReadDevice8 = ipc.Command(Id, .read_device8, struct {
        device: Device,
    }, struct {
        value: u8,
    });
    pub const MultiWriteDevice8 = ipc.Command(Id, .multi_write_device8, struct {
        device: Device,
        values_len: u32,
        values: ipc.Static(u8, 1),
    }, struct {});
    pub const MultiReadDevice8 = ipc.Command(Id, .multi_read_device8, struct {
        pub const StaticOutput = struct { values: []u8 };
        device: Device,
        values_len: u32,
    }, struct { values: ipc.Static(u8, 0) });

    pub const Id = enum(u16) {
        write_register_masked8 = 0x0001,
        set_register8,
        clear_register8,
        multi_write_register_masked16,
        write_register8,
        write_device8,
        write_register16,
        multi_write_register16,
        read_register8,
        read_register16,
        write_registers8,
        write_registers16,
        read_registers8,
        write_registers8_2,
        read_registers8_delayed,
        read_registers16,
        write_registers_mapped,
        read_registers_mapped,
        read_device8,
        multi_write_device8,
        multi_read_device8,
    };
};

const I2c = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
