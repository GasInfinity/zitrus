//! An application that renders by blitting to the screen directly.
//!
//! Remember the dimensions of the screens are not what you expect,
//! they're rotated 90º!
//!
//! Sleeps and jumps to home are handled automatically, if you want more control
//! use methods in `horizon.Init.Application`.

app: horizon.Init.Application,
soft: *horizon.services.GspGpu.Graphics.Software,

/// Same behaviour as `sft.waitEventTimeout(.none)`
pub fn waitEvent(sft: Software) !horizon.Init.Application.Event.Minimal {
    return sft.waitEventTimeout(.none).?;
}

/// Same behaviour as `sft.waitEventTimeout(.fromNanoseconds(0))`
pub fn pollEvent(sft: Software) !?horizon.Init.Application.Event.Minimal {
    return try sft.waitEventTimeout(.fromNanoseconds(0));
}

/// Waits for an event until one is encountered or a timeout happens.
pub fn waitEventTimeout(sft: Software, timeout: horizon.Timeout) !?horizon.Init.Application.Event.Minimal {
    while (try sft.app.waitEventTimeout(timeout)) |ev| switch (ev) {
        .quit => return .quit,
        .jump_home_rejected => return .jump_home_rejected,
        .jump_home => {
            const capture = try sft.soft.release(sft.app.gsp);
            switch (try sft.app.app.jumpToHome(sft.app.apt, .app, sft.app.srv, capture, .none)) {
                .resumed => {
                    try sft.soft.reacquire(sft.app.gsp);
                    continue;
                },
                .jump_home => unreachable,
                .must_close => return .quit,
            }
        },
        .sleep => {
            _ = try sft.soft.release(sft.app.gsp);
            while (try sft.app.app.waitNotification(sft.app.apt, .app, sft.app.srv) != .sleep_wakeup) {}
            try sft.soft.reacquire(sft.app.gsp);
        },
    };

    return null;
}

const Software = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
