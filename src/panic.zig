// FIXME: check for recursve panics

pub fn throw(msg: []const u8, ret_trace: ?*std.builtin.StackTrace) noreturn {
    @branchHint(.cold);
    defer {
        while (true) {
            horizon.breakExecution(.panic);
        }
        horizon.exit();
    }

    var errdisp = ErrorDisplayManager.init() catch {
        return;
    };
    defer errdisp.deinit();

    var stack_trace_buffer: [1024]u8 = undefined;
    var stack_trace_stream = std.io.fixedBufferStream(&stack_trace_buffer);
    const stack_trace_writer = stack_trace_stream.writer();

    const last_trace_pc = if (ret_trace) |trace| lt: {
        const traces = @min(trace.index, trace.instruction_addresses.len);
        // TODO: Use dwarf debug info or thats too overkill...?

        _ = stack_trace_stream.write("Return trace:\n") catch unreachable;
        for (0..traces) |i| {
            const pc = trace.instruction_addresses[i];

            std.fmt.format(stack_trace_writer, "at 0x{X}\n", .{pc}) catch break;
        }
        break :lt (if (traces > 0) trace.instruction_addresses[0] else 0xAAAAAAAA);
    } else lt: {
        _ = stack_trace_stream.write("Unable to print return trace.") catch unreachable;
        break :lt 0xAAAAAAAA;
    };

    errdisp.sendSetUserString(stack_trace_stream.getWritten()) catch {};

    const process_id: u32 = switch (horizon.getProcessId(.current)) {
        .success => |s| s.value,
        .failure => |_| 0xDEADCAFE,
    };

    errdisp.sendThrow(ErrorDisplayManager.FatalErrorInfo{
        .type = .failure,
        .revision_high = 0x00,
        .revision_low = 0x00,
        .result_code = .{},
        .pc_address = last_trace_pc,
        .process_id = process_id,
        .title_id = 0x0,
        .applet_title_id = 0x0,
        .data = .{ .failure = .{
            .message = if (msg.len > 0x59) (msg[0..0x5F].* ++ .{0}) else buf: {
                var buffer: [0x60]u8 = undefined;
                @memcpy(buffer[0..msg.len], msg);
                buffer[msg.len] = 0x00;
                break :buf buffer;
            },
        } },
    }) catch {
        // Bad luck? Try next time :D!
    };
}

pub fn call(msg: []const u8, return_address: ?usize) noreturn {
    @branchHint(.cold);
    var stack_frames: [32]usize = @splat(0x00);
    var panic_trace: std.builtin.StackTrace = std.builtin.StackTrace{
        .index = 0,
        .instruction_addresses = &stack_frames,
    };

    std.debug.captureStackTrace((return_address orelse @returnAddress()), &panic_trace);
    throw(msg, &panic_trace);
}

pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
    _ = found;
    call("sentinel mismatch", @returnAddress());
}

pub fn unwrapError(err: anyerror) noreturn {
    _ = &err;
    call("attempt to unwrap error", @returnAddress());
}

pub fn outOfBounds(index: usize, len: usize) noreturn {
    _ = index;
    _ = len;
    call("index out of bounds", @returnAddress());
}

pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
    _ = start;
    _ = end;
    call("start index is larger than end index", @returnAddress());
}

pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
    _ = accessed;
    call("access of inactive union field", @returnAddress());
}

pub fn sliceCastLenRemainder(src_len: usize) noreturn {
    _ = src_len;
    call("slice length does not divide exactly into destination elements", @returnAddress());
}

pub fn reachedUnreachable() noreturn {
    call("reached unreachable code", @returnAddress());
}

pub fn unwrapNull() noreturn {
    call("attempt to use null value", @returnAddress());
}

pub fn castToNull() noreturn {
    call("cast causes pointer to be null", @returnAddress());
}

pub fn incorrectAlignment() noreturn {
    call("incorrect alignment", @returnAddress());
}

pub fn invalidErrorCode() noreturn {
    call("invalid error code", @returnAddress());
}

pub fn castTruncatedData() noreturn {
    call("integer cast truncated bits", @returnAddress());
}

pub fn negativeToUnsigned() noreturn {
    call("attempt to cast negative value to unsigned integer", @returnAddress());
}

pub fn integerOverflow() noreturn {
    call("integer overflow", @returnAddress());
}

pub fn shlOverflow() noreturn {
    call("left shift overflowed bits", @returnAddress());
}

pub fn shrOverflow() noreturn {
    call("right shift overflowed bits", @returnAddress());
}

pub fn divideByZero() noreturn {
    call("division by zero", @returnAddress());
}

pub fn exactDivisionRemainder() noreturn {
    call("exact division produced remainder", @returnAddress());
}

pub fn integerPartOutOfBounds() noreturn {
    call("integer part of floating point value out of bounds", @returnAddress());
}

pub fn corruptSwitch() noreturn {
    call("switch on corrupt value", @returnAddress());
}

pub fn shiftRhsTooBig() noreturn {
    call("shift amount is greater than the type size", @returnAddress());
}

pub fn invalidEnumValue() noreturn {
    call("invalid enum value", @returnAddress());
}

pub fn forLenMismatch() noreturn {
    call("for loop over objects with non-equal lengths", @returnAddress());
}

pub const memcpyLenMismatch = copyLenMismatch;

pub fn copyLenMismatch() noreturn {
    call("source and destination have non-equal lengths", @returnAddress());
}

pub fn memcpyAlias() noreturn {
    call("@memcpy arguments alias", @returnAddress());
}

pub fn noreturnReturned() noreturn {
    call("'noreturn' function returned", @returnAddress());
}

const builtin = @import("builtin");

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ErrorDisplayManager = zitrus.horizon.ErrorDisplayManager;
