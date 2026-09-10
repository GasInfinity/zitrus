//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/DSP_Services

pub const service = "dsp::DSP";

session: ClientSession,

pub fn open(srv: ServiceManager) !Dsp {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(dsp: Dsp) void {
    dsp.session.close();
}

pub const command = struct {
    pub const Recv = ipc.Command(Id, .recv, struct { stream: u2 }, struct { data: u16 });
    pub const RecvReady = ipc.Command(Id, .recv_ready, struct { stream: u2 }, struct { ready: bool });
    pub const Send = ipc.Command(Id, .send, struct { stream: u2, data: u16 }, struct {});
    pub const SendReady = ipc.Command(Id, .send_ready, struct { stream: u2 }, struct { ready: bool });

    pub const SetSemaphore = ipc.Command(Id, .set_semaphore, struct { value: u16 }, struct {});
    pub const GetSemaphore = ipc.Command(Id, .get_semaphore, struct {}, struct { value: u16 });
    pub const ClearSemaphore = ipc.Command(Id, .clear_semaphore, struct { mask: u32 }, struct {});
    pub const MaskSemaphore = ipc.Command(Id, .mask_semaphore, struct { mask: u32 }, struct {});
    pub const IsSemaphoreRequested = ipc.Command(Id, .is_semaphore_requested, struct { mask: u32 }, struct {});

    pub const LoadComponent = ipc.Command(Id, .load_component, struct {
        size: u32,
        program_mask: u32,
        data_mask: u32,
        buffer: ipc.Mapped(.r),
    }, struct { loaded: bool, buffer: ipc.Mapped(.r) });
    pub const UnloadComponent = ipc.Command(Id, .unload_component, struct {}, struct {});

    pub const FlushDataCache = ipc.Command(Id, .flush_data_cache, struct { address: u32, size: u32, process: horizon.Process }, struct {});
    pub const InvalidateDataCache = ipc.Command(Id, .invalidate_data_cache, struct { address: u32, size: u32, process: horizon.Process }, struct {});
    pub const RegisterInterruptEvents = ipc.Command(Id, .register_interrupt_events, struct { irq: u32, channel: u32, event: horizon.Event }, struct {});
    pub const GetPhysicalAddress = ipc.Command(Id, .get_virtual_address, struct { virtual: u32 }, struct { physical: u32 });
    pub const GetVirtualAddress = ipc.Command(Id, .get_virtual_address, struct { physical: u32 }, struct { virtual: u32 });
    pub const ForceHeadphoneOutput = ipc.Command(Id, .force_headphone_output, struct { force: bool }, struct {});
    pub const IsDspOccupied = ipc.Command(Id, .is_dsp_occupied, struct {}, struct { occupied: bool });

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
        set_iir_filter_i2s1,
        set_iir_filter_i2s2,
        set_iir_filter_eq,
        read_multi,
        write_multi,
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
