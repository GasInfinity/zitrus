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
        check_semaphore_request,
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
