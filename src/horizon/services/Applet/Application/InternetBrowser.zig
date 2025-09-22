//! Mid-level abstraction around the Horizon `internet browser` system applet.
//!
//! Used to navigate to the requested url.

url: [:0]const u8,

pub fn initUrl(url: [:0]const u8) InternetBrowser {
    return .{ .url = url };
}

pub fn start(internet: *InternetBrowser, app: *Application, apt: Applet, service: Applet.Service, srv: ServiceManager, gsp: GspGpu) !Application.ExecutionResult {
    return app.launchSystemApplet(apt, srv, service, gsp, .internet_browser, .null, internet.url);
}

const InternetBrowser = @This();
const Applet = horizon.services.Applet;
const Application = Applet.Application;

const GspGpu = horizon.services.GspGpu;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const services = horizon.services;

const ServiceManager = zitrus.horizon.ServiceManager;
