//! Alternative minimal panic alternative which only calls `errdisp.throw`
//! without producing a stacktrace.

pub fn call(message: []const u8, return_address: ?usize) noreturn {
    @branchHint(.cold);

    const errdisp = horizon.ErrorDisplayManager.open() catch horizon.breakExecution(.panic);
    defer errdisp.close();

    errdisp.sendSetUserString(message) catch {};
    errdisp.sendThrow(.{
        .type = .failure,
        .revision_high = 0x00,
        .revision_low = 0x00,
        .result_code = .failure,
        .pc_address = return_address orelse @returnAddress(),
        .process_id = @intFromEnum(horizon.getProcessId(.current).value), // NOTE: cannot fail as current is always valid.
        .title_id = 0x0,
        .applet_title_id = 0x0,
        .data = .{ .failure = .{
            .message = blk: {
                var buffer: [0x60]u8 = undefined;
                const truncated_len = @min(buffer.len - 1, message.len); // -1 as we need a NUL-terminator
                @memcpy(buffer[0..truncated_len], message[0..truncated_len]);
                buffer[truncated_len] = 0;
                break :blk buffer;
            },
        } },
    }) catch horizon.breakExecution(.panic);
    while (true) horizon.breakExecution(.panic);
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

pub fn integerOutOfBounds() noreturn {
    call("integer does not fit in destination type", @returnAddress());
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

pub fn copyLenMismatch() noreturn {
    call("source and destination have non-equal lengths", @returnAddress());
}

pub fn memcpyAlias() noreturn {
    call("@memcpy arguments alias", @returnAddress());
}

pub fn noreturnReturned() noreturn {
    call("'noreturn' function returned", @returnAddress());
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
