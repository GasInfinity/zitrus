//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/CSND_Services
// TODO: Only missing methods

// TODO: Investigate CSND

pub const service = "csnd:SND";

pub const ChannelId = enum(u8) {
    pub const Mask = packed struct(u8) { @"0": bool, @"1": bool, @"2": bool, @"3": bool, _: u4 };

    @"0",
    @"1",
    @"2",
    @"3",
};

pub const CaptureId = enum(u8) { @"0", @"1", @"2" };
pub const Priority = enum(u8) { _ };

session: ClientSession,

pub fn open(srv: ServiceManager) !ChannelSound {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(csnd: ChannelSound) void {
    csnd.session.close();
}

pub const command = struct {
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        shared_block_size: u32,
        offset0: u32,
        offset1: u32,
        offset2: u32,
        offset3: u32,
    }, struct {
        mutex_shm: [2]horizon.Object,
    });
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {}, struct {});
    pub const ExecuteCommands = ipc.Command(Id, .execute_commands, struct { shm_command_offset: u32 }, struct {});
    pub const PlaySoundDirectly = ipc.Command(Id, .play_sound_directly, struct { channel_id: Id, priority: Priority }, struct {});
    pub const AcquireSoundChannels = ipc.Command(Id, .acquire_sound_channels, struct {}, struct { available: ChannelId.Mask });
    pub const ReleaseSoundChannels = ipc.Command(Id, .release_sound_channels, struct {}, struct {});
    pub const AcquireCaptureUnit = ipc.Command(Id, .acquire_capture_unit, struct {}, struct { unit: CaptureId });
    pub const ReleaseCaptureUnit = ipc.Command(Id, .acquire_capture_unit, struct { unit: CaptureId }, struct {});
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

const ClientSession = horizon.ClientSession;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = horizon.ServiceManager;
