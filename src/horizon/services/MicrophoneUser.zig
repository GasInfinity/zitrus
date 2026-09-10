//! `mic:u`
//!
//! Microphone access; only 1 client can access it at one time.
//!
//! Based on documentation found in 3dbrew: https://www.3dbrew.org/wiki/MIC_Services

pub const service = "mic:u";

pub const SampleRate = zitrus.hardware.mic.SampleRate;
pub const Encoding = enum(u2) { pcm8, pcm16, spcm8, spcm16 };

session: ClientSession,

pub fn open(srv: ServiceManager) !MicUser {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(mic: MicUser) void {
    mic.session.close();
}

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
    return switch ((try data.ipc.sendRequest(mic.session, command.GetDataAvailableEvent, .{}, .{})).cases()) {
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
    return switch ((try data.ipc.sendRequest(mic.session, command.SetIgnoreShellClosed, .{
        .ignore = ignore,
    }, .{})).cases()) {
        .success => {},
        // Cannot fail
        .failure => |c| horizon.unexpectedResult(c),
    };
}

pub const command = struct {
    /// May fail with 0xd8208ff9 (already initialized), 0xe0e08fec (size is 0) or 0xe0e08ff2 (unaligned size, must be aligned to 2 bytes)
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        size: u32,
        block: horizon.MemoryBlock,
    }, struct {});
    /// May fail with 0xd8208ff8 (not initialized)
    pub const Deinitialize = ipc.Command(Id, .deinitialize, struct {}, struct {});
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed), 0xe1008ffd (offset + size oob), 
    pub const Start = ipc.Command(Id, .start, struct {
        encoding: Encoding,
        sample_rate: SampleRate,
        offset: u32,
        size: u32,
        loop: bool,
    }, struct {});
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed)
    pub const AdjustSampleRate = ipc.Command(Id, Id, struct {
        sample_rate: SampleRate,
    }, struct {});
    /// May fail with 0xd8208ff8 (not initialized) 0xc9408c01 (shell closed while not allowing to record with it closed)
    pub const Stop = ipc.Command(Id, .stop, struct {}, struct {});
    /// Cannot fail
    pub const IsRecording = ipc.Command(Id, .is_recording, struct {}, struct {
        recording: bool,
    });
    /// Cannot fail
    pub const GetDataAvailableEvent = ipc.Command(Id, .get_data_available_event, struct {}, struct {
        data_available: horizon.Event,
    });
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const SetGain = ipc.Command(Id, .set_gain, struct {
        gain: u8,
    }, struct {});
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const GetGain = ipc.Command(Id, .get_gain, struct {}, struct {
        gain: u8,
    });
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const SetPowered = ipc.Command(Id, .set_powered, struct {
        powered: bool,
    }, struct {});
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const IsPowered = ipc.Command(Id, .is_powered, struct {}, struct {
        powered: bool,
    });
    /// Straight wrapper of cdc:MIC, forwards it's result.
    pub const SetIirFilter= ipc.Command(Id, .set_iir_filter, struct {
        powered: bool,
    }, struct {});
    /// Cannot fail
    pub const SetClampSamples = ipc.Command(Id, .set_clamp_samples, struct {
        clamp: bool,
    }, struct {});
    /// Cannot fail
    pub const IsClampingSamples = ipc.Command(Id, .is_clamping_samples, struct {}, struct {
        clamp: bool,
    });
    /// Cannot fail
    pub const SetIgnoreShellClosed = ipc.Command(Id, .ignore_shell_state, struct {}, struct {
        ignore: bool,
    });

    pub const Id = enum(u16) {
        initialize = 0x0001,
        deinitialize,
        start,
        adjust_sample_rate,
        stop,
        is_recording,
        get_data_available_event,
        set_gain,
        get_gain,
        set_powered,
        is_powered,
        set_iir_filter,
        set_clamp_samples,
        is_clamping_samples,
        set_ignore_shell_state,

        // Some sort of "legacy" (mayyybe?) mode? This being false sets a flag to true (which is already true by default), if that flag is true and sampling with encoding = pcm16s, sample_rate = 1
        // and size = 0x5ffc (24572) another mode is used.
        //
        // flag = false -> drains the MIC fifo statelessly, if it overruns the first sample after clearing the fifo will be the last sample before the overrun. pseudo:
        //   data = mic.data
        //   if (state.was_overrun) {
        //      state.was_overrun = false
        //      data = state.last_sample
        //   }
        //   state.last_sample = data
        //   sample_buf[cur] = state.last_sample
        //
        //   if (mic.cnt.fifo_overrun) state.was_overrun = true // Simplified, will also clear the fifo and restart sampling
        // 
        // flag = true (default), with conditions as above -> same as above but an overrun happening will restart sampling without the mumbo jumbo that happens above.
        // flag = true (default), without conditions -> much more complex, maintains some state to track elapsed ticks and the current samples written; calculating how many samples 
        // should be added to the buffer.
        //
        // Maybe the flag is some sort of "raw mode"? "legacy mode"? idk man
        //
        // Important, cannot fail obv
        set_different_mode,
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
