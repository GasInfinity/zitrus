//! Mid-level abstraction around IrRst state.
//!
//! Allows polling current input state.

handles: IrRst.Handles,
shm_memory_data: *align(horizon.heap.page_size) IrRst.Shared,

pub fn init(hid: IrRst) !Input {
    var handles = try hid.sendGetHandles();
    errdefer handles.close();

    const shm_memory_data = try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(@sizeOf(IrRst.Shared), .fromByteUnits(4096));
    errdefer horizon.heap.non_thread_safe_shared_memory_address_allocator.free(shm_memory_data);

    try handles.shm.map(@alignCast(shm_memory_data.ptr), .r, .dont_care);
    return .{
        .handles = handles,
        .shm_memory_data = @ptrCast(shm_memory_data),
    };
}

pub fn deinit(input: *Input) void {
    input.handles.shm.unmap(@ptrCast(input.shm_memory_data));
    horizon.heap.non_thread_safe_shared_memory_address_allocator.free(@ptrCast(input.shm_memory_data));
    input.handles.close();
    input.* = undefined;
}

pub fn pollPad(input: Input) IrRst.Pad.Entry {
    const pad: *const IrRst.Pad = &input.shm_memory_data.pad;
    return pad.entries[pad.index];
}

const Input = @This();
const IrRst = horizon.services.IrRst;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
