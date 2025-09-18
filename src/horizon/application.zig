//! High-level abstraction to manage the lifecycle of an average Application.
//!
//! Unless you really want explicitness or control specific things,
//! it is recommended you use this. You can use this as a reference of
//! how everything should be correctly used.
//!
//! Uses 'APT:A' under the hood.

/// An Application which may use the PICA200 to render to framebuffers.
///
/// Creates a `mango.Device` on your behalf and handles synchronization
/// appropiately. The `Device` OWNS gsp state.
///
/// You can still do software rendering by mapping framebuffer memory
/// of a `mango.Swapchain` (if the memory can be mapped).
pub const Accelerated = Manager(true);

/// An Application which only uses software rendering.
///
/// Use this for prototypes only as `Accelerated` is preferred!
pub const Software = Manager(false);

pub const Event = enum(u1) {
    jump_home_rejected,
    quit,
};

pub const Config = struct {
    pub const default: Config = .{};
};

fn Manager(comptime accelerated: bool) type {
    return struct {
        pub const apt_service: Applet.Service = .app;

        arbiter: horizon.AddressArbiter,

        srv: ServiceManager,
        apt: Applet,
        gsp: GspGpu,
        hid: Hid,

        notification_manager: ServiceManager.Notification.Manager,
        apt_app: Applet.Application,
        input: Hid.Input,
        device: (if (accelerated) mango.Device else void),

        pub fn init(config: Config, allocator: std.mem.Allocator) !Application {
            _ = config;
            const arbiter: horizon.AddressArbiter = try .create();
            errdefer arbiter.close();

            const srv = try ServiceManager.open();
            errdefer srv.close();

            try srv.sendRegisterClient();

            const apt = try Applet.open(apt_service, srv);
            errdefer apt.close();

            const gsp = try GspGpu.open(srv);
            errdefer gsp.close();

            const hid = try Hid.open(.user, srv);
            errdefer hid.close();

            var notif_man = try ServiceManager.Notification.Manager.init(srv);
            errdefer notif_man.deinit();

            var app = try Applet.Application.init(apt, apt_service, srv);
            errdefer app.deinit(apt, apt_service, srv);

            var input = try Hid.Input.init(hid);
            errdefer input.deinit();

            const device = if (accelerated)
                try mango.createHorizonBackedDevice(.{
                    .gsp = gsp,
                    .arbiter = arbiter,
                }, allocator)
            else
                undefined;

            return .{
                .arbiter = arbiter,

                .srv = srv,
                .apt = apt,
                .gsp = gsp,
                .hid = hid,
                .notification_manager = notif_man,

                .apt_app = app,
                .input = input,
                .device = device,
            };
        }

        pub fn deinit(app: *Application, allocator: std.mem.Allocator) void {
            if (accelerated) {
                app.device.destroy(allocator);
            }

            app.input.deinit();
            app.apt_app.deinit(app.apt, apt_service, app.srv);
            app.notification_manager.deinit();
            app.hid.close();
            app.gsp.close();
            app.apt.close();
            app.srv.close();
            app.* = undefined;
        }

        /// Same behaviour as `app.waitEventTimeout(-1)`
        pub fn waitEvent(app: *Application) !Event {
            return app.waitEventTimeout(-1).?;
        }

        /// Same behaviour as `app.waitEventTimeout(0)`
        pub fn pollEvent(app: *Application) !?Event {
            return app.waitEventTimeout(0);
        }

        /// Waits for an event until one is encountered or a timeout happens.
        ///
        /// Automatically jumps to the home menu and sleeps if requested and allowed.
        pub fn waitEventTimeout(app: *Application, timeout: i64) !?Event {
            while (try app.notification_manager.pollNotification(app.srv)) |notif| switch (notif) {
                .must_terminate => return .quit,
                else => {},
            };

            while (try app.apt_app.waitNotificationTimeout(app.apt, apt_service, app.srv, timeout)) |n| switch (n) {
                .jump_home, .jump_home_by_power => {
                    if (accelerated) {
                        try app.device.waitIdle();
                    }

                    switch (try app.apt_app.jumpToHome(app.apt, apt_service, app.srv, app.gsp, .none)) {
                        .resumed => {},
                        .jump_home => unreachable,
                        .must_close => return .quit,
                    }
                },
                .sleeping => {
                    if (accelerated) {
                        try app.device.waitIdle();
                    }

                    while (try app.apt_app.waitNotification(app.apt, apt_service, app.srv) != .sleep_wakeup) {}
                    try app.gsp.sendSetLcdForceBlack(false);
                },
                .must_close, .must_close_by_shutdown => return .quit,
                .jump_home_rejected => return .jump_home_rejected,
                else => {},
            };

            return null;
        }

        const Application = @This();
    };
}

const zitrus = @import("zitrus");
const std = @import("std");

const mango = zitrus.mango;
const horizon = zitrus.horizon;
const services = horizon.services;

const ServiceManager = horizon.ServiceManager;
const GspGpu = services.GspGpu;
const Applet = services.Applet;
const Hid = services.Hid;
