/// Provides a session to the Applet service within tests.
/// Initialized at startup. Read-only after that
pub var apt: horizon.services.Applet = if(!builtin.is_test)
    @compileError("trying to get openede testing gsp session when not testing")
else 
    undefined;

/// Provides a session to the GspGpu service within tests.
/// Initialized at startup. Read-only after that
pub var gsp: horizon.services.GspGpu = if(!builtin.is_test)
    @compileError("trying to get openede testing gsp session when not testing")
else 
    undefined;

const builtin = @import("builtin");
const std = @import("std");

const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
