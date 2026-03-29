//! Documented partially in https://problemkaputt.de/gbatek.htm#dswifidslinkwifibootprotocol
//! Missing info filled with a wireshark dump.

pub const description = "Send a 3DSX through the 3dslink protocol to a 3DS.";

pub const descriptions: plz.Descriptions(@This()) = .{
    .ip = "IP address of the 3DS",
    .retries = "Times to try to find a 3DS in LAN",
    .timeout = "Timeout (in ms) when listening for 3DS replies",
};

pub const short: plz.Short(@This()) = .{
    .ip = 'i',
    .retries = 'r',
    .timeout = 't',
    .verbose = 'v',
};

ip: ?[]const u8,
retries: u32 = 30,
timeout: u32 = 1000,
verbose: ?void,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "3DSX to send",
    };

    input: []const u8,
},

pub fn run(args: Link, io: std.Io, arena: std.mem.Allocator) !u8 {
    _ = arena;
    const cwd = std.Io.Dir.cwd();

    const input_file = cwd.openFile(io, args.@"--".input, .{ .mode = .read_only }) catch |err| {
        log.err("could not open input file '{s}': {t}", .{ args.@"--".input, err });
        return 1;
    };
    defer input_file.close(io);

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &input_buffer);

    const binary_in = &input_reader.interface;
    const hdr = try binary_in.peekStruct(@"3dsx".Header, .little);

    hdr.check() catch |err| {
        log.err("3DSX header check failed, refusing to send: {t}", .{err});
        return 1;
    };

    const basename = std.Io.Dir.path.basename(args.@"--".input);
    const full_size = input_reader.getSize() catch |err| {
        log.err("Could not get file size for '{s}': {t}", .{ args.@"--".input, err });
        return 1;
    };

    if (args.verbose) |_| log.info("'{s}' ({s}) is {} bytes long", .{ basename, args.@"--".input, full_size });

    const addr = if (args.ip) |ip| net.IpAddress.parse(ip, link_port) catch |err| {
        log.err("Could not parse IP address '{s}': {t}", .{ ip, err });
        return 1;
    } else (findDevice(io, .{
        .duration = .{
            .raw = .fromMilliseconds(args.timeout),
            .clock = .real,
        },
    }, args.retries, args.verbose != null) catch |err| {
        log.err("Could not find 3DS due to {t}", .{err});
        return 1;
    }) orelse {
        log.err("The 3DS did not respond after {} tries. Is your 3DS listening?", .{args.retries});
        log.info("Use --ip if UDP broadcasts are very unreliable in your LAN", .{});
        return 1;
    };

    const send = addr.connect(io, .{
        .mode = .stream,
        .protocol = .tcp,
        .timeout = .none,
    }) catch |err| {
        log.err("Could not connect to 3DS '{f}': {t}", .{ addr, err });
        return 1;
    };
    defer send.close(io);

    if (args.verbose) |_| log.info("Connected, sending payload", .{});

    var send_out_buf: [4096]u8 = undefined;
    var send_out = send.writer(io, &send_out_buf);
    const out = &send_out.interface;

    var send_in_buf: [4096]u8 = undefined;
    var send_in = send.reader(io, &send_in_buf);
    const in = &send_in.interface;

    try out.writeInt(u32, @intCast(basename.len), .little);
    try out.writeAll(basename);
    try out.writeInt(u32, @intCast(full_size), .little);
    try out.flush();

    // XXX: What are these replies? Do they mean something?
    const first_reply = try in.takeInt(u32, .little);

    if (first_reply != 0) {
        log.err("First 3DS reply is not 0: {}\n", .{first_reply});
        return 1;
    }

    var link_buf: [max_link_chunk_size]u8 = undefined;
    var heading_writer: HeadingWriter = .init(out, &link_buf);

    var deflate_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var deflate_compressor: std.compress.flate.Compress = try .init(&heading_writer.writer, &deflate_buf, .zlib, .default);

    try binary_in.streamExact64(&deflate_compressor.writer, full_size);
    try deflate_compressor.finish();
    try heading_writer.finish();
    try out.flush();

    const second_reply = try in.takeInt(u32, .little);

    if (second_reply != 0) {
        log.err("Second 3DS reply is not 0: {}\n", .{first_reply});
        return 1;
    }

    try out.writeInt(u32, @intCast(link_path.len + basename.len + 1), .little);
    try out.print("{s}{s}\x00", .{ link_path, basename });
    try out.flush();

    try send.shutdown(io, .both);
    return 0;
}

