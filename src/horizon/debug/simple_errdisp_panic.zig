//! Alternative minimal panic alternative which only calls `errdisp.throw`
//! without producing a stacktrace.

pub fn call(message: []const u8, return_address: ?usize) noreturn {
    @branchHint(.cold);

    const errdisp = blk: for (0..20) |_| {
        const errdisp = horizon.ErrorDisplayManager.open() catch {
            horizon.sleepThread(1 * std.time.ns_per_ms);
            continue;
        };
        break :blk errdisp;
    } else horizon.breakExecution(.panic);
    defer errdisp.close();

    errdisp.sendSetUserString(message) catch {};
    errdisp.sendThrow(.{
        .type = .generic,
        .revision_high = 0x00,
        .revision_low = 0x00,
        .result_code = .ztr_panic,
        .pc_address = return_address orelse @returnAddress(),
        .process_id = @intFromEnum(horizon.getProcessId(.current).value), // NOTE: cannot fail as current is always valid.
        .title_id = 0x0,
        .applet_title_id = 0x0,
        .data = undefined,
    }) catch horizon.breakExecution(.panic);
    while (true) horizon.breakExecution(.panic);
}

pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
    @branchHint(.cold);
    _ = found;
    call("sentinel mismatch", null);
}

pub fn unwrapError(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = &err;
    call("attempt to unwrap error", null);
}

pub fn outOfBounds(index: usize, len: usize) noreturn {
    @branchHint(.cold);
    _ = index;
    _ = len;
    call("index out of bounds", null);
}

pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
    @branchHint(.cold);
    _ = start;
    _ = end;
    call("start index is larger than end index", null);
}

pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
    @branchHint(.cold);
    _ = accessed;
    call("access of inactive union field", null);
}

pub fn sliceCastLenRemainder(src_len: usize) noreturn {
    @branchHint(.cold);
    _ = src_len;
    call("slice length does not divide exactly into destination elements", null);
}

pub fn reachedUnreachable() noreturn {
    @branchHint(.cold);
    call("reached unreachable code", null);
}

pub fn unwrapNull() noreturn {
    @branchHint(.cold);
    call("attempt to use null value", null);
}

pub fn castToNull() noreturn {
    @branchHint(.cold);
    call("cast causes pointer to be null", null);
}

pub fn incorrectAlignment() noreturn {
    @branchHint(.cold);
    call("incorrect alignment", null);
}

pub fn invalidErrorCode() noreturn {
    @branchHint(.cold);
    call("invalid error code", null);
}

pub fn unexpectedErrorCode(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = &err;
    call("unexpected error code", null);
}

pub fn integerOutOfBounds() noreturn {
    @branchHint(.cold);
    call("integer does not fit in destination type", null);
}

pub fn integerOverflow() noreturn {
    @branchHint(.cold);
    call("integer overflow", null);
}

pub fn shlOverflow() noreturn {
    @branchHint(.cold);
    call("left shift overflowed bits", null);
}

pub fn shrOverflow() noreturn {
    @branchHint(.cold);
    call("right shift overflowed bits", null);
}

pub fn divideByZero() noreturn {
    @branchHint(.cold);
    call("division by zero", null);
}

pub fn exactDivisionRemainder() noreturn {
    @branchHint(.cold);
    call("exact division produced remainder", null);
}

pub fn integerPartOutOfBounds() noreturn {
    @branchHint(.cold);
    call("integer part of floating point value out of bounds", null);
}

pub fn corruptSwitch() noreturn {
    @branchHint(.cold);
    call("switch on corrupt value", null);
}

pub fn shiftRhsTooBig() noreturn {
    @branchHint(.cold);
    call("shift amount is greater than the type size", null);
}

pub fn invalidEnumValue() noreturn {
    @branchHint(.cold);
    call("invalid enum value", null);
}

pub fn forLenMismatch() noreturn {
    @branchHint(.cold);
    call("for loop over objects with non-equal lengths", null);
}

pub fn copyLenMismatch() noreturn {
    @branchHint(.cold);
    call("source and destination have non-equal lengths", null);
}

pub fn memcpyAlias() noreturn {
    @branchHint(.cold);
    call("@memcpy arguments alias", null);
}

pub fn noreturnReturned() noreturn {
    @branchHint(.cold);
    call("'noreturn' function returned", null);
}

pub fn loadUninstantiableType() noreturn {
    call("attempt to load uninstantiable type", null);
}

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
