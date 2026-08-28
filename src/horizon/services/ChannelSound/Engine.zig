pub const DirectSound = ChannelSound.DirectSound;

handles: ChannelSound.Handles,
commands: []align(horizon.heap.page_size) Command,
state: *ChannelSound.State,

available_mask: ChannelSound.Channel.Id.Mask,
available_channels: usize,

pub fn initCapacity(csnd: ChannelSound, max_commands: usize) !Engine {
    const shm_memory_data = horizon.heap.allocShared(max_commands * @sizeOf(ChannelSound.Command) + @sizeOf(ChannelSound.State));
    return try .initCapacityAddress(csnd, max_commands, shm_memory_data);
}

pub fn initCapacityAddress(csnd: ChannelSound, max_commands: usize, shared_address: [*]align(horizon.heap.page_size) u8) !Engine {
    const state_offset = max_commands * @sizeOf(ChannelSound.Command);
    const shm_size = std.mem.alignForward(usize, state_offset + @sizeOf(ChannelSound.State), horizon.heap.page_size);

    const handles = try csnd.sendInitialize(
        shm_size, 
        state_offset + @offsetOf(ChannelSound.State, "acquired"),
        state_offset + @offsetOf(ChannelSound.State, "channels"),
        state_offset + @offsetOf(ChannelSound.State, "captures"),
        state_offset + @offsetOf(ChannelSound.State, "direct"),
    );
    errdefer handles.deinit();

    try handles.shared_memory.map(shared_address, .rw, .dont_care);
    errdefer handles.shared_memory.unmap(shared_address);

    const commands: [*]align(horizon.heap.page_size) Command = @ptrCast(shared_address);
    const state: *ChannelSound.State = @alignCast(@ptrCast(shared_address + state_offset));

    const available_mask = try csnd.sendAcquireSoundChannels();
    const available_channels = @popCount(@as(u32, @bitCast(available_mask)));

    return .{
        .handles = handles,
        .commands = commands[0..max_commands],
        .state = state,

        .available_mask = available_mask,
        .available_channels = available_channels,
    };
}

pub fn deinit(engine: *Engine, csnd: ChannelSound) void {
    csnd.sendReleaseSoundChannels() catch {};
    engine.handles.shared_memory.unmap(@ptrCast(engine.commands.ptr));
    engine.handles.deinit();
    csnd.sendShutdown() catch {};
    engine.* = undefined;
}

pub fn playDirect(engine: *Engine, csnd: ChannelSound, id: DirectSound.Id, priority: DirectSound.Priority, sound: *const DirectSound) !bool {
    const direct_state = &engine.state.direct;

    {
        try engine.handles.mutex.wait(.none);
        defer engine.handles.mutex.release();

        direct_state.* = sound.*;
    }

    return try csnd.sendPlaySoundDirectly(id, priority);
}

/// Stops the `DirectSound` with the supplied `id`
pub fn stopDirect(engine: *Engine, csnd: ChannelSound, id: DirectSound.Id) !void {
    _ = try engine.playDirect(csnd, id, .max, &.{
        .finished = false,
        .stereo = false,
        .channels = 1,
        .format = .init(.pcm8),
        .sample_rate = 44100,
        .buffer = @splat(.zero),
        // We need at least some samples; CSND doesn't update 
        // the priority if there's no audio.
        .size = 32,
        .ima_state = undefined,
        .volume = @splat(0),
        .ignore_sleep = true,
        // We don't want to play bogus data
        .ignore_volume_slider = true,
    });
}

pub fn waitCompletion(engine: *Engine, first: *const Command) !void {
    return try engine.waitCompletionTimeout(first, .none);
}

pub fn waitCompletionTimeout(engine: *Engine, first: *const Command, timeout: horizon.Timeout) !void {
    while (!@atomicLoad(bool, &first.first_finished, .monotonic)) {
        try engine.handles.mutex.wait(timeout);
        defer engine.handles.mutex.release();
    } 
}

const Engine = @This();
const ChannelSound = horizon.services.ChannelSound;
const Command = ChannelSound.Command;
const Channel = ChannelSound.Channel;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const environment = horizon.environment;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Result = horizon.Result;
const ResultCode = horizon.result.Code;
