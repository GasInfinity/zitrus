//! `mic:u`
//!
//! Microphone access; only 1 client can access it at one time.
//!
//! Based on documentation found in 3dbrew: https://www.3dbrew.org/wiki/MIC_Services

pub const service = "mic:u";

pub const SampleRate = zitrus.hardware.mic.SampleRate;
pub const Encoding = enum(u2) { pcm8, pcm16, spcm8, spcm16 };

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

/// `block` should have rw perms for other processes.
pub fn sendInitialize(mic: MicUser, block: horizon.MemoryBlock, size: u32) !void {
    std.debug.assert(size > 0 and std.mem.isAligned(size, 2));

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.Initialize, .{
        .block = block,
        .size = size,
    }, .{})).cases()) {
        .success => {},
        .failure => |c| switch (c) {
            .mic_already_initialized => unreachable,
            .mic_invalid_size, .mic_unaligned_size => unreachable,
            else => horizon.unexpectedResult(c),
        },
    };
}

pub fn sendDeinitialize(mic: MicUser) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.Deinitialize, .{}, .{})).cases()) {
        .success => {},
        .failure => |c| switch (c) {
            else => horizon.unexpectedResult(c),
        },
    };
}

/// May return false if the shell is closed and it's not ignored (see `sendSetIgnoreShellState`)
pub fn sendStart(mic: MicUser, encoding: Encoding, sample_rate: SampleRate, offset: u32, size: u32, loop: bool) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.Start, .{
        .encoding = encoding,
        .sample_rate = sample_rate,
        .offset = offset,
        .size = size,
        .loop = loop,
    }, .{})).cases()) {
        .success => true,
        .failure => |c| switch (c) {
            .mic_shell_closed => false,
            .mic_not_initialized, .mic_out_of_range => horizon.resultBug(c),
            else => horizon.unexpectedResult(c),
        },
    };
}

pub fn sendAdjustSampleRate(mic: MicUser, sample_rate: SampleRate) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.AdjustSampleRate, .{
        .sample_rate = sample_rate,
    }, .{})).cases()) {
        .success => true,
        .failure => |c| switch (c) {
            .mic_shell_closed => false,
            .mic_not_initialized => horizon.resultBug(c),
            else => horizon.unexpectedResult(c),
        },
    };
}

pub fn sendStop(mic: MicUser) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.Stop, .{}, .{})).cases()) {
        .success => true,
        .failure => |c| switch (c) {
            .mic_shell_closed => false,
            .mic_not_initialized => horizon.resultBug(c),
            else => horizon.unexpectedResult(c),
        },
    };
}

pub fn sendIsRecording(mic: MicUser) !bool {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.IsRecording, .{}, .{})).cases()) {
        .success => |r| r.value.recording,
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendGetDataAvailableEvent(mic: MicUser) !horizon.Event {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.GetFinishedRecordingEvent, .{}, .{})).cases()) {
        .success => |r| r.value.data_available,
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendSetClampSamples(mic: MicUser, clamp: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.SetClampSamples, .{
        .clamp = clamp,
    }, .{})).cases()) {
        .success => {},
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendIsClampingSamples(mic: MicUser) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.IsClampingSamples, .{}, .{})).cases()) {
        .success => |r| r.value.clamp,
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub fn sendSetIgnoreShellState(mic: MicUser, ignore: bool) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(mic.session, command.SetIgnoreShellState, .{
        .ignore = ignore,
    }, .{})).cases()) {
        .success => {},
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    /// May fail with 0xd8208ff9 (already initialized), 0xe0e08fec (size is 0) or 0xe0e08ff2 (unaligned size, must be aligned to 2 bytes), 0xe0e01bf2 (unaligned size, must be aligned to 4096 bytes), 0xd8601837 (could not allocate shared memory for mapping)
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        size: u32,
        block: horizon.MemoryBlock,
    }, void);
    /// May fail with 0xd8208ff8 (not initialized)
    pub const Deinitialize = ipc.Command(Id, .deinitialize, void, void);
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed), 0xe1008ffd (offset + size oob),
    pub const Start = ipc.Command(Id, .start, struct {
        encoding: Encoding,
        sample_rate: SampleRate,
        offset: u32,
        size: u32,
        loop: bool,
    }, void);
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed) or 0xe0e003ed (invalid sample_rate value)
    pub const AdjustSampleRate = ipc.Command(Id, .adjust_sample_rate, SampleRate, void);
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed)
    pub const Stop = ipc.Command(Id, .stop, void, void);
    /// Cannot fail
    pub const IsRecording = ipc.Command(Id, .is_recording, void, bool);
    /// Cannot fail
    pub const GetFinishedRecordingEvent = ipc.Command(Id, .get_finished_recording_event, void, horizon.Event);
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const SetGain = ipc.Command(Id, .set_gain, CdcMic.command.SetGain.Request, CdcMic.command.SetGain.Response);
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const GetGain = ipc.Command(Id, .get_gain, CdcMic.command.GetGain.Request, CdcMic.command.GetGain.Response);
    /// Wrapper of cdc:MIC, forwards it's result. When powering on the microphone, one second will be filled with silence.
    pub const SetPowered = ipc.Command(Id, .set_powered, CdcMic.command.SetPowered.Request, CdcMic.command.SetPowered.Response);
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const IsPowered = ipc.Command(Id, .is_powered, CdcMic.command.IsPowered.Request, CdcMic.command.IsPowered.Response);
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const SetIirFilter = ipc.Command(Id, .set_iir_filter, CdcMic.command.SetIirFilter.Request, CdcMic.command.SetIirFilter.Response);
    /// Cannot fail
    pub const SetClampSamples = ipc.Command(Id, .set_clamp_samples, bool, void);
    /// Cannot fail
    pub const IsClampingSamples = ipc.Command(Id, .is_clamping_samples, void, bool);
    /// Cannot fail
    pub const SetIgnoreShellState = ipc.Command(Id, .set_ignore_shell_state, bool, void);
    /// Cannot fail
    pub const DisableLegacySampling = ipc.Command(Id, .disable_legacy_sampling, bool, void);

    pub const Id = enum(u16) {
        initialize = 0x0001,
        deinitialize,
        start,
        adjust_sample_rate,
        stop,
        is_recording,
        get_finished_recording_event,
        set_gain,
        get_gain,
        set_powered,
        is_powered,
        set_iir_filter,
        set_clamp_samples,
        is_clamping_samples,
        set_ignore_shell_state,
        disable_legacy_sampling,
    };
};

const MicUser = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;

const CdcMic = horizon.services.cdc.Mic;
