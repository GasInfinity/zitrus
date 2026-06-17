//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/CSND_Services

pub const service = "csnd:SND";

pub const Command = extern struct {
    pub const Offset = enum(i16) {
        none = 0xFFFF,
        _,

        pub fn offset(value: i16) Offset {
            return @enumFromInt(value);
        }
    };

    pub const Id = enum(u16) {
        set_channel_playback = 0x0000,
        set_channel_paused,
        set_channel_format,
        set_channel_second_buffer,
        set_channel_repeat,
        set_channel_hold_last,
        set_channel_linearly_interpolate,
        set_channel_wave_duty,
        set_channel_sample_rate,
        set_channel_volume,
        set_channel_buffer,
        set_channel_imaadpcm_info,
        set_channel_imaadpcm_loopinfo,
        set_channel_imaadpcm_reload_second_buffer_state,
        set_channel_sound,
        set_channel_psg_square,
        set_channel_psg_noise,

        set_capture_start = 0x100,
        set_capture_one_shot,
        set_capture_format,
        set_capture_unknown0,
        set_capture_sample_rate,
        set_capture_buffer,
        set_capture,

        interrupt_dsp_unknown0 = 0x200,

        write_register_state = 0x300,
    };

    pub const Parameters = extern union {
        pub const None = extern struct {};
        pub const SetChannelPlayback = extern struct {
            pub const Operation = enum(u8) { start, stop };
            channel: hardware.LsbRegister(Channel.Id),
            /// If `start`, begins audio playback.
            /// Otherwise stops it and resets `csnd` registers.
            operation: Operation,
            _unused0: [19]u8 = @splat(0),
        };

        pub const SetChannelPaused = extern struct {
            pub const Operation = enum(u8) { play, pause };
            channel: hardware.LsbRegister(Channel.Id),
            /// If `pause`, playback pauses until `play`.
            operation: Operation,
            _unused0: [19]u8 = @splat(0),
        };

        pub const SetChannelFormat = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            format: hardware.LsbRegister(csnd.Channel.Format),
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelBuffer = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            address: hardware.PhysicalAddress,
            size: u32,
            _unused0: [12]u8 = @splat(0),
        };

        pub const SetChannelRepeat = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            repeat: hardware.LsbRegister(csnd.Channel.Repeat),
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelHoldLast = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            hold_last: u32,
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelLinearlyInterpolate = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            linearly_interpolate: u32,
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelWaveDuty = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            wave_duty: hardware.LsbRegister(csnd.Channel.WaveDuty),
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelSampleRate = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            sample_rate: hardware.LsbRegister(csnd.SampleRate),
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelVolume = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            channel_volume: csnd.Channel.Volume,
            capture_volume: csnd.Channel.Volume,
            _unused0: [12]u8 = @splat(0),
        };

        pub const SetChannelImAdPcm = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            state: csnd.Channel.ImaAdPcm,
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelImAdPcmReloadSecondBuffer = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            reload: hardware.LsbRegister(bool),
            _unused0: [16]u8 = @splat(0),
        };

        pub const SetChannelSound = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u1 = 0,
                linearly_interpolate: bool,
                _unused1: u3 = 0,
                repeat: csnd.Channel.Repeat,
                format: csnd.Channel.Format,
                disable_pause: bool,
                _unused2: u1,
                sample_rate: csnd.SampleRate,
            };

            control: csnd.Channel.Control,
            channel_volume: csnd.Channel.Volume,
            capture_volume: csnd.Channel.Volume,
            address: hardware.PhysicalAddress,
            second_address: hardware.PhysicalAddress,
            size: u32,
        };

        pub const SetChannelPsg = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u9 = 0,
                disable_pause: bool,
                _unused1: u1,
                sample_rate: csnd.SampleRate,
            };

            control: Control,
            channel_volume: csnd.Channel.Volume,
            capture_volume: csnd.Channel.Volume,
            duty: hardware.LsbRegister(csnd.Channel.WaveDuty),
            _unused0: [8]u8 = @splat(0),
        };

        pub const SetChannelPsgNoise = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u9 = 0,
                disable_pause: bool,
                _unused1: u17,
            };

            control: Control,
            channel_volume: csnd.Channel.Volume,
            capture_volume: csnd.Channel.Volume,
            _unused0: [12]u8 = @splat(0),
        };

        // TODO: Finish this.
        pub const SetCaptureStart = extern struct {};
        pub const SetCaptureOneShot = extern struct {};
        pub const SetCaptureFormat = extern struct {};
        pub const SetCaptureSampleRate = extern struct {};
        pub const SetCaptureBuffer = extern struct {};
        pub const SetCapture = extern struct {};

        none: None,
        set_channel_playback: SetChannelPlayback,
        set_channel_paused: SetChannelPaused,
        set_channel_format: SetChannelFormat,
        set_channel_second_buffer: SetChannelBuffer,
        set_channel_repeat: SetChannelRepeat,
        set_channel_hold_last: SetChannelHoldLast,
        set_channel_linearly_interpolate: SetChannelLinearlyInterpolate,
        set_channel_wave_duty: SetChannelWaveDuty,
        set_channel_sample_rate: SetChannelSampleRate,
        set_channel_buffer: SetChannelBuffer,
        set_channel_imadpcm_start: SetChannelImAdPcm,
        set_channel_imadpcm_loop: SetChannelImAdPcm,
        set_channel_imadpcm_reload_second_buffer: SetChannelImAdPcmReloadSecondBuffer,
        set_channel_sound: SetChannelSound,
        set_channel_psg: SetChannelPsg,
        set_channel_psg_noise: SetChannelPsgNoise,

        set_capture_start: SetCaptureStart,
        set_capture_one_short: SetCaptureOneShot,
        set_capture_format: SetCaptureFormat,
        set_capture_sample_rate: SetCaptureSampleRate,
        set_capture_buffer: SetCaptureBuffer,
        set_capture: SetCapture,
    };

    next: Offset,
    id: Id,
    /// Set to true if this is the first command executed by `csnd`
    /// and it finished executing the chain.
    first_finished: bool = false,
    _padding0: [3]u8 = @splat(0),
    parameters: Parameters,
};

