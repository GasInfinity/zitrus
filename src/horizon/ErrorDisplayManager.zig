//! A connection to the `Horizon` error display manager.
//!
//! Manages error logging and exception throwing.

pub const port = "err:f";

pub const Error = ClientSession.RequestError;

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
        fault: zitrus.hardware.cpu.arm11.Fault,
        address: u32,
        fpexc: u32,
        fpinst: u32,
        fpinst2: u32,
    };

    pub const Registers = extern struct {
        /// r0-r12, sp, lr, pc. See `zitrus.hardware.cpu.Register`
        gpr: [16]usize,
        cpsr: usize,
    };

    info: Info,
    registers: Registers,
};

pub const Failure = extern struct { message: [0x60]u8 };

pub const FatalError = extern struct {
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
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openPort;
pub const openWithResult = horizon.services.Methods(@This()).openPortWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = ipc.ServiceSend(@This()).send;
pub const sendWithResult = ipc.ServiceSend(@This()).sendWithResult;

/// Any string larger than 256 bytes will get truncated.
pub fn sendSetUserString(errdisp: ErrDispManager, str: []const u8) !void {
    return switch ((try errdisp.send(.SetUserString, .init(str[0..@min(str.len, 256)]), .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendThrow(errdisp: ErrDispManager, fatal: FatalError) !void {
    return switch (((try errdisp.send(.Throw, fatal, .{})).cases())) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub inline fn assertResult(result: anytype) @TypeOf(result.value) {
    assertCode(result.code);
    return result.value;
}

pub noinline fn assertCode(code: ResultCode) void {
    if (code.isSuccess()) return;

    const errdisp = blk: for (0..10) |_| {
        if (ErrDispManager.open()) |errdisp| {
            break :blk errdisp;
        } else |_| {}

        horizon.sleepThread(std.time.ns_per_s);
    } else horizon.breakExecution(.panic);
    defer errdisp.close();

    errdisp.sendThrow(.{
        .type = .generic,
        .revision_high = 0,
        .revision_low = 0,
        .result_code = code,
        .pc_address = @returnAddress(),
        .process_id = @intFromEnum(horizon.getProcessId(.current).value),
        .title_id = 0,
        .applet_title_id = 0,
        .data = undefined,
    }) catch horizon.breakExecution(.panic);

    while (true) horizon.breakExecution(.panic);
}

pub const command = struct {
    pub const Id = enum(u16) {
        throw = 0x0001,
        set_user_string,
    };

    pub const Throw = ipc.Command(Id, .throw, FatalError, void);
    // NOTE: Not documented on 3dbrew but the max str_size is 256 or we get a kernel panic.
    pub const SetUserString = ipc.Command(Id, .set_user_string, struct {
        str_size: u32,
        str: ipc.Static(0),

        pub fn init(str: []const u8) @This() {
            std.debug.assert(str.len <= 256);
            return .{ .str_size = @intCast(str.len), .str = .static(str) };
        }
    }, void);

    comptime {
        std.debug.assert(std.meta.eql(Throw.request_parameters, .parameters(32, 0)));
        std.debug.assert(std.meta.eql(Throw.response_parameters, .parameters(0, 0)));
        std.debug.assert(std.meta.eql(SetUserString.request_parameters, .parameters(1, 2)));
        std.debug.assert(std.meta.eql(SetUserString.response_parameters, .parameters(0, 0)));
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
const ClientSession = horizon.Session.Client;
const ResultCode = horizon.result.Code;
