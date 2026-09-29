//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/DSP_Services

pub const service = "dsp::DSP";

session: ClientSession,

pub const Stream = enum(u2) { _ };

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const Recv = ipc.Command(Id, .recv, u2, u16);
    pub const RecvReady = ipc.Command(Id, .recv_ready, u2, bool);
    pub const Send = ipc.Command(Id, .send, struct {
        stream: u2,
        data: u16,
    }, void);
    pub const SendReady = ipc.Command(Id, .send_ready, u2, bool);

    pub const SetSemaphore = ipc.Command(Id, .set_semaphore, u16, void);
    pub const GetSemaphore = ipc.Command(Id, .get_semaphore, void, u16);
    pub const ClearSemaphore = ipc.Command(Id, .clear_semaphore, u32, void);
    pub const MaskSemaphore = ipc.Command(Id, .mask_semaphore, u32, void);
    pub const IsSemaphoreRequested = ipc.Command(Id, .is_semaphore_requested, u32, bool);

    pub const LoadComponent = ipc.Command(Id, .load_component, struct {
        size: u32,
        program_mask: u32,
        data_mask: u32,
        buffer: ipc.Mapped(u8, .r),
    }, struct { loaded: bool, buffer: ipc.Mapped(u8, .r) });
    pub const UnloadComponent = ipc.Command(Id, .unload_component, void, void);

    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct { address: u32, size: u32, process: horizon.Process }, void);
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct { address: u32, size: u32, process: horizon.Process }, void);
    pub const RegisterInterruptEvents = ipc.Command(Id, .register_interrupt_events, struct { irq: u32, channel: u32, event: horizon.Event }, void);

    pub const GetPhysicalAddress = ipc.Command(Id, .get_physical_address, u32, u32);
    pub const GetVirtualAddress = ipc.Command(Id, .get_virtual_address, u32, u32);
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
    pub const ForceHeadphoneOutput = ipc.Command(Id, .force_headphone_output, CdcDsp.command.ForceHeadphoneOutput.Request, CdcDsp.command.ForceHeadphoneOutput.Response);
    pub const IsDspOccupied = ipc.Command(Id, .is_dsp_occupied, void, bool);

    pub const Id = enum(u16) {
        recv = 0x0001,
        recv_ready,
        send,
        send_ready,
        send_fifo,
        recv_fifo,
        set_semaphore,
        get_semaphore,
        clear_semaphore,
        mask_semaphore,
        is_semaphore_requested,
        convert_process_address_from_dsp_dram,
        write_process_pipe,
        read_pipe,
        get_pipe_readable_size,
        try_read_pipe,
        load_component,
        unload_component,
        flush_data_cache,
        invalidate_data_cache,
        register_interrupt_events,
        get_semaphore_event_handle,
        set_semaphore_mask,
        get_physical_address,
        get_virtual_address,
        set_i2s1_iir_filters,
        set_i2s2_iir_filters,
        set_sink_iir_filters,
        read_3ds_tsc,
        write_3ds_tsc,
        get_headphone_status,
        force_heaphone_output,
        is_dsp_occupied,
    };
};

const Dsp = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const MemoryBlock = horizon.MemoryBlock;
const ServiceManager = horizon.ServiceManager;

const CdcDsp = horizon.services.cdc.Dsp;