pub const Channel = extern struct {
    pub const Id = enum(u5) {
        pub const Mask = packed struct(u8) { @"0": bool, @"1": bool, @"2": bool, @"3": bool, _: u4 };

        @"0",
        @"1",
        @"2",
        @"3",
    };

    active: bool,
    _pad0: [3]u8 = @splat(0),
    ima_state: csnd.Channel.ImaAdPcm,
    _pad1: [1]u8 = @splat(0),
    zero: u32 = 0,
};

pub const Capture = extern struct {
    pub const Id = enum(u1) { @"0", @"1" };

    active: bool,
    _pad0: [3]u8 = @splat(0),
    zero: u32 = 0,
};

pub const Priority = enum(u8) { _ };

pub const State = extern struct {
    pub const Flags = extern struct { unk0: [2]u32 };

    flags: Flags,
    channels: [csnd.channels]Channel,
    captures: [csnd.captures]Capture,
    // TODO: direct sound?
};

pub const Handles = struct { mutex: horizon.Mutex, shared_memory: horizon.MemoryBlock };

session: ClientSession,

pub fn open(srv: ServiceManager) !ChannelSound {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(snd: ChannelSound) void {
    snd.session.close();
}

pub fn sendShutdown(snd: ChannelSound) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.Shutdown, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendExecuteCommands(snd: ChannelSound, shm_offset: u32) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.ExecuteCommands, .{ .shm_offset = shm_offset }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendPlaySoundDirectly(snd: ChannelSound, channel: Channel.Id, priority: Priority) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.PlaySoundDirectly, .{ .channel = channel, .priority = priority }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendAcquireSoundChannels(snd: ChannelSound) !Channel.Id.Mask {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.AcquireSoundChannels, .{}, .{})).cases()) {
        .success => |s| s.value.response.available,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseSoundChannels(snd: ChannelSound) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.ReleaseSoundChannels, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendAcquireCaptureUnit(snd: ChannelSound) !Capture.Id {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.AcquireCaptureUnit, .{}, .{})).cases()) {
        .success => |s| s.value.response.unit,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseCaptureUnit(snd: ChannelSound, unit: Capture.Id) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.ReleaseCaptureUnit, .{ .unit = unit }, .{})).cases()) {
        .success => |s| s.value.response.unit,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendFlushDataCache(snd: ChannelSound, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.FlushDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendInvalidateDataCache(snd: ChannelSound, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.InvalidateDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendStoreDataCache(snd: ChannelSound, buffer: []u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.StoreDataCache, .{ .address = @intFromPtr(buffer.ptr), .size = buffer.len, .process = .current }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReset(snd: ChannelSound) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.Reset, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        shared_memory_size: u32,
        dsp_state_offset: u32,
        channel_state_offset: u32,
        capture_unit_state_offset: u32,
        direct_sound_state_offset: u32,
    }, struct {
        handles: ipc.HandleArray(Handles),
    });
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {}, struct {});
    pub const ExecuteCommands = ipc.Command(Id, .execute_commands, struct { shm_offset: u32 }, struct {});
    pub const PlaySoundDirectly = ipc.Command(Id, .play_sound_directly, struct { channel: Channel.Id, priority: Priority }, struct {});
    pub const AcquireSoundChannels = ipc.Command(Id, .acquire_sound_channels, struct {}, struct { available: Channel.Id.Mask });
    pub const ReleaseSoundChannels = ipc.Command(Id, .release_sound_channels, struct {}, struct {});
    pub const AcquireCaptureUnit = ipc.Command(Id, .acquire_capture_unit, struct {}, struct { unit: Capture.Id });
    pub const ReleaseCaptureUnit = ipc.Command(Id, .release_capture_unit, struct { unit: Capture.Id }, struct {});
    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct { address: usize, size: usize, zero: u32 = 0, process: horizon.Process }, struct {});
    pub const StoreDataCache = ipc.Command(Id, .store_data_cache, struct { address: usize, size: usize, zero: u32 = 0, process: horizon.Process }, struct {});
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct { address: usize, size: usize, zero: u32 = 0, process: horizon.Process }, struct {});
    pub const Reset = ipc.Command(Id, .reset, struct {}, struct {});

    pub const Id = enum(u16) {
        initialize = 0x0001,
        shutdown,
        execute_commands,
        play_sound_directly,
        acquire_sound_channels,
        release_sound_channels,
        acquire_capture_unit,
        release_capture_unit,
        flush_data_cache,
        store_data_cache,
        invalidate_data_cache,
        reset,
    };
};

const ChannelSound = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const hardware = zitrus.hardware;
const csnd = hardware.csnd;

const ClientSession = horizon.Session.Client;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = horizon.ServiceManager;
