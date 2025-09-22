/// Gets the `ThreadLocalStorage` of the current thread.
///
/// `zitrus` reserves some needed state and storage
/// for `threadlocal` variables.
pub export fn ztrHorGetThreadLocalStorage() *tls.ThreadLocalStorage {
    return tls.get();
}

const std = @import("std");
const zitrus = @import("zitrus");

const c = zitrus.c;
const horizon = zitrus.horizon;
const tls = horizon.tls;
