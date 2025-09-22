//! A connection to the `Horizon` error display manager.
//!
//! Manages error logging and exception throwing.

pub const port = "err:f";

pub const Error = ClientSession.RequestError;

pub const FatalErrorInfo = extern struct {
    pub const ErrorType = enum(u8) {
        generic,
        corrupted,
        card_removed,
        exception,
        failure,
        logged,
    };

    type: ErrorType,
    revision_high: u8,
    revision_low: u16,
    result_code: ResultCode,
    pc_address: u32,
    process_id: u32,
    title_id: u64,
    applet_title_id: u64,
    data: extern union { failure: Failure, exception: Exception },

    pub const Failure = extern struct { message: [0x60]u8 };
    pub const Exception = extern struct {
        pub const Type = enum(u8) {
            prefetch_abort,
            data_abort,
            undefined,
            vfp,
        };

        pub const Info = extern struct {
            type: Type,
            _pad0: [3]u8 = @splat(0),
            ifsr_dfsr: u32,
            r15_dfar: u32,
            fpexc: u32,
            fpinst: u32,
            fpinst2: u32,
        };

        info: Info,

        /// r0-r12, sp, lr, pc, cpsr
        registers: [17]u32,
    };
};

session: ClientSession,

pub fn open() !ErrDispManager {
    return .{ .session = try ClientSession.connect(port) };
}

pub fn close(errdisp: ErrDispManager) void {
    errdisp.session.close();
}

pub fn sendSetUserString(errdisp: ErrDispManager, str: []const u8) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(errdisp.session, command.SetUserString, .{ .str_size = str.len, .str = .init(str) }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendThrow(errdisp: ErrDispManager, fatal: FatalErrorInfo) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(errdisp.session, command.Throw, fatal, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const Id = enum(u16) {
        throw = 0x0001,
        set_user_string,
    };

    pub const Throw = ipc.Command(Id, .throw, FatalErrorInfo, struct {});
    pub const SetUserString = ipc.Command(Id, .set_user_string, struct { str_size: usize, str: ipc.StaticSlice(0) }, struct {});

    comptime {
        std.debug.assert(std.meta.eql(Throw.request, .{ .normal = 32, .translate = 0 }));
        std.debug.assert(std.meta.eql(Throw.response, .{ .normal = 1, .translate = 0 }));
        std.debug.assert(std.meta.eql(SetUserString.request, .{ .normal = 1, .translate = 2 }));
        std.debug.assert(std.meta.eql(SetUserString.response, .{ .normal = 1, .translate = 0 }));
    }
};

const ErrDispManager = @This();
const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Event = horizon.Event;
const Semaphore = horizon.Semaphore;
const ClientSession = horizon.ClientSession;
const ResultCode = horizon.result.Code;
