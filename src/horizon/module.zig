//! Mid-level sysmodule abstractions.

pub const StateBehavior = enum {
    /// The handler processes the requests of this service
    handled,

    /// You handle each new connection, e.g to spawn new threads
    /// or reuse an existing one.
    unhandled,
};

pub fn State(
    /// When not `null`, notifications will be handled by `next`
    ///
    /// If you're handling them elsewhere, leave this `null`
    comptime notifications: ?[]const ServiceManager.Notification,
    // SOA-style go brrrrr
    comptime names: []const []const u8,
    comptime behaviors: *const [names.len]StateBehavior,
    comptime max_sessions: *const [names.len]u15,
) type {
    std.debug.assert(names.len > 0);

    const notification_semaphore_len: usize = @intFromBool(notifications != null);
    const ports_start = notification_semaphore_len;
    const ports_len = names.len;
    const ports_end = ports_start + ports_len - 1;

    const always_listening_len = notification_semaphore_len + ports_len;

    const PortsInt = std.math.IntFittingRange(0, names.len - 1);
    const Ports = @Enum(PortsInt, .exhaustive, names, &std.simd.iota(PortsInt, names.len));
    const handled_remote_storage_len = blk: {
        var sum: usize = 0;

        for (behaviors, max_sessions) |behavior, max| switch (behavior) {
            .handled => sum += max,
            .unhandled => {}, // You handle it!
        };

        break :blk sum;
    };

    const HandledRemotesInt = std.math.IntFittingRange(0, handled_remote_storage_len);

    const handled_remote_storage_start = ports_start + ports_len;
    const handled_remote_storage_end = @max(handled_remote_storage_start + handled_remote_storage_len - 1, handled_remote_storage_start);

    const stored_handles_len = always_listening_len + handled_remote_storage_len;
    const StoredHandlesInt = std.math.IntFittingRange(0, stored_handles_len - 1);
    const Notification = if (notifications != null) ServiceManager.Notification else noreturn;

    const UnhandledPortSessionResult = struct {
        port: Ports,
        session: horizon.Session.Server,
    };

    const LastReplyTo = if (handled_remote_storage_len > 0) struct {
        idx: ?StoredHandlesInt = null,
        session: horizon.Session.Server = .none,
    } else struct {};

    return struct {
        pub const empty: Simple = .{
            .handles = undefined,
            .remote_port_mapping = undefined,
            .remotes = 0,
            .last_reply_to = .{},
        };

        pub const Result = union(enum) {
            notification: Notification,
            handled_session_accepted: Ports,
            handled_session_request: Ports,
            handled_session_closed: Ports,
            unhandled_session_accepted: UnhandledPortSessionResult,
        };

        handles: [stored_handles_len]horizon.Synchronization,
        remote_port_mapping: [handled_remote_storage_len]Ports,
        remotes: HandledRemotesInt,
        last_reply_to: LastReplyTo,

        pub fn initServices(state: *Simple, srv: ServiceManager) void {
            if (notifications) |notifs| {
                state.handles[0] = @bitCast(assertResult(srv.sendWithResult(.EnableNotification, {}, .{})));
                for (notifs) |id| assertResult(srv.sendWithResult(.Subscribe, id, .{}));
            }

            for (state.handles[ports_start..][0..ports_len], names, max_sessions) |*port, name, max| {
                port.* = @bitCast(assertResult(srv.sendWithResult(.RegisterService, .init(name, max), .{})).wrapped);
            }
        }

        /// Unregisters the services and closes all handles.
        pub fn deinitServices(state: *Simple, srv: ServiceManager) void {
            if (notifications) |notifs| {
                for (notifs) |id| assertResult(srv.sendWithResult(.Unsubscribe, id, .{}));
            }

            for (names) |name| assertResult(srv.sendWithResult(.UnregisterService, .embedded(name), .{}));
            for (state.handles[0 .. always_listening_len + state.remotes]) |handle| handle.close();
            state.* = .empty;
        }

        /// Assumes the previous
        pub fn next(state: *Simple, srv: ServiceManager) Result {
            const idx = if (handled_remote_storage_len > 0) blk: {
                const res = horizon.replyAndReceive(state.handles[0 .. always_listening_len + state.remotes], state.last_reply_to.session);
                const idx: usize = if (res.value < 0)
                    (if (state.last_reply_to.idx) |last| last else {
                        assertCode(.ztr_panic);
                        unreachable;
                    })
                else
                    @intCast(res.value);
                state.last_reply_to = .{};

                switch (res.code) {
                    .os_session_closed_by_remote => {
                        const session_idx = idx - handled_remote_storage_start;
                        const port: Ports = state.remote_port_mapping[session_idx];

                        state.remotes -= 1;
                        state.remote_port_mapping[session_idx] = state.remote_port_mapping[state.remotes];
                        state.remote_port_mapping[state.remotes] = undefined;

                        const last_idx = always_listening_len + state.remotes;
                        state.handles[idx].close();
                        state.handles[idx] = state.handles[last_idx];
                        state.handles[last_idx] = undefined;
                        return .{ .handled_session_closed = port };
                    },
                    else => |c| assertCode(c),
                }

                break :blk idx;
            } else assertResult(horizon.waitSynchronizationMultiple(state.handles[0..always_listening_len], false, .none));

            if (notifications != null and idx == 0) {
                return .{ .notification = assertResult(srv.sendWithResult(.ReceiveNotification, {}, .{})) };
            }

            switch (idx) {
                ports_start...ports_end => {
                    const session = assertResult(horizon.acceptSession(@bitCast(state.handles[idx])));
                    const port: Ports = @enumFromInt(idx - ports_start);

                    switch (behaviors[@intFromEnum(port)]) {
                        .handled => {
                            if (handled_remote_storage_len == 0) unreachable;
                            const session_idx = state.remotes;

                            state.handles[always_listening_len + session_idx] = @bitCast(session);
                            state.remote_port_mapping[session_idx] = port;
                            state.remotes += 1;
                            return .{ .handled_session_accepted = port };
                        },
                        .unhandled => return .{
                            .unhandled_session_accepted = .{ .port = port, .session = session },
                        },
                    }
                },
                handled_remote_storage_start...handled_remote_storage_end => {
                    if (handled_remote_storage_len == 0) unreachable;

                    const session: horizon.Session.Server = @bitCast(state.handles[idx]);
                    const port: Ports = state.remote_port_mapping[idx - handled_remote_storage_start];
                    state.last_reply_to = .{ .session = session, .idx = @intCast(idx) };
                    return .{ .handled_session_request = port };
                },
                else => unreachable,
            }
        }

        const Simple = @This();
    };
}

const assertResult = ErrorDisplayManager.assertResult;
const assertCode = ErrorDisplayManager.assertCode;

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;

const ServiceManager = horizon.ServiceManager;
const ErrorDisplayManager = horizon.ErrorDisplayManager;
