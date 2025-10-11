//! Replacement for std.debug (print) mainly

/// Print to the debug console. Intended for use in "printf
/// debugging". Use `std.log` functions for proper logging.
///
/// Uses a 64-byte buffer for formatted printing which is flushed before this
/// function returns.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    var debug_writer = horizon.outputDebugWriter(&buf);
    debug_writer.print(fmt, args) catch unreachable;
    debug_writer.flush() catch unreachable;
}

const std = @import("std");
const zitrus = @import("zitrus");

const horizon = zitrus.horizon;
