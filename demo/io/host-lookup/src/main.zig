pub const std_os_options: std.Options.OperatingSystem = horizon.default_std_os_options;

pub const init_options: horizon.Init.Application.Software.Options = .{
    .double_buffer = .initFill(false),
};

pub fn main(init: horizon.Init.Application.Software) !void {
    const app = init.app;
    const gpa = app.base.gpa;
    const io = app.base.io;
    const soft = init.soft;

    // XXX: Better but still not great, networking and fs should also be separate (in initialization, not usage)
    try horizon.Io.global.initStorage(app.srv, .soc, 4 * 1024 * 1024);

    var top_renderer_buf: [64]u8 = undefined;
    var top_renderer = try zdebug.PsfRenderer.init(
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
    var bottom_renderer = try zdebug.PsfRenderer.init(
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

    var swkbd: Swkbd = try .normal(.{
        .max_length = net.HostName.max_len,
        .buttons = &.{ .button(.utf8("Cancel"), .none), .button(.utf8("Lookup"), .submits) },
        .hint = .utf8("Enter a host name..."),
        .filter = .{},
        .features = .{},
        .password_mode = .none,
        .dictionary = &.{},
    }, gpa);
    defer swkbd.deinit(gpa);

    const top_w = &top_renderer.writer;
    const bottom_w = &bottom_renderer.writer;

    bottom_renderer.x = @intCast((bottom_renderer.width / 2) - ((bottom_message.len * bottom_renderer.psf.glyph_width) / 2));
    bottom_renderer.y = @intCast((bottom_renderer.height / 2) - (bottom_renderer.psf.glyph_height / 2));
    try bottom_w.writeAll(bottom_message);
    try bottom_w.flush();

    soft.flush();
    soft.swap(.none);
    try soft.waitVBlank();

    var canonical_buffer: [255]u8 = undefined;
    var utf8_buffer: [512]u8 = undefined;
    main_loop: while (true) {
        while (try init.pollEvent()) |ev| switch (ev) {
            .jump_home_rejected => {},
            .quit => break :main_loop,
        };

        const input = init.app.input;
        const pad = input.pollPad();
        const touch = input.pollTouch();

        if (pad.current.start) break :main_loop;

        if (touch.pressed) print_host: {
            // Reset what was written, can be omitted this if you want to show the last inputted text
            swkbd.state.initial_text_offset = std.math.maxInt(u32);
            const result = try swkbd.start(init.app.app, init.app.apt, .app, init.app.srv, try soft.release(init.app.gsp));
            try soft.reacquire(init.app.gsp);

            switch (result) {
                .middle, .jump_home, .jump_home_by_power => unreachable, // we only have one button
                .left => break :print_host,
                .right => {
                    const host_name_bytes = utf8_buffer[0..try std.unicode.utf16LeToUtf8(&utf8_buffer, swkbd.writtenText())];
                    const host_name = net.HostName.init(host_name_bytes) catch |err| switch (err) {
                        error.NameTooLong => unreachable, // we cap it above
                        error.InvalidHostName => {
                            try top_w.print("Invalid host name '{s}'", .{host_name_bytes});
                            try top_w.flush();
                            break :print_host;
                        },
                    };

                    try top_w.print("Resolving '{s}'... ", .{host_name_bytes});
                    try top_w.flush();

                    var results: [16]net.HostName.LookupResult = undefined;
                    var resolved: Io.Queue(net.HostName.LookupResult) = .init(&results);

                    host_name.lookup(io, &resolved, .{
                        .port = 80,
                        .canonical_name_buffer = &canonical_buffer,
                    }) catch |err| switch (err) {
                        else => |e| {
                            try top_w.print(" FAIL ({t})\n", .{e});
                            try top_w.flush();
                            break :print_host;
                        },
                    };

                    while (resolved.getOne(io)) |lookup_result| switch (lookup_result) {
                        .address => |addr| try top_w.print("{f} ", .{addr}),
                        .canonical_name => |canon| try top_w.print("'{s}' ", .{canon.bytes}),
                    } else |_| {}
                    try top_w.writeByte('\n');
                    try top_w.flush();
                },
                else => {},
            }
        }

        soft.flush();
        soft.swap(.none);
        try soft.waitVBlank();
    }
}

const bottom_message = "Press the touch screen to lookup a new host...";
const unspecified: net.IpAddress = .{ .ip4 = net.Ip4Address.unspecified(0) };

const horizon = zitrus.horizon;
const Swkbd = horizon.services.Applet.Application.SoftwareKeyboard;

const zdebug = zitrus.debug;
const zitrus = @import("zitrus");
const std = @import("std");
const Io = std.Io;
const net = Io.net;
