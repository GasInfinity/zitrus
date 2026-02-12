//! A `std.Thread`-compatible API
pub const default_stack_size = 16 * 1024;
pub const Id = u32;

threadlocal var tls_id: ?u32 = 0;

pub fn getCurrentId() u32 {
    return tls_id orelse {
        const tid = @intFromEnum(horizon.Thread.current.id());
        tls_id = tid;
        return tid;
    };
}

pub fn getCpuCount() !usize {
    return @bitCast(horizon.getCpuCount());
}

pub fn yield() std.Thread.YieldError!void {
    horizon.sleepThread(0);
}

pub const Completion = struct {
    pub const State = std.atomic.Value(enum(u8) { running, completed, detached });

    thread: horizon.Thread,
    state: State,
    gpa: std.mem.Allocator,
    all_memory_alignment: std.mem.Alignment,
    all_memory: []u8,

    pub fn deinit(compl: Completion) void {
        // XXX: This is INVALID! We cannot free ourselves while detached
        // If we do so we enter UB terrirory, as we would be freeing the stack we're currently on.
        // We don't even know if the function calls other ones after freeing the memory so either:
        //  - We ignore this a YOLO it (What we have currently, risking a panic/UB)
        //  - We leak the memory? We obviously don't want that!
        //  - We find some other way? How? We can't munmap as in normal OSes, we DON'T have it.
        compl.gpa.rawFree(compl.all_memory, compl.all_memory_alignment, @returnAddress());
    }
};

completion: *Completion,

const bad_fn_ret = "expected return type of startFn to be 'u8', 'noreturn', '!noreturn', 'void', or '!void'";

pub fn spawn(config: std.Thread.SpawnConfig, comptime f: anytype, args: anytype) !Impl {
    const gpa = config.allocator orelse @panic("We need an allocator to spawn a Thread!");

    const Args = @TypeOf(args);
    const Instance = struct {
        fn_args: Args,
        tls_data: [*]u8,
        completion: Completion,

        fn entry(ctx: ?*anyopaque) callconv(.c) noreturn {
            defer horizon.exitThread();

            const inst: *@This() = @ptrCast(@alignCast(ctx));
            horizon.tls.get().state.tp = @ptrFromInt(@intFromPtr(inst.tls_data) - 8); // NOTE: Yes, the ABI says data starts at $tp + 8
            defer switch (inst.completion.state.swap(.completed, .seq_cst)) {
                .running => {},
                .completed => unreachable,
                .detached => inst.completion.deinit(),
            };

            switch (@typeInfo(@typeInfo(@TypeOf(f)).@"fn".return_type.?)) {
                .noreturn, .void => @call(.auto, f, inst.fn_args),
                .int => |info| {
                    if (info.bits != 8) @compileError(bad_fn_ret);

                    _ = @call(.auto, f, inst.fn_args);
                },
                .error_union => |info| {
                    if (info.payload != void) @compileError(bad_fn_ret);

                    @call(.auto, f, inst.fn_args) catch |err| {
                        std.debug.print("error: {s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
                    };
                },
                else => @compileError(bad_fn_ret),
            }
        }
    };

    const tls_size = horizon.tls.size();
    const tls_alignment = horizon.tls.alignment();
    const min_alingment: std.mem.Alignment = .fromByteUnits(@max(@alignOf(Instance), tls_alignment, 8));

    const needed_size: usize, const tls_offset: usize, const stack_offset = blk: {
        var needed: usize = @sizeOf(Instance);

        const tls = std.mem.alignForward(usize, needed, tls_alignment);
        needed = tls + tls_size;

        const stack = std.mem.alignForward(usize, needed, 8);
        needed = stack + config.stack_size;

        break :blk .{
            needed,
            tls,
            stack,
        };
    };

    const all_memory = (gpa.rawAlloc(needed_size, min_alingment, @returnAddress()) orelse return error.OutOfMemory)[0..needed_size];
    errdefer gpa.rawFree(all_memory, min_alingment, @returnAddress());

    const instance: *Instance = @ptrCast(@alignCast(all_memory[0..@sizeOf(Instance)]));

    const tls_data: []u8 = all_memory[tls_offset..][0..tls_size];
    const tls_data_image = horizon.tls.dataImage();
    @memcpy(tls_data[0..tls_data_image.len], tls_data_image);

    const stack = all_memory[stack_offset..][0..config.stack_size];

    instance.* = .{
        .fn_args = args,
        .tls_data = tls_data.ptr,
        .completion = .{
            .state = .init(.running),
            .thread = undefined, // to be set literally below
            .gpa = gpa,
            .all_memory_alignment = min_alingment,
            .all_memory = all_memory,
        },
    };

    instance.completion.thread = try .create(Instance.entry, instance, stack.ptr + stack.len, .lowest, .any);

    return .{ .completion = &instance.completion };
}

pub const ThreadHandle = horizon.Thread;

pub fn getHandle(impl: Impl) ThreadHandle {
    return impl.completion.thread;
}

// NOTE: see above!
pub fn detach(impl: Impl) void {
    impl.completion.thread.close();

    switch (impl.completion.state.swap(.detached, .seq_cst)) {
        .running => {},
        .completed => impl.completion.deinit(),
        .detached => unreachable,
    }
}

pub fn join(impl: Impl) void {
    impl.completion.thread.wait(.none) catch unreachable;
    impl.completion.thread.close();
    std.debug.assert(impl.completion.state.load(.seq_cst) == .completed);
    impl.completion.deinit();
}

test spawn {
    if (builtin.os.tag != .@"3ds") return error.SkipZigTest;
    const gpa = std.testing.allocator;

    var a: std.atomic.Value(u32) = .init(69);

    const thread: std.Thread = try .spawn(.{
        .allocator = gpa,
    }, (struct {
        fn aTest(v: *std.atomic.Value(u32)) void {
            v.store(9000, .monotonic);
        }
    }).aTest, .{&a});
    thread.join();

    try std.testing.expectEqual(9000, a.load(.monotonic));
}

const Impl = @This();
const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
