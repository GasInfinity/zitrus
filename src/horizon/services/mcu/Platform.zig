//! `mcu::PLS`

pub const service = "mcu::PLS";

session: horizon.Session.Client,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const GetRealtime = ipc.Command(Id, .get_realtime, void, mcu.Realtime);
    pub const GetRealtimeSecond = ipc.Command(Id, .get_realtime_second, void, u8);
    pub const GetRealtimeMinute = ipc.Command(Id, .get_realtime_minute, void, u8);
    pub const GetRealtimeHour = ipc.Command(Id, .get_realtime_hour, void, u8);
    pub const GetRealtimeWeekday = ipc.Command(Id, .get_realtime_weekday, void, u8);
    pub const GetRealtimeDay = ipc.Command(Id, .get_realtime_day, void, u8);
    pub const GetRealtimeMonth = ipc.Command(Id, .get_realtime_month, void, u8);
    pub const GetRealtimeYear = ipc.Command(Id, .get_realtime_year, void, u8);
    pub const GetTickCounter = ipc.Command(Id, .get_tick_counter, void, u16);

    pub const Id = enum(u16) {
        get_realtime = 0x0001,
        get_realtime_second,
        get_realtime_minute,
        get_realtime_hour,
        get_realtime_weekday,
        get_realtime_day,
        get_realtime_month,
        get_realtime_year,
        get_tick_counter,
    };
};

const I2s = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const ipc = horizon.ipc;

const mcu = horizon.services.mcu;
