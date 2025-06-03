pub const Error = Session.RequestError;

pub const FatalErrorInfo = extern struct {
    pub const Type = enum(u8) {
        generic,
        corrupted,
        card_removed,
        exception,
        failure,
        logged,
    };

    type: Type,
    revision_high: u8,
    revision_low: u16,
    result_code: ResultCode,
    pc_address: u32,
    process_id: u32,
    title_id: u64,
    applet_title_id: u64,
    data: extern union { failure: Failure, exception: Exception },

    pub const Failure = extern struct { message: [0x60]u8 };
    pub const Exception = extern struct { _todo: [0x60]u8 = @splat(0) };
};

session: Session,

pub fn init(port: [:0]const u8) !ErrDispManager {
    const errdisp_session = try Session.connect(port);
    return ErrDispManager{ .session = errdisp_session };
}

pub fn deinit(errdisp: *ErrDispManager) void {
    errdisp.session.deinit();
    errdisp.* = undefined;
}

pub fn sendSetUserString(errdisp: ErrDispManager, str: []const u8) !void {
    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.set_user_string, .{str.len}, .{ ipc.StaticBufferTranslationDescriptor.init(str.len, 0), @intFromPtr(str.ptr) });

    try errdisp.session.sendRequest();
}

pub fn sendThrow(errdisp: ErrDispManager, fatal: FatalErrorInfo) !void {
    const as_u32: []const u32 = std.mem.bytesAsSlice(u32, std.mem.asBytes(&fatal));

    const data = tls.getThreadLocalStorage();
    data.ipc.fillCommand(Command.throw, as_u32, .{});

    try errdisp.session.sendRequest();
}

pub const Command = enum(u16) {
    throw = 0x0001,
    set_user_string,

    pub inline fn normalParameters(cmd: Command) u6 {
        return switch (cmd) {
            .throw => 32,
            .set_user_string => 1,
        };
    }

    pub inline fn translateParameters(cmd: Command) u6 {
        return switch (cmd) {
            .throw => 0,
            .set_user_string => 2,
        };
    }
};

const ErrDispManager = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const environment = zitrus.environment;
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Event = horizon.Event;
const Semaphore = horizon.Semaphore;
const Session = horizon.Session;
const ResultCode = horizon.ResultCode;
