//! A `std.process`-compatible API

pub const can_spawn = false;
pub const can_replace = false;

pub fn getBaseAddress() usize {
    return @intFromPtr(@extern(*anyopaque, .{ .name = "__base__" }));
}

pub fn totalSystemMemory() process.TotalSystemMemoryError!u64 {
    return switch (horizon.getProcessInfo(.current, .memory_region).cases()) {
        .success => |r| blk: {
            const info: horizon.Process.Capability.KernelFlags = @bitCast(@as(u32, @truncate(@as(u64, @bitCast(r.value)))));
            const kernel_config = horizon.memory.kernel_config;

            break :blk switch (info.memory_type) {
                .base => kernel_config.base_total_memory,
                .system => kernel_config.system_total_memory,
                .application => kernel_config.application_total_memory,
                _ => return error.UnknownTotalSystemMemory,
            };
        },
        // XXX: emulators (e.g Azahar) don't implement getProcessInfo(19) so assume app
        .failure => horizon.memory.kernel_config.application_total_memory,
    };
}

// NOTE: (un)lockMemory* is a NOP instead of an error as everything is commited and in RAM always.
pub fn lockMemory(_: []align(std.heap.page_size_min) const u8, _: process.LockMemoryOptions) process.LockMemoryError!void {}
pub fn unlockMemory(_: []align(std.heap.page_size_min) const u8) process.UnlockMemoryError!void {}
pub fn lockMemoryAll(_: process.LockMemoryAllOptions) process.LockMemoryError!void {}
pub fn unlockMemoryAll() process.UnlockMemoryError!void {}

pub fn protectMemory(memory: []align(std.heap.page_size_min) u8, protection: process.MemoryProtection) process.ProtectMemoryError!void {
    // NOTE: We need to go through these hoops as controlProcessMemory doesn't support the `.current` alias
    const global = struct {
        var current_process: std.atomic.Value(horizon.Process) = .init(.none);

        pub fn get() !horizon.Process {
            const initial = current_process.load(.monotonic);
            if (initial != horizon.Process.none) return initial;

            const duped = horizon.Process.current.dupe() catch return error.OutOfMemory;

            return if (current_process.cmpxchgStrong(.none, duped, .monotonic, .monotonic)) |already_duped| blk: {
                duped.close();
                break :blk already_duped;
            } else duped;
        }
    };

    try (try global.get()).controlMemory(.protect, memory.ptr, null, memory.len, .{
        .read = protection.read,
        .write = protection.write,
        .execute = protection.execute,
    });
}

pub fn abort() noreturn {
    @panic("aborted");
}

// NOTE: `exit` is only valid on sysmodules.
// Applications must notify APT/NS so the user can return to home!
pub fn exit(status: u8) noreturn {
    _ = status;
    horizon.exit();
}

// NOTE: We're using std to test that we didn't break anything
var test_page: [std.heap.page_size_max]u8 align(std.heap.page_size_max) = undefined;

test getBaseAddress {
    _ = std.process.getBaseAddress();
}

test totalSystemMemory {
    _ = try std.process.totalSystemMemory();
}

test lockMemory {
    try std.process.lockMemory(&test_page, .{});
    try std.process.unlockMemory(&test_page);
}

test lockMemoryAll {
    try std.process.lockMemoryAll(.{
        .current = true,
    });
    try std.process.unlockMemoryAll();
}

test protectMemory {
    try std.process.protectMemory(&test_page, .{});
    try std.process.protectMemory(&test_page, .{ .read = true, .write = true });
}

// literally a page full of `bx lr` instructions
var bx_lr: [@divExact(std.heap.page_size_max, @sizeOf(u32))]u32 align(std.heap.page_size_max) = @splat(0xE12FFF1E);

test "protectMemory: executing read-only memory" {
    if (builtin.os.tag != .@"3ds") return error.SkipZigTest;
    try std.process.protectMemory(@ptrCast(&bx_lr), .{ .read = true, .execute = true });

    const doNothing: *const fn () callconv(.c) void = @ptrCast(@alignCast(&bx_lr));
    doNothing();

    try std.process.protectMemory(@ptrCast(&bx_lr), .{ .read = true, .write = true });
}

const builtin = @import("builtin");
const std = @import("std");
const process = std.process;

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
