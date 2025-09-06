// XXX: We should try to connect first to SPRV, shouldn't we?
const service_names = [_][]const u8{ "hid:USER", "hid:SPRV" };

pub const Input = @import("Hid/Input.zig");

pub const Pad = extern struct {
    pub const State = packed struct(u32) {
        a: bool,
        b: bool,
        select: bool,
        start: bool,
        right: bool,
        left: bool,
        up: bool,
        down: bool,
        r: bool,
        l: bool,
        x: bool,
        y: bool,
        _: u14 = 0,
        inverted_gpio0: bool,
        inverted_gpio14: bool,
        circle_pad_right: bool,
        circle_pad_left: bool,
        circle_pad_up: bool,
        circle_pad_down: bool,

        pub inline fn changed(state: State, other: State) State {
            const st: u32 = @bitCast(state);
            const ot: u32 = @bitCast(other);

            return @bitCast(st ^ ot);
        }

        pub inline fn same(state: State, other: State) State {
            const st: u32 = @bitCast(state);
            const ot: u32 = @bitCast(other);

            return @bitCast(st & ot);
        }
    };

    pub const CircleState = packed struct(u32) { x: i16, y: i16 };

    pub const Entry = extern struct { current: State, pressed: State, released: State, circle: CircleState };

    tick: i64,
    previous_tick: i64,
    index: u32,
    _pad0: u32 = 0,
    slider_3d: f32,
    current: State,
    circle: CircleState,
    _pad1: u32 = 0,
    entries: [8]Entry,
};

pub const Touch = extern struct {
    pub const State = extern struct { x: i16, y: i16, pressed: bool, _pad0: [3]u8 };

    tick: i64,
    previous_tick: i64,
    index: u32,
    _pad0: u32 = 0,
    raw: State,
    entries: [8]State,
};

pub const Accelerometer = extern struct {
    pub const State = extern struct { x: i16, y: i16, z: i16 };

    tick: i64,
    previous_tick: i64,
    index: u32,
    _pad0: u32 = 0,
    raw: State,
    _pad1: u16 = 0,
    entries: [8]State,
};

pub const Gyroscope = extern struct {
    pub const State = extern struct { x: i16, y: i16, z: i16 };

    tick: i64,
    previous_tick: i64,
    index: u32,
    _pad0: u32 = 0,
    raw: State,
    _pad1: u16 = 0,
    entries: [32]State,
};

pub const DebugPad = extern struct {
    pub const State = extern struct { _: [12]u8 };

    tick: i64,
    previous_tick: i64,
    index: u32,
    _pad0: u32 = 0,
    entries: [8]State,
};

pub const Shared = extern struct {
    pad: Pad,
    touch: Touch,
    accelerometer: Accelerometer,
    gyroscope: Gyroscope,
    debug_pad: DebugPad,
};

pub const ControllerState = struct {
    current: Pad.State,
    pressed: Pad.State,
    released: Pad.State,
    circle: Pad.CircleState,
};

session: ClientSession,

pub fn open(srv: ServiceManager) !Hid {
    var last_error: anyerror = undefined;
    const hid_session = used: for (service_names) |service_name| {
        const hid_session = srv.getService(service_name, .wait) catch |err| {
            last_error = err;
            continue;
        };

        break :used hid_session;
    } else return last_error;

    return .{ .session = hid_session };
}

pub fn close(hid: Hid) void {
    hid.session.close();
}

pub const Handles = struct {
    shm: MemoryBlock,
    pad_0: Event,
    pad_1: Event,
    accelerometer: Event,
    gyroscope: Event,
    debug_pad: Event,

    pub fn close(handles: *Handles) void {
        handles.shm.close();
        handles.pad_0.close();
        handles.pad_1.close();
        handles.accelerometer.close();
        handles.gyroscope.close();
        handles.debug_pad.close();
    }
};

pub fn sendGetIPCHandles(hid: Hid) !Handles {
    const data = tls.getThreadLocalStorage();
    return switch (try data.ipc.sendRequest(hid.session, command.GetIPCHandles, .{}, .{})) {
        .success => |s| .{
            .shm = @bitCast(@intFromEnum(s.value.response.handles[0])),
            .pad_0 = @bitCast(@intFromEnum(s.value.response.handles[1])),
            .pad_1 = @bitCast(@intFromEnum(s.value.response.handles[2])),
            .accelerometer = @bitCast(@intFromEnum(s.value.response.handles[3])),
            .gyroscope = @bitCast(@intFromEnum(s.value.response.handles[4])),
            .debug_pad = @bitCast(@intFromEnum(s.value.response.handles[5])),
        },
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const GetIPCHandles = ipc.Command(Id, .get_ipc_handles, struct {}, struct { handles: [6]horizon.Object });

    pub const Id = enum(u16) {
        calibrate_touch_screen = 0x0001,
        update_touch_config,
        unknown0,
        unknown1,
        unknown2,
        unknown3,
        unknown4,
        unknown5,
        unknown7,
        get_ipc_handles,
        start_analog_stick_calibration,
        stop_analog_stick_calibration,
        set_analog_stick_calibrate_param,
        get_analog_stick_calibrate_param,
        unknown8,
        unknown9,
        enable_accelerometer,
        disable_accelerometer,
        enable_giroscope_low,
        disable_giroscope_low,
        get_giroscope_low_raw_to_dps_coefficient,
        get_giroscope_low_calibrate_param,
        get_sound_volume,
    };
};

const Hid = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.result.Code;
const ClientSession = horizon.ClientSession;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;

const ServiceManager = zitrus.horizon.ServiceManager;
