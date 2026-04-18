pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub const init_options: horizon.Init.Application.Software.Options = .{
    .double_buffer = .initFill(false),
};

pub fn main(init: horizon.Init.Application.Software) !void {
    const app = init.app;
    // const gpa = app.base.gpa;
    const io = app.base.io;
    const soft = init.soft;

    try horizon.Io.global.initStorage(app.srv, .soc, 4 * 1024 * 1024);

    var top_renderer_buf: [64]u8 = undefined;
    var top_renderer = zdebug.PsfRenderer.init(
        &top_renderer_buf,
        .spleen_6x12,
        soft.current(.top, .left),
        240 * 3,
        0,
        0,
        400,
        240,
        3,
    );
    top_renderer.clear();

    var bottom_renderer_buf: [64]u8 = undefined;
    var bottom_renderer = zdebug.PsfRenderer.init(
        &bottom_renderer_buf,
        .spleen_6x12,
        soft.current(.bottom, .left),
        240 * 3,
        0,
        0,
        320,
        240,
        3,
    );
    bottom_renderer.clear();

    const top_w = &top_renderer.writer;
    const bottom_w = &bottom_renderer.writer;

    const bound = try unspecified.bind(io, .{
        .mode = .dgram,
    });
    defer bound.close(io);

    try top_w.print("Listening on {f}", .{bound.address});
    try top_w.flush();

    soft.flush();
    soft.swap(.none);
    try soft.waitVBlank();

    var udp_buf: [64]u8 = undefined;
    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const input = init.app.input;
        const pad = input.pollPad();

        if (pad.current.start) break :main_loop;

        msg: {
            const msg = bound.receiveTimeout(io, &udp_buf, zero_timeout) catch |err| switch (err) {
                error.Timeout => break :msg,
                else => |e| return e,
            };

            const trimmed = std.mem.trim(u8, msg.data, " \t\n");
            try bottom_w.print("{f} -> {s} ", .{ msg.from, trimmed });
            if (msg.flags.trunc) try bottom_w.writeAll(" (truncated)");
            try bottom_w.writeByte('\n');
            try bottom_w.flush();

            try bound.send(io, &msg.from, msg.data);
        }

        soft.flush();
        soft.swap(.none);
        try soft.waitVBlank();
    }
}

const zero_timeout: Io.Timeout = .{ .duration = .{ .raw = .fromNanoseconds(0), .clock = .awake } };
const unspecified: net.IpAddress = .{ .ip4 = net.Ip4Address.unspecified(0) };

const horizon = zitrus.horizon;

const zdebug = zitrus.debug;
const zitrus = @import("zitrus");
const std = @import("std");
const Io = std.Io;
const net = Io.net;
