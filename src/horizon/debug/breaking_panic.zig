//! Minimal panic alternative which only calls `svcBreak`

pub fn call(_: []const u8, _: ?usize) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn sentinelMismatch(_: anytype, _: anytype) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn unwrapError(_: anyerror) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn outOfBounds(_: usize, _: usize) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn startGreaterThanEnd(_: usize, _: usize) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn inactiveUnionField(_: anytype, _: anytype) noreturn {
    @branchHint(.cold);
    horizon.breakExecution(.panic);
}

pub fn sliceCastLenRemainder(_: usize) noreturn {
    @branchHint(.cold);
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

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
