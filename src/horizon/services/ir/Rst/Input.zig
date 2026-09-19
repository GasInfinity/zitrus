//! Mid-level abstraction around IrRst state.
//!
//! Allows polling current input state.

handles: IrRst.Handles,
shm_memory_data: *align(horizon.heap.page_size) IrRst.Shared,

pub fn init(irrst: IrRst) !Input {
    const shm_memory_data = horizon.heap.allocShared(@sizeOf(IrRst.Shared));
    return try .initAddress(irrst, @ptrCast(shm_memory_data));
}

pub fn initAddress(irrst: IrRst, shared_address: *align(horizon.heap.page_size) IrRst.Shared) !Input {
    var handles = try irrst.sendGetHandles();
    errdefer handles.close();

    try handles.shm.map(@ptrCast(shared_address), .r, .dont_care);
    errdefer handles.shm.unmap(@ptrCast(shared_address));

    return .{
        .handles = handles,
        .shm_memory_data = shared_address,
    };
}

pub fn deinit(input: *Input) void {
    input.handles.shm.unmap(@ptrCast(input.shm_memory_data));
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
