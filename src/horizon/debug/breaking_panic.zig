//! Minimal panic alternative which only calls `svcBreak`

pub fn call(_: []const u8, _: ?usize) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
    @branchHint(.cold);
    _ = found;
    horizon.breakExecution(.panic);
}

pub fn unwrapError(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = &err;
    horizon.breakExecution(.panic);
}

pub fn outOfBounds(index: usize, len: usize) noreturn {
    @branchHint(.cold);
    _ = index;
    _ = len;
    horizon.breakExecution(.panic);
}

pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
    @branchHint(.cold);
    _ = start;
    _ = end;
    horizon.breakExecution(.panic);
}

pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
    @branchHint(.cold);
    _ = accessed;
    horizon.breakExecution(.panic);
}

pub fn sliceCastLenRemainder(src_len: usize) noreturn {
    @branchHint(.cold);
    _ = src_len;
    horizon.breakExecution(.panic);
}

pub fn reachedUnreachable() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn unwrapNull() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn castToNull() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn incorrectAlignment() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn invalidErrorCode() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn unexpectedErrorCode(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = &err;
    horizon.breakExecution(.panic);
}

pub fn integerOutOfBounds() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn integerOverflow() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn shlOverflow() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn shrOverflow() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn divideByZero() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn exactDivisionRemainder() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn integerPartOutOfBounds() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn corruptSwitch() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn shiftRhsTooBig() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn invalidEnumValue() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn forLenMismatch() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn copyLenMismatch() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn memcpyAlias() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn noreturnReturned() noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn loadUninstantiableType() noreturn {
    horizon.breakExecution(.panic);
}

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