/// Writes a little endian 4-byte integer header before writing each buffered chunk.
///
/// More than 16KB will trigger a buffer overflow in the 3DS.
const HeadingWriter = struct {
    output: *Io.Writer,
    writer: Io.Writer,

    pub fn init(output: *Io.Writer, buffer: []u8) HeadingWriter {
        std.debug.assert(buffer.len <= max_link_chunk_size);
        
        return .{
            .output = output,
            .writer = .{
                .buffer = buffer,
                .end = 0,
                .vtable = &.{
                    .drain = drain,
                },
            }
        };
    }

    pub fn finish(h_writer: *HeadingWriter) !void {
        defer h_writer.writer = .failing;
        try h_writer.finishChunk();
    }

    fn drain(w: *Io.Writer, _: []const []const u8, _: usize) Io.Writer.Error!usize {
        const h_writer: *HeadingWriter = @alignCast(@fieldParentPtr("writer", w));
        try h_writer.finishChunk();
        return 0;
    }

    fn finishChunk(h_writer: *HeadingWriter) !void {
        const buf = h_writer.writer.buffered();
        defer h_writer.writer.end = 0;

        try h_writer.output.writeInt(u32, @intCast(buf.len), .little);
        try h_writer.output.writeAll(buf);
    }
};

fn findDevice(io: std.Io, timeout: Io.Timeout, retries: u32, verbose: bool) !?net.IpAddress {
    // XXX: ahh yes, let's hardcode the port instead of using the one we got from recv...
    // The 3DS always replies to this port...
    const any: net.IpAddress = .{ .ip4 = .unspecified(link_port) };
    const broadcast: net.IpAddress = .{
        .ip4 = .{
            .bytes = @splat(255),
            .port = link_port,
        },
    };

    const udp = try any.bind(io, .{
        .protocol = .udp,
        .mode = .dgram,
    });
    defer udp.close(io);

    // TODO: move to allow_broadcast when the next zig master is uploaded
    if (@hasDecl(std.posix.system, "setsockopt") and ((builtin.os.tag == .windows and builtin.link_libc) or builtin.os.tag != .windows)) {
        const truth: u32 = 1;
        _ = std.posix.system.setsockopt(udp.handle, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, @ptrCast(&truth), @sizeOf(u32));
    }

    // XXX: Can this handshake be bigger?
    var receive_buf: [link_rep_magic.len]u8 = undefined;

    for (0..retries) |retry| {
        if (verbose) log.info("Retry {d}... Broadcasting magic", .{retry});
        try udp.send(io, &broadcast, link_req_magic);

        recv: while (true) {
            const received = udp.receiveTimeout(io, &receive_buf, timeout) catch |err| switch (err) {
                error.Timeout => break :recv,
                else => |e| return e,
            };

            if (verbose) log.info("Datagram received from {f} - '{s}' ({s})", .{
                received.from,
                received.data,
                if (received.flags.trunc) "trunc" else "full",
            });

            if (received.flags.trunc) continue;
            if (std.mem.eql(u8, received.data, link_rep_magic)) return received.from;
        }
    }

    return null;
}

const link_port = 17491;
// NOTE: It seems this path is hardcoded somehow? It always sends this?
const link_path = "sdmc:/3ds/";
const link_req_magic = "3dsboot";
const link_rep_magic = "boot3ds";

// XXX: More than this and you'll get a buffer overflow.
const max_link_chunk_size = 16 * 1024;

const Link = @This();

const log = std.log.scoped(.@"3dsx-link");

const builtin = @import("builtin");
const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");

const Io = std.Io;
const net = Io.net;

const fmt = zitrus.horizon.fmt;
const @"3dsx" = zitrus.fmt.@"3dsx";
