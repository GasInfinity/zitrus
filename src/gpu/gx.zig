// TODO: We could maybe ziggify this more?
// FIXME: Ok, this is specific to horizon and the gsp module, why is it toplevel (a.k.a: freestanding)?
pub const Command = extern struct {
    pub const Id = enum(u8) { request_dma, process_command_list, memory_fill, display_transfer, texture_copy, flush_cache_regions };

    pub const Header = packed struct(u32) {
        command_id: Id,
        _unused0: u8 = 0,
        stop_processing_queue: bool = false,
        _unused1: u7 = 0,
        fail_if_any: bool = false,
        _unused2: u7 = 0,
    };

    pub const DmaRequest = extern struct {
        source: *anyopaque,
        destination: *anyopaque,
        size: usize,
        _unused0: [3]u32 = @splat(0),
        flush: u32,
    };

    pub const ProcessCommandList = extern struct {
        address: *align(8) anyopaque,
        size: usize,
        update_results: u32,
        _unused0: [3]u32 = @splat(0),
        flush: u32,
    };

    pub const MemoryFill = extern struct {
        pub const Buffer = extern struct {
            pub const none: Buffer = .{ .start = null, .value = 0, .end = null };

            start: ?*anyopaque,
            value: u32,
            end: ?*anyopaque,
        };

        buffers: [2]Buffer,
        controls: [2]gpu.MemoryFill.Control,
    };

    pub const DisplayTransfer = extern struct {
        source: *anyopaque,
        destination: *anyopaque,
        source_dimensions: gpu.Dimensions,
        destination_dimensions: gpu.Dimensions,
        flags: gpu.TransferEngine.Flags,
        _unused0: [2]u32 = @splat(0),
    };

    pub const TextureCopy = extern struct {
        source: *anyopaque,
        destination: *anyopaque,
        dimensions: gpu.Dimensions,
        source_line_gap: gpu.Dimensions,
        destination_line_gap: gpu.Dimensions,
        flags: gpu.TransferEngine.Flags,
        _unused0: u32 = 0,
    };

    pub const FlushCacheRegions = extern struct {
        pub const Buffer = extern struct {
            address: *anyopaque,
            size: usize,
        };

        buffers: [3]Buffer,
        _unused0: u32 = 0,
    };

    header: Header,
    data: extern union {
        dma_request: DmaRequest,
        process_command_list: ProcessCommandList,
        memory_fill: MemoryFill,
        display_transfer: DisplayTransfer,
        texture_copy: TextureCopy,
        flush_cache_regions: FlushCacheRegions,
    },

    pub const MemoryFillParameters = struct {
        pub const Value = union(gpu.MemoryFill.FillWidth) {
            @"16": u16,
            @"24": u24,
            @"32": u32,
        };

        pub const Buffer = struct { slice: []u8, value: Value };

        buffers: [2]?Buffer,
    };

    pub fn initMemoryFill(params: MemoryFillParameters, stop_queue: bool, fail_if_any: bool) Command {
        var fill: MemoryFill = std.mem.zeroes(MemoryFill);

        inline for (0..2) |i| {
            if (params.buffers[i]) |buf| {
                fill.buffers[i].start = buf.slice.ptr;
                fill.buffers[i].value = switch (buf.value) {
                    inline else => |v| v,
                };
                fill.buffers[i].end = buf.slice.ptr + buf.slice.len;
                fill.controls[i].busy = true;
                fill.controls[i].fill_width = std.meta.activeTag(buf.value);
            }
        }

        return .{
            .header = .{
                .command_id = .memory_fill,
                .stop_processing_queue = stop_queue,
                .fail_if_any = fail_if_any,
            },
            .data = .{ .memory_fill = fill },
        };
    }
};

const std = @import("std");

const zitrus = @import("zitrus");
const gpu = zitrus.gpu;
