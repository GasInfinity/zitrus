//! Juicy application entrypoint, from here you could choose your path:
//!     * Use `Software` rendering
//!     * Use `Mango` to drive the PICA200
//!     * Do your own thing and stay with `horizon.Init.Application`
//!
//! You must handle jump to home and sleep requests with this layer
//! as we don't know how you're using the PICA200 (if you're even using it)

pub const Software = @import("Application/Software.zig");
pub const Mango = @import("Application/Mango.zig");

pub const Event = enum {
    pub const Minimal = enum {
        /// The user wanted to do jump to the home menu but we rejected it.
        jump_home_rejected,

        /// The application has been notified to exit.
        quit,
    };

    /// The user wanted to do jump to the home menu but we rejected it.
    jump_home_rejected,

    /// The user wanted to jump and we allowed it, proceed with the jump.
    jump_home,

    /// The console will enter to sleep, you should wait until you're notified.
    sleep,

    /// The application has been notified to exit.
    quit,
};

base: horizon.Init,
srv: ServiceManager,
apt: Applet,
gsp: GraphicsServerGpu,
hid: Hid,

notification_manager: *ServiceManager.Notification.Manager,
app: *Applet.Application,
input: *Hid.Input,

/// Same behaviour as `app.waitEventTimeout(.none)`
pub fn waitEvent(app: Application) !Event {
    return app.waitEventTimeout(.none).?;
}

/// Same behaviour as `app.waitEventTimeout(.fromNanoseconds(0))`
pub fn pollEvent(app: Application) !?Event {
    return try app.waitEventTimeout(.fromNanoseconds(0));
}

/// Waits for an event until one is encountered or a timeout happens.
pub fn waitEventTimeout(app: Application, timeout: horizon.Timeout) !?Event {
    while (try app.notification_manager.pollNotification(app.srv)) |notif| switch (notif) {
        .must_terminate => return .quit,
        else => {},
    };

    while (app.app.waitNotificationTimeout(app.apt, .app, app.srv, timeout) catch |err| switch (err) {
        error.Timeout => return null,
        else => |e| return e,
    }) |n| switch (n) {
        .jump_home, .jump_home_by_power => return .jump_home,
        .sleeping => return .sleep,
        .must_close, .must_close_by_shutdown => return .quit,
        .jump_home_rejected => return .jump_home_rejected,
        else => {},
    };

    return null;
}

const Application = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ServiceManager = horizon.ServiceManager;
const services = horizon.services;
const GraphicsServerGpu = services.GraphicsServerGpu;
const Applet = services.Applet;
const Hid = services.Hid;
