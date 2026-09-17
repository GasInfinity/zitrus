//! (Channel)Sound or (Ctr)Sound (?)
//!
//! Completely independent from the DSP;
//! Primarily used for sound effects but can be used to stream audio.
//!
//! Channels 0-7 are allocated to direct sounds; processes will always
//! acquire channels 8-32. All processes acquire always the same channels.
//!
//! Sounds played directly (on channels 0-7) seem to cut off all DSP output.
//!
//! Based on reverse enginering & the documentation found in 3dbrew: https://www.3dbrew.org/wiki/CSND_Services

pub const service = "csnd:SND";
pub const Engine = @import("ChannelSound/Engine.zig");

pub const Command = extern struct {
    pub const Offset = enum(u16) {
        none = 0xFFFF,
        _,

        pub fn offset(value: u16) Offset {
            return @enumFromInt(value);
        }
    };

    pub const Id = enum(u16) {
        set_channel_playback = 0x0000,
        set_channel_paused,
        set_channel_format,
        set_channel_loop_buffer,
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

        write_channels_captures_to_unknown = 0x200,
        write_state = 0x300,
    };

    pub const Parameters = extern union {
        pub const None = extern struct {
            pub const undef: None = .{ ._ = undefined };

            _: [6]u32,
        };

        pub const SetChannelPlayback = extern struct {
            pub const Operation = enum(u32) { stop, start, _ };
            channel: hardware.LsbRegister(Channel.Id),
            /// If `start`, begins audio playback.
            /// Otherwise stops it and resets `csnd` registers.
            operation: Operation,
            _unused0: [16]u8 = undefined,

            pub fn playback(channel: Channel.Id, operation: Operation) SetChannelPlayback {
                return .{ .channel = .init(channel), .operation = operation };
            }
        };

        pub const SetChannelPaused = extern struct {
            pub const Operation = enum(u32) { pause, play, _ };
            channel: hardware.LsbRegister(Channel.Id),
            /// If `pause`, playback pauses until `play`.
            operation: Operation,
            _unused0: [16]u8 = undefined,

            pub fn paused(channel: Channel.Id, operation: Operation) SetChannelPaused {
                return .{ .channel = .init(channel), .operation = operation };
            }
        };

        pub const SetChannelFormat = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            format: hardware.LsbRegister(Channel.Format),
            _unused0: [16]u8 = undefined,

            pub fn fmt(channel: Channel.Id, format: Channel.Format) SetChannelFormat {
                return .{ .channel = .init(channel), .format = .init(format) };
            }
        };

        pub const SetChannelBuffer = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            address: hardware.PhysicalAddress,
            size: u32,
            _unused0: [12]u8 = undefined,

            pub fn buffer(channel: Channel.Id, address: hardware.PhysicalAddress, size: u32) SetChannelFormat {
                return .{ .channel = .init(channel), .address = address, .size = size };
            }
        };

        pub const SetChannelRepeat = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            repeat: hardware.LsbRegister(Channel.Repeat),
            _unused0: [16]u8 = undefined,

            pub fn buffer(channel: Channel.Id, repeat: Channel.Repeat) SetChannelFormat {
                return .{ .channel = .init(channel), .repeat = repeat };
            }
        };

        pub const SetChannelHoldLast = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            hold_last: hardware.LsbRegister(bool),
            _unused0: [16]u8 = undefined,

            pub fn holdLast(channel: Channel.Id, hold_last: bool) SetChannelHoldLast {
                return .{ .channel = .init(channel), .hold_last = .init(hold_last) };
            }
        };

        pub const SetChannelLinearlyInterpolate = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            linearly_interpolate: hardware.LsbRegister(bool),
            _unused0: [16]u8 = undefined,

            pub fn linearlyInterpolate(channel: Channel.Id, linearly_interpolate: bool) SetChannelLinearlyInterpolate {
                return .{ .channel = .init(channel), .linearly_interpolate = .init(linearly_interpolate) };
            }
        };

        pub const SetChannelWaveDuty = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            wave_duty: hardware.LsbRegister(Channel.WaveDuty),
            _unused0: [16]u8 = undefined,

            pub fn waveDuty(channel: Channel.Id, wave_duty: Channel.WaveDuty) SetChannelWaveDuty {
                return .{ .channel = .init(channel), .wave_duty = .init(wave_duty) };
            }
        };

        pub const SetChannelSampleRate = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            sample_rate: hardware.LsbRegister(SampleRate),
            _unused0: [16]u8 = undefined,

            pub fn sampleRate(channel: Channel.Id, sample_rate: SampleRate) SetChannelSampleRate {
                return .{ .channel = .init(channel), .sample_rate = .init(sample_rate) };
            }
        };

        pub const SetChannelVolume = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            channel_volume: Channel.Volume,
            capture_volume: Channel.Volume,
            _unused0: [12]u8 = undefined,

            pub fn volume(channel: Channel.Id, channel_volume: Channel.Volume, capture_volume: Channel.Volume) SetChannelVolume {
                return .{ .channel = .init(channel), .channel_volume = .init(channel_volume), .capture_volume = .init(capture_volume) };
            }
        };

        pub const SetChannelImaAdPcm = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            state: Channel.ImaAdPcm,
            _unused0: [16]u8 = undefined,

            pub fn imaAdPcm(channel: Channel.Id, state: Channel.ImaAdPcm) SetChannelImaAdPcm {
                return .{ .channel = .init(channel), .state = state };
            }
        };

        pub const SetChannelImaAdPcmLoopReload = extern struct {
            channel: hardware.LsbRegister(Channel.Id),
            ima_ad_pcm_reload: hardware.LsbRegister(bool),
            _unused0: [16]u8 = undefined,

            pub fn imaAdPcmReload(channel: Channel.Id, value: bool) SetChannelImaAdPcmLoopReload {
                return .{ .channel = .init(channel), .ima_ad_reload = .init(value) };
            }
        };

        pub const SetChannelSound = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u1 = 0,
                linearly_interpolate: bool,
                _unused1: u3 = 0,
                repeat: Channel.Repeat,
                format: Channel.Format,
                disable_pause: bool,
                _unused2: u1 = 0,
                sample_rate: SampleRate,
            };

            control: SetChannelSound.Control,
            channel_volume: Channel.Volume,
            capture_volume: Channel.Volume,
            address: hardware.PhysicalAddress,
            loop_address: hardware.PhysicalAddress,
            size: u32,
        };

        pub const SetChannelPsgSquare = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u9 = 0,
                disable_pause: bool,
                _unused1: u1,
                sample_rate: SampleRate,
            };

            control: Control,
            channel_volume: Channel.Volume,
            capture_volume: Channel.Volume,
            duty: hardware.LsbRegister(Channel.WaveDuty),
            _unused0: [8]u8 = undefined,
        };

        pub const SetChannelPsgNoise = extern struct {
            pub const Control = packed struct(u32) {
                channel: Channel.Id,
                _unused0: u9 = 0,
                disable_pause: bool,
                _unused1: u17,
            };

            control: Control,
            channel_volume: Channel.Volume,
            capture_volume: Channel.Volume,
            _unused0: [12]u8 = undefined,
        };

        pub const SetCaptureStart = extern struct {
            capture: hardware.LsbRegister(Capture.Id),
            start: hardware.LsbRegister(bool),
            _unused0: [16]u8 = undefined,

            pub fn captureStart(capture: Capture.Id, start: bool) SetCaptureStart {
                return .{ .capture = .init(capture), .start = .init(start) };
            }
        };

        pub const SetCaptureOneShot = extern struct {
            capture: hardware.LsbRegister(Capture.Id),
            one_shot: hardware.LsbRegister(bool),
            _unused0: [16]u8 = undefined,

            pub fn oneShot(capture: Capture.Id, one_shot: bool) SetCaptureOneShot {
                return .{ .capture = .init(capture), .one_shot = .init(one_shot) };
            }
        };

        pub const SetCaptureFormat = extern struct {
            capture: hardware.LsbRegister(Capture.Id),
            format: hardware.LsbRegister(Capture.Format),
            _unused0: [16]u8 = undefined,

            pub fn fmt(capture: Capture.Id, format: Capture.Format) SetCaptureFormat {
                return .{ .capture = .init(capture), .format = .init(format) };
            }
        };

        pub const SetCaptureSampleRate = extern struct {
            capture: hardware.LsbRegister(Capture.Id),
            sample_rate: hardware.LsbRegister(SampleRate),
            _unused0: [16]u8 = undefined,

            pub fn sampleRate(capture: Capture.Id, sample_rate: SampleRate) SetCaptureSampleRate {
                return .{ .capture = .init(capture), .sample_rate = .init(sample_rate) };
            }
        };

        pub const SetCaptureBuffer = extern struct {
            capture: hardware.LsbRegister(Capture.Id),
            address: hardware.PhysicalAddress,
            size: u32,
            _unused0: [12]u8 = undefined,

            pub fn buffer(capture: Capture.Id, address: hardware.PhysicalAddress, size: u32) SetCaptureBuffer {
                return .{ .capture = .init(capture), .address = address, .size = size };
            }
        };

        pub const SetCapture = extern struct {
            pub const Control = packed struct(u32) {
                one_shot: bool,
                format: Capture.Format,
                unk0: bool,
                _unused0: u12 = 0,
                start: bool,
                sample_rate: SampleRate,
            };

            capture: hardware.LsbRegister(Capture.Id),
            control: Control,
            address: hardware.PhysicalAddress,
            size: u32,
            _unused0: [8]u8 = undefined,
        };

        none: None,
        set_channel_playback: SetChannelPlayback,
        set_channel_paused: SetChannelPaused,
        set_channel_format: SetChannelFormat,
        set_channel_loop_buffer: SetChannelBuffer,
        set_channel_repeat: SetChannelRepeat,
        set_channel_hold_last: SetChannelHoldLast,
        set_channel_linearly_interpolate: SetChannelLinearlyInterpolate,
        set_channel_wave_duty: SetChannelWaveDuty,
        set_channel_sample_rate: SetChannelSampleRate,
        set_channel_buffer: SetChannelBuffer,
        set_channel_ima_ad_pcm_start: SetChannelImaAdPcm,
        set_channel_ima_ad_pcm_loop: SetChannelImaAdPcm,
        set_channel_ima_ad_pcm_loop_reload: SetChannelImaAdPcmLoopReload,
        set_channel_sound: SetChannelSound,
        set_channel_psg: SetChannelPsgSquare,
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

    pub fn setChannelPlayback(next: Offset, playback: Parameters.SetChannelPlayback) Command {
        return .{
            .next = next,
            .id = .set_channel_playback,
            .parameters = .{ .set_channel_playback = playback },
        };
    }

    pub fn setChannelSound(next: Offset, sound: Parameters.SetChannelSound) Command {
        return .{
            .next = next,
            .id = .set_channel_sound,
            .parameters = .{ .set_channel_sound = sound },
        };
    }

    pub fn writeChannelsCapturesToUnknown(next: Offset) Command {
        return .{
            .next = next,
            .id = .write_channels_captures_to_unknown,
            .parameters = .{ .none = .undef },
        };
    }

    pub fn writeState(next: Offset) Command {
        return .{
            .next = next,
            .id = .write_state,
            .parameters = .{ .none = .undef },
        };
    }

    comptime {
        std.debug.assert(@sizeOf(ChannelSound.Command) == 0x20);
    }
};

