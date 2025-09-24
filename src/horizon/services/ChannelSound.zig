//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/CSND_Services
// TODO: Only missing methods

pub const service = "csnd:SND";

// TODO: Finish this.
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
        set_channel_unknown0,
        set_channel_hold_last,
        set_channel_wave_duty,
        set_channel_sample_rate,
        set_channel_volume,
        set_channel_buffer,
        set_channel_imaadpcm_info,
        set_channel_imaadpcm_loopinfo,
        set_channel_imaadpcm_reload_second_buffer_state,
        set_channel,
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
        pub const SetChannelPlayback = extern struct {
            pub const Operation = enum(u8) { start, stop };
            /// If `start`, begins audio playback.
            /// Otherwise stops it and resets `csnd` registers.
            operation: Operation,
            _unused0: [19]u8 = @splat(0),
        };

        pub const SetChannelPaused = extern struct {
            pub const Operation = enum(u8) { play, pause };
            /// If `pause`, playback pauses until `play`.
            operation: Operation,
            _unused0: [19]u8 = @splat(0),
        };

        pub const SetChannelFormat = extern struct {
            format: hardware.LsbRegister(csnd.Channel.Format),
            _unused0: [19]u8 = @splat(0),
        };

        pub const SetChannelSecondBuffer = extern struct {
            address: hardware.PhysicalAddress,
            size: u32,
            _unused0: [12]u8 = @splat(0),
        };

        pub const SetChannelRepeat = extern struct {
            repeat: hardware.LsbRegister(csnd.Channel.Repeat),
            _unused0: [19]u8 = @splat(0),
        };

        set_channel_playback: SetChannelPlayback,
        set_channel_paused: SetChannelPaused,
        set_channel_format: SetChannelFormat,
        set_channel_second_buffer: SetChannelSecondBuffer,
        set_channel_repeat: SetChannelRepeat,
    };

    next: Offset,
    id: Id,
    /// Set to true if this is the first command executed by `csnd`
    /// and it finished executing the chain.
    first_finished: bool = false,
    _padding0: [3]u8 = @splat(0),
    channel: ChannelId,
    _padding1: [3]u8 = @splat(0),
    parameters: Parameters,
};

pub const ChannelId = enum(u8) {
    pub const Mask = packed struct(u8) { @"0": bool, @"1": bool, @"2": bool, @"3": bool, _: u4 };

    @"0",
    @"1",
    @"2",
    @"3",
};

pub const CaptureId = enum(u8) { @"0", @"1" };
pub const Priority = enum(u8) { _ };

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

pub fn sendPlaySoundDirectly(snd: ChannelSound, channel: ChannelId, priority: Priority) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.PlaySoundDirectly, .{ .channel = channel, .priority = priority }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendAcquireSoundChannels(snd: ChannelSound) !ChannelId.Mask {
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

pub fn sendAcquireCaptureUnit(snd: ChannelSound) !CaptureId {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.AcquireCaptureUnit, .{}, .{})).cases()) {
        .success => |s| s.value.response.unit,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseCaptureUnit(snd: ChannelSound, unit: CaptureId) !void {
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
        shared_block_size: u32,
        offset0: u32,
        offset1: u32,

        // XXX: What does offset2 and offset3 do? Only offset0 and offset1 are documented in 3dbrew
        offset2: u32,
        offset3: u32,
    }, struct {
        mutex_shm: [2]horizon.Object,
    });
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {}, struct {});
    pub const ExecuteCommands = ipc.Command(Id, .execute_commands, struct { shm_offset: u32 }, struct {});
    pub const PlaySoundDirectly = ipc.Command(Id, .play_sound_directly, struct { channel: Id, priority: Priority }, struct {});
    pub const AcquireSoundChannels = ipc.Command(Id, .acquire_sound_channels, struct {}, struct { available: ChannelId.Mask });
    pub const ReleaseSoundChannels = ipc.Command(Id, .release_sound_channels, struct {}, struct {});
    pub const AcquireCaptureUnit = ipc.Command(Id, .acquire_capture_unit, struct {}, struct { unit: CaptureId });
    pub const ReleaseCaptureUnit = ipc.Command(Id, .release_capture_unit, struct { unit: CaptureId }, struct {});
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

const ClientSession = horizon.ClientSession;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = horizon.ServiceManager;
