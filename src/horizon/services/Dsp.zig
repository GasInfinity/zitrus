//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/DSP_Services

pub const service = "dsp::DSP";

session: ClientSession,

pub const Address = hardware.dsp.Address;
pub const Sink = CdcDsp.Sink;
pub const IirBiquad = CdcDsp.IirBiquad;
pub const Biquad = CdcDsp.Biquad;
pub const TransferFlags = packed struct(u32) {
    increment_source: bool,
    increment_destination: bool,
    _: u30,
};

pub const Channel = enum(u8) {
    pub const Direction = enum(u8) { dsp, arm };
    _,
};

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const Recv = ipc.Command(Id, .recv, u2, u16);
    pub const IsRecvReady = ipc.Command(Id, .is_recv_ready, u2, bool);
    pub const Send = ipc.Command(Id, .send, struct {
        stream: u2,
        value: u16,
    }, void);
    pub const IsSendEmpty = ipc.Command(Id, .is_send_empty, u2, bool);

    pub const WriteDataTransfer = ipc.Command(Id, .write_data_transfer, struct {
        address: Address,
        len: u32,
        flags: TransferFlags,
        buffer: ipc.Static(u16, 0),
    }, void);

    pub const ReadDataTransfer = ipc.Command(Id, .read_data_transfer, struct {
        pub const StaticOutput = struct { buffer: []u16 };
        address: Address,
        len: u32,
        flags: TransferFlags,
    }, ipc.Static(u16, 0));

    pub const SendSemaphore = ipc.Command(Id, .send_semaphore, hardware.BitpackedArray(bool, 16), void);
    pub const RecvSemaphore = ipc.Command(Id, .recv_semaphore, void, hardware.BitpackedArray(bool, 16));
    pub const ClearSemaphore = ipc.Command(Id, .clear_semaphore, hardware.BitpackedArray(bool, 16), void);
    pub const DisableSemaphoreInterrupt = ipc.Command(Id, .disable_semaphore_interrupt, hardware.BitpackedArray(bool, 16), void);
    pub const IsSemaphoreRequested = ipc.Command(Id, .is_semaphore_requested, void, bool);

    pub const GetMappedDataAddress = ipc.Command(Id, .get_mapped_data_address, Address, u32);
    /// Cannot fail
    pub const WriteChannel = ipc.Command(Id, .write_channel, struct {
        channel: Channel,
        direction: Channel.Direction,
        buffer: ipc.Static(u8, 1),
    }, void);
    /// Cannot fail
    pub const ReadChannel = ipc.Command(Id, .read_channel, struct {
        pub const StaticOutput = struct { buffer: []u8 };

        channel: Channel,
        direction: Channel.Direction,
        len: u16,
    }, ipc.Static(u8, 0));
    /// Cannot fail
    pub const GetChannelUnusedCapacity = ipc.Command(Id, .get_channel_unused_capacity, struct {
        channel: Channel,
        direction: Channel.Direction,
    }, u16);
    /// Cannot fail
    pub const TryReadChannel = ipc.Command(Id, .try_read_channel, struct {
        pub const StaticOutput = struct { buffer: []u8 };

        channel: Channel,
        direction: Channel.Direction,
        len: u16,
    }, struct {
        actual_read: u16,
        buffer: ipc.Static(u8, 0),
    });

    pub const LoadComponent = ipc.Command(Id, .load_component, struct {
        size: u32,
        program_mask: u32,
        data_mask: u32,
        buffer: ipc.Mapped(u8, .r),
    }, struct { loaded: bool, buffer: ipc.Mapped(u8, .r) });
    pub const UnloadComponent = ipc.Command(Id, .unload_component, void, void);

    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct {
        address: u32,
        size: u32,
        process: horizon.Process,
    }, void);
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct {
        address: u32,
        size: u32,
        process: horizon.Process,
    }, void);
    pub const RegisterInterruptEvents = ipc.Command(Id, .register_interrupt_events, struct {
        irq: u32,
        channel: u32,
        event: horizon.Event,
    }, void);
    /// Cannot fail
    pub const GetSemaphoreSendEvent = ipc.Command(Id, .get_semaphore_send_event, void, horizon.Event);
    /// Cannot fail
    pub const SetSentSemaphore = ipc.Command(Id, .set_sent_semaphore, hardware.BitpackedArray(bool, 16), void);

    /// Cannot fail
    pub const GetPhysicalAddress = ipc.Command(Id, .get_physical_address, u32, u32);

    // This literally doesn't... exist? (in the latest module at least)
    // pub const GetVirtualAddress = ipc.Command(Id, .get_virtual_address, u32, u32);

    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const SetI2s1IirFilters = ipc.Command(Id, .set_i2s1_iir_filters, CdcDsp.command.SetI2s1IirFilters.Request, CdcDsp.command.SetI2s1IirFilters.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const SetI2s2IirFilters = ipc.Command(Id, .set_i2s2_iir_filters, CdcDsp.command.SetI2s2IirFilters.Request, CdcDsp.command.SetI2s2IirFilters.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const SetSinkIirFilters = ipc.Command(Id, .set_sink_iir_filters, CdcDsp.command.SetSinkIirFilters.Request, CdcDsp.command.SetSinkIirFilters.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const Read3dsTsc = ipc.Command(Id, .read_3ds_tsc, CdcDsp.command.Read3dsTsc.Request, CdcDsp.command.Read3dsTsc.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const Write3dsTsc = ipc.Command(Id, .write_3ds_tsc, CdcDsp.command.Write3dsTsc.Request, CdcDsp.command.Write3dsTsc.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    pub const IsHeadphoneConnected = ipc.Command(Id, .is_headphone_connected, CdcDsp.command.IsHeadphoneConnected.Request, CdcDsp.command.IsHeadphoneConnected.Response);
    /// Straight wrapper of cdc:DSP, forwards it's result.
    ///
    /// May also fail with 0xc8a0a401 (dsp not active)
    pub const ForceHeadphoneOutput = ipc.Command(Id, .force_headphone_output, CdcDsp.command.ForceHeadphoneOutput.Request, CdcDsp.command.ForceHeadphoneOutput.Response);

    /// Cannot fail
    pub const IsOccupied = ipc.Command(Id, .is_occupied, void, bool);

    pub const Id = enum(u16) {
        recv = 0x0001,
        is_recv_ready = 0x0002,
        send = 0x0003,
        is_send_empty = 0x0004,

        write_data_transfer = 0x0005,
        read_data_transfer = 0x0006,

        send_semaphore = 0x0007,
        recv_semaphore = 0x0008,
        clear_semaphore = 0x0009,
        disable_semaphore_interrupt = 0x000a,
        is_semaphore_requested = 0x000b,

        get_mapped_data_address = 0x000c,

        write_channel = 0x000d,
        read_channel = 0x000e,
        get_channel_unused_capacity = 0x000f,
        try_read_channel = 0x0010,

        load_component = 0x0011,
        unload_component = 0x0012,

        flush_data_cache = 0x0013,
        invalidate_data_cache = 0x0014,
        register_interrupt_events = 0x0015,
        get_semaphore_send_event = 0x0016,
        set_sent_semaphore = 0x0017,
        get_physical_address = 0x0018,
        // Doesn't exist in latest? When was it removed?
        // get_virtual_address = 0x0019,

        set_i2s1_iir_filters = 0x001a,
        set_i2s2_iir_filters = 0x001b,
        set_sink_iir_filters = 0x001c,
        read_3ds_tsc = 0x001d,
        write_3ds_tsc = 0x001e,
        is_headphone_connected = 0x001f,
        force_headphone_output = 0x0020,
        is_occupied = 0x0021,
    };
};

const Dsp = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = horizon.ServiceManager;

const CdcDsp = horizon.services.cdc.Dsp;
