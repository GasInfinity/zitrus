// XXX: We should try to connect first to SPRV, shouldn't we?
const service_names = [_][]const u8{ "hid:USER", "hid:SPRV" };

// TODO: Refactor and finish HID
pub const Error = ClientSession.RequestError;

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

pub const ControllerState = struct {
    current: Pad.State,
    pressed: Pad.State,
    released: Pad.State,
    circle: Pad.CircleState,
};

session: ClientSession,
input: ?Handles = null,
shm_memory_data: ?[]u8 = null,

pub fn init(srv: ServiceManager) (error{OutOfMemory} || MemoryBlock.MapError || Error)!Hid {
    var last_error: Error = undefined;
    const hid_session = used: for (service_names) |service_name| {
        const hid_session = srv.getService(service_name, .wait) catch |err| {
            last_error = err;
            continue;
        };

        break :used hid_session;
    } else return last_error;

    var hid = Hid{
        .session = hid_session,
    };
    errdefer hid.deinit();

    const input = try hid.sendGetIPCHandles();
    hid.input = input;

    const shm_memory_data = try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(0x2B0, .@"1");
    hid.shm_memory_data = shm_memory_data;

    try input.shm.map(@alignCast(shm_memory_data.ptr), .r, .dont_care);
    return hid;
}

pub fn deinit(hid: *Hid) void {
    if (hid.input) |*input| {
        if (hid.shm_memory_data) |shm_data| {
            input.shm.unmap(@alignCast(shm_data.ptr));
            horizon.heap.non_thread_safe_shared_memory_address_allocator.free(shm_data);
        }

        input.deinit();
    }

    hid.session.deinit();
    hid.* = undefined;
}

// TODO: Proper event handling
pub fn readPadInput(hid: *Hid) Pad.Entry {
    const hid_data = hid.shm_memory_data.?;
    const pad_data: *const Pad = @alignCast(std.mem.bytesAsValue(Pad, hid_data));

    const current_index = pad_data.index;
    return pad_data.entries[current_index];
}

const Handles = struct {
    shm: MemoryBlock,
    pad_0: Event,
    pad_1: Event,
    accelerometer: Event,
    gyroscope: Event,
    debug_pad: Event,

    pub fn deinit(handles: *Handles) void {
        handles.shm.deinit();
        handles.pad_0.deinit();
        handles.pad_1.deinit();
        handles.accelerometer.deinit();
        handles.gyroscope.deinit();
        handles.debug_pad.deinit();
    }
};

pub fn sendGetIPCHandles(hid: Hid) Error!Handles {
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

const ResultCode = horizon.ResultCode;
const ClientSession = horizon.ClientSession;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;

const ServiceManager = zitrus.horizon.ServiceManager;

const SharedMemoryAddressAllocator = horizon.SharedMemoryAddressAllocator;
