const service_names = [_][]const u8{ "hid:USER", "hid:SPVR" };

pub const Error = Session.RequestError;

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

session: Session,
input: ?Handles = null,
shm_memory_data: ?[]align(horizon.page_size_min) u8 = null,

pub fn init(srv: ServiceManager, shm_allocator: *SharedMemoryAddressPageAllocator) (MemoryBlock.MapError || SharedMemoryAddressPageAllocator.Error || Error)!Hid {
    var last_error: Error = undefined;
    const hid_session = used: for (service_names) |service_name| {
        const hid_session = srv.getService(service_name, true) catch |err| {
            last_error = err;
            continue;
        };

        break :used hid_session;
    } else return last_error;

    var hid = Hid{
        .session = hid_session,
    };
    errdefer hid.deinit(shm_allocator);

    const input = try hid.sendGetIPCHandles();
    hid.input = input;

    const shm_memory_data = try shm_allocator.allocateAddress(0x2B0);
    hid.shm_memory_data = shm_memory_data;

    try input.shm.map(shm_memory_data.ptr, .r, .dont_care);
    return hid;
}

pub fn deinit(hid: *Hid, shm_allocator: *SharedMemoryAddressPageAllocator) void {
    if (hid.input) |*input| {
        if (hid.shm_memory_data) |*shm_data| {
            input.shm.unmap(shm_data.ptr);
            shm_allocator.freeAddress(shm_data.*);
        }

        input.deinit();
    }

    hid.session.deinit();
    hid.* = undefined;
}

// TODO: Proper event handling
pub fn readPadInput(hid: *Hid) Pad.Entry {
    const hid_data = hid.shm_memory_data.?;
    const pad_data: *const Pad = std.mem.bytesAsValue(Pad, hid_data);

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

pub fn sendGetIPCHandles(hid: *Hid) Error!Handles {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.get_ipc_handles, .{}, .{});

    try hid.session.sendRequest();

    return Handles{
        .shm = @bitCast(data.ipc.parameters[2]),
        .pad_0 = @bitCast(data.ipc.parameters[3]),
        .pad_1 = @bitCast(data.ipc.parameters[4]),
        .accelerometer = @bitCast(data.ipc.parameters[5]),
        .gyroscope = @bitCast(data.ipc.parameters[6]),
        .debug_pad = @bitCast(data.ipc.parameters[7]),
    };
}

pub const Command = enum(u16) {
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

    pub inline fn normalParameters(cmd: Command) u6 {
        return switch (cmd) {
            .calibrate_touch_screen => 8,
            .get_ipc_handles => 0,
            .enable_accelerometer => 0,
            .disable_accelerometer => 0,
            .enable_giroscope_low => 0,
            .disable_giroscope_low => 0,
            .get_giroscope_low_raw_to_dps_coefficient => 0,
            .get_giroscope_low_calibrate_param => 0,
            .get_sound_volume => 0,
            else => @compileError("Not implemented"),
        };
    }

    pub inline fn translateParameters(cmd: Command) u6 {
        return switch (cmd) {
            .calibrate_touch_screen => 0,
            .get_ipc_handles => 0,
            .enable_accelerometer => 0,
            .disable_accelerometer => 0,
            .enable_giroscope_low => 0,
            .disable_giroscope_low => 0,
            .get_giroscope_low_raw_to_dps_coefficient => 0,
            .get_giroscope_low_calibrate_param => 0,
            .get_sound_volume => 0,
            else => @compileError("Not implemented"),
        };
    }
};

const Hid = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = zitrus.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ResultCode = horizon.ResultCode;
const Session = horizon.Session;
const Event = horizon.Event;
const MemoryBlock = horizon.MemoryBlock;

const ServiceManager = zitrus.horizon.ServiceManager;

const SharedMemoryAddressPageAllocator = horizon.SharedMemoryAddressPageAllocator;
