//! std.Io and std.fs tests ~yoinked~ imported from std (as we can't test it directly)
//!
//! omits tests which will always be skipped (e.g we don't have symlinks) or are irrelevant.

test "resolve DNS" {
    if (builtin.os.tag == .wasi) return error.SkipZigTest;

    const io = testing.io;

    // Resolve localhost, this should not fail.
    {
        const localhost_v4 = try net.IpAddress.parse("127.0.0.1", 80);
        const localhost_v6 = try net.IpAddress.parse("::2", 80);

        var canonical_name_buffer: [net.HostName.max_len]u8 = undefined;
        var results_buffer: [32]net.HostName.LookupResult = undefined;
        var results: Io.Queue(net.HostName.LookupResult) = .init(&results_buffer);

        try net.HostName.lookup(try .init("localhost"), io, &results, .{
            .port = 80,
            .canonical_name_buffer = &canonical_name_buffer,
        });

        var addresses_found: usize = 0;

        while (results.getOne(io)) |result| switch (result) {
            .address => |address| {
                if (address.eql(&localhost_v4) or address.eql(&localhost_v6))
                    addresses_found += 1;
            },
            .canonical_name => |canonical_name| try testing.expectEqualStrings("localhost", canonical_name.bytes),
        } else |err| switch (err) {
            error.Closed => {},
            error.Canceled => |e| return e,
        }

        try testing.expect(addresses_found != 0);
    }

    {
        // The tests are required to work even when there is no Internet connection,
        // so some of these errors we must accept and skip the test.
        var canonical_name_buffer: [net.HostName.max_len]u8 = undefined;
        var results_buffer: [16]net.HostName.LookupResult = undefined;
        var results: Io.Queue(net.HostName.LookupResult) = .init(&results_buffer);

        net.HostName.lookup(try .init("example.com"), io, &results, .{
            .port = 80,
            .canonical_name_buffer = &canonical_name_buffer,
        }) catch |err| switch (err) {
            error.UnknownHostName => return error.SkipZigTest,
            error.NameServerFailure => return error.SkipZigTest,
            else => |e| return e,
        };

        while (results.getOne(io)) |result| switch (result) {
            .address => {},
            .canonical_name => {},
        } else |err| switch (err) {
            error.Closed => {},
            error.Canceled => |e| return e,
        }
    }
}

test "listen on a port, send bytes, receive bytes" {
    if (builtin.single_threaded) return error.SkipZigTest;
    if (builtin.os.tag == .wasi) return error.SkipZigTest;

    const io = testing.io;

    var server = try localhost.listen(io, .{
        .kernel_backlog = 1, // NOTE: changed as the default is too large
    });
    defer server.deinit(io);

    const S = struct {
        fn clientFn(server_address: net.IpAddress) !void {
            var stream = try server_address.connect(io, .{ .mode = .stream });
            defer stream.close(io);

            var stream_writer = stream.writer(io, &.{});
            try stream_writer.interface.writeAll("Hello world!");
            try stream.shutdown(io, .both); // NOTE: added as a close sends a RST
        }
    };

    const t = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, S.clientFn, .{server.socket.address});
    defer t.join();

    var stream = try server.accept(io);
    defer stream.close(io);
    var buf: [16]u8 = undefined;
    var stream_reader = stream.reader(io, &.{});
    const n = try stream_reader.interface.readSliceShort(&buf);

    try testing.expectEqual(@as(usize, 12), n);
    try testing.expectEqualSlices(u8, "Hello world!", buf[0..n]);
}

test "bind on a port, send bytes, receive bytes" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = testing.io;

    const server = try localhost.bind(io, .{ .mode = .dgram });
    defer server.close(io);

    const S = struct {
        fn clientFn(server_address: net.IpAddress) !void {
            const client = try localhost.bind(io, .{ .mode = .dgram });
            defer client.close(io);

            try client.send(io, &server_address, "Hello world!");
        }
    };

    const t = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, S.clientFn, .{server.address});
    defer t.join();

    var buf: [16]u8 = undefined;
    const msg = try server.receive(io, &buf);

    try testing.expectEqual(@as(usize, 12), msg.data.len);
    try testing.expectEqualSlices(u8, "Hello world!", msg.data);
}

const localhost: net.IpAddress = .{ .ip4 = .loopback(0) };

const testing = std.testing;
const expect = testing.expect;
const expectEqual  = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const tmpDir = std.testing.tmpDir;

const native_os = builtin.target.os.tag;

const zitrus = @import("zitrus");
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const Io = std.Io;

const net = Io.net;