pub const SampleRate = csnd.SampleRate;
pub const Channel = extern struct {
    pub const Volume = csnd.Channel.Volume;
    pub const Format = csnd.Channel.Format;
    pub const Repeat = csnd.Channel.Repeat;
    pub const WaveDuty = csnd.Channel.WaveDuty;
    pub const ImaAdPcm = csnd.Channel.ImaAdPcm;
    pub const Id = enum(u5) {
        pub const Mask = hardware.BitpackedArray(bool, 32);

        _,

        pub fn channel(value: u5) Id {
            return @enumFromInt(value);
        }
    };

    active: bool,
    _pad0: [3]u8 = @splat(0),
    ima_state: Channel.ImaAdPcm,
    _pad1: [1]u8 = @splat(0),
    zero: u32 = 0,
};

pub const Capture = extern struct {
    pub const Id = enum(u1) {
        pub const Mask = hardware.BitpackedArray(bool, 32);

        @"0",
        @"1",
    };

    pub const Format = csnd.Capture.Format;

    active: bool,
    _pad0: [3]u8 = @splat(0),
    zero: u32 = 0,
};

pub const DirectSound = extern struct {
    pub const Id = enum(u2) {
        _,

        pub fn id(value: u2) Id {
            return @enumFromInt(value);
        }
    };

    pub const Priority = enum(u8) {
        pub const min: Priority = .priority(0x20);
        pub const max: Priority = .priority(0);
        _,

        pub fn priority(value: u8) Priority {
            return @enumFromInt(value);
        }
    };

    pub const Format = packed struct(u8) {
        fmt: Channel.Format,
        _: u6 = 0,

        pub fn init(fmt: Channel.Format) DirectSound.Format {
            return .{ .fmt = fmt };
        }
    };

    finished: bool = false,
    stereo: bool,
    _unused0: [2]u8 = undefined,
    channels: u8,
    format: DirectSound.Format,
    _unused1: [2]u8 = undefined,
    sample_rate: u32,
    buffer: [2]hardware.PhysicalAddress,
    size: u32,
    ima_state: [2]Channel.ImaAdPcm,
    speed_multiplier: f32 = 1.0,
    volume: [2]u32,
    linearly_interpolate: bool = true,
    _unused2: [3]u8 = undefined,
    /// Transition gain of the previous sound; the volume of the previous
    /// sound will be linearly interpolated from `1.0` to `transition_gain`
    /// for `transition_time` milliseconds and the new sound will play afterwards.
    transition_gain: f32 = 1.0,
    /// Transition time in milliseconds; see `transition_gain`
    transition_time: u32 = 0,
    /// Ignores the volume slider.
    ignore_volume_slider: bool = false,
    force_speaker_output: bool = false,
    /// Will keep playing even when sleeping. If `false` the
    /// sound will pause and play on sleep enter/exit.
    ///
    /// This doesn't mean it *will* be heard as CSND still
    /// fades the master volume on sleep and wakeup.
    ignore_sleep: bool = false,
    _unused3: [1]u8 = undefined,

    comptime {
        std.debug.assert(@sizeOf(DirectSound) == 0x3C);
    }
};

