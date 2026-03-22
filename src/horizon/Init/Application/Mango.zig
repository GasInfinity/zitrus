//! An application that uses hardware acceleration with the PICA200 through `mango`
//!
//! Sleeps and jumps to home are handled automatically, if you want more control
//! use methods in `horizon.Init.Application`.

app: horizon.Init.Application,
device: mango.Device,

/// Same behaviour as `sft.waitEventTimeout(.none)`
pub fn waitEvent(mn: Mango) !horizon.Init.Application.Event.Minimal {
    return mn.waitEventTimeout(.none).?;
}

/// Same behaviour as `sft.waitEventTimeout(.fromNanoseconds(0))`
pub fn pollEvent(mn: Mango) !?horizon.Init.Application.Event.Minimal {
    return try mn.waitEventTimeout(.fromNanoseconds(0));
}

/// Waits for an event until one is encountered or a timeout happens.
pub fn waitEventTimeout(mn: Mango, timeout: horizon.Timeout) !?horizon.Init.Application.Event.Minimal {
    while (try mn.app.waitEventTimeout(timeout)) |ev| switch (ev) {
        .quit => return .quit,
        .jump_home_rejected => return .jump_home_rejected,
        .jump_home => {
            const info = try mn.device.release();
            switch (try mn.app.app.jumpToHome(mn.app.apt, .app, mn.app.srv, info, .none)) {
                .resumed => {
                    try mn.device.reacquire();
                    continue;
                },
                .jump_home => unreachable,
                .must_close => return .quit,
            }
        },
        .sleep => {
            _ = try mn.device.release();
            while (try mn.app.app.waitNotification(mn.app.apt, .app, mn.app.srv) != .sleep_wakeup) {}
            try mn.device.reacquire();
        },
    };

    return null;
}

const Mango = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const mango = zitrus.mango;
