handles: Hid.Handles,
shm_memory_data: *align(horizon.heap.page_size) Hid.Shared,

pub fn init(hid: Hid) !Input {
    var handles = try hid.sendGetIPCHandles();
    errdefer handles.deinit();

    const shm_memory_data = try horizon.heap.non_thread_safe_shared_memory_address_allocator.alloc(@sizeOf(Hid.Shared), .fromByteUnits(4096));
    errdefer horizon.heap.non_thread_safe_shared_memory_address_allocator.free(shm_memory_data);

    try handles.shm.map(@alignCast(shm_memory_data.ptr), .r, .dont_care);
    return .{
        .handles = handles,
        .shm_memory_data = std.mem.bytesAsValue(Hid.Shared, shm_memory_data),
    };
}

pub fn deinit(input: *Input) void {
    input.handles.shm.unmap(@ptrCast(input.shm_memory_data));
    horizon.heap.non_thread_safe_shared_memory_address_allocator.free(std.mem.asBytes(input.shm_memory_data));
    input.handles.deinit();
    input.* = undefined;
}

pub fn pollPad(input: Input) Hid.Pad.Entry {
    const pad: *const Hid.Pad = &input.shm_memory_data.pad;
    return pad.entries[pad.index];
}

pub fn pollTouch(input: Input) Hid.Touch.State {
    const touch: *const Hid.Touch = &input.shm_memory_data.touch;
    return touch.entries[touch.index];
}

const Input = @This();
const Hid = horizon.services.Hid;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