pub const State = extern struct {
    pub const Acquired = extern struct {
        /// This is acquired_channels & <some unknown value (fifo?) from csnd master registers>.
        channels: Channel.Id.Mask,
        /// This is acquire_capture_units & <some unknown value (fifo?) from csnd master registers>.
        capture_units: Capture.Id.Mask,
    };

    acquired: Acquired,
    channels: [csnd.channels]Channel,
    captures: [csnd.captures]Capture,
    direct: DirectSound,
};

pub const Handles = struct {
    /// Locked while CSND is reading/writing from/to shared state.
    mutex: horizon.Mutex,
    shared_memory: horizon.MemoryBlock,

    pub fn deinit(handles: Handles) void {
        handles.mutex.close();
        handles.shared_memory.close();
    }
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub fn sendInitialize(snd: ChannelSound, shared_memory_size: u32, acquired_state_offset: u32, channel_state_offset: u32, capture_unit_state_offset: u32, direct_sound_state_offset: u32) !Handles {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.Initialize, .{
        .shared_memory_size = shared_memory_size,
        .acquired_state_offset = acquired_state_offset,
        .channel_state_offset = channel_state_offset,
        .capture_unit_state_offset = capture_unit_state_offset,
        .direct_sound_state_offset = direct_sound_state_offset,
    }, .{})).cases()) {
        .success => |s| s.value.handles.wrapped,
        .failure => |code| horizon.unexpectedResult(code),
    };
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

/// Plays a sound directly, overtaking DSP output until the sound finishes.
///
/// Returns `true` if the sound was played
pub fn sendPlaySoundDirectly(snd: ChannelSound, id: DirectSound.Id, priority: DirectSound.Priority) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.PlaySoundDirectly, .{ .id = id, .priority = priority }, .{})).cases()) {
        .success => true,
        .failure => |code| switch (code) {
            .csnd_direct_sound_sleeping, .csnd_direct_sound_priority => false,
            .csnd_not_initialized => error.NotInitialized,
            else => horizon.unexpectedResult(code),
        },
    };
}

pub fn sendAcquireSoundChannels(snd: ChannelSound) !Channel.Id.Mask {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.AcquireSoundChannels, .{}, .{})).cases()) {
        .success => |s| s.value.available,
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
        .success => |s| s.value.unit,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendReleaseCaptureUnit(snd: ChannelSound, unit: Capture.Id) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(snd.session, command.ReleaseCaptureUnit, .{ .unit = unit }, .{})).cases()) {
        .success => |s| s.value.unit,
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
    /// May fail
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        shared_memory_size: u32,
        acquired_state_offset: u32,
        channel_state_offset: u32,
        capture_unit_state_offset: u32,
        direct_sound_state_offset: u32,
    }, struct {
        handles: ipc.HandleArray(Handles),
    });
    /// Never fails
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {}, struct {});
    /// May fail with 0xc8a0b7ff (not initialized) or 0xc8a0b7f0 (cannot push new command execution requests).
    ///
    /// Any command containing a non-allocated channel or capture unit will be ignored.
    pub const ExecuteCommands = ipc.Command(Id, .execute_commands, struct { shm_offset: u32 }, struct {});
    /// May fail with 0xc960b7f8 (not initialized), 0xc940b401 (sleeping and direct sound is not ignoring sleep) or 0xc940b402 (not enough priority)
    ///
    /// Maximum of 4 direct sounds; since CSND doesn't check the index you can write OOB anywhere so be careful.
    /// Maximum priority of 0, minimum of 32; if priority is lower or equal than current it will replace it, if not it fails with 0xc940b402.
    pub const PlaySoundDirectly = ipc.Command(Id, .play_sound_directly, struct { id: DirectSound.Id, priority: DirectSound.Priority }, struct {});
    /// Never fails
    ///
    /// All proccesses always acquire the same sound channels (0xFFFFFF00).
    pub const AcquireSoundChannels = ipc.Command(Id, .acquire_sound_channels, struct {}, struct { available: Channel.Id.Mask });
    /// Never fails
    ///
    /// Just clears the process acquired sound channels.
    pub const ReleaseSoundChannels = ipc.Command(Id, .release_sound_channels, struct {}, struct {});
    /// May fail
    ///
    /// Acquires from a pool shared by all processes; a maximum of 2 capture units can be acquired overall.
    /// Zeroes out the acquired capture unit data in shared memory.
    pub const AcquireCaptureUnit = ipc.Command(Id, .acquire_capture_unit, struct {}, struct { unit: Capture.Id });
    /// May fail with 0xc8a0b7ff (releasing a capture unit the process doesn't own)
    ///
    /// Releases to a pool shared by all processes.
    pub const ReleaseCaptureUnit = ipc.Command(Id, .release_capture_unit, struct { unit: Capture.Id }, struct {});
    /// Only accepts linear memory
    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct { address: u32, size: u32, process: horizon.Process }, struct {});
    /// Only accepts linear memory
    pub const StoreDataCache = ipc.Command(Id, .store_data_cache, struct { address: u32, size: u32, process: horizon.Process }, struct {});
    /// Only accepts linear memory
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct { address: u32, size: u32, process: horizon.Process }, struct {});
    /// Never fails.
    ///
    /// Resets all direct sound, channel and capture-related state.
    /// Does not reset acquired sound channels or capture units; those are kept by the process.
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

comptime {
    _ = DirectSound;
    _ = Command;
}

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
