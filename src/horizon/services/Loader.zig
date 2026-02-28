pub const service = "Loader";

// TODO: Only missing methods

pub const Program = enum(u64) { _ };

session: ClientSession,

pub fn open(srv: ServiceManager) !Loader {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(ldr: Loader) void {
    ldr.session.close();
}

pub fn sendLoadProcess(ldr: Loader, program: Program) !horizon.Process {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ldr.session, command.LoadProcess, .{ .program = program }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendRegisterProgram(ldr: Loader, base: Filesystem.ProgramInfo, update: Filesystem.ProgramInfo) !Program {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ldr.session, command.RegisterProgram, .{ .base = base, .update = update }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnregisterProgram(ldr: Loader, program: Program) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ldr.session, command.UnregisterProgram, .{ .program = program }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendGetProgramInfo(ldr: Loader, program: Program) !horizon.fmt.ncch.ExtendedHeader {
    var exhdr: horizon.fmt.ncch.ExtendedHeader = undefined;

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(ldr.session, command.GetProgramInfo, .{ .program = program }, .{ .extended_header = &exhdr })).cases()) {
        .success => exhdr,
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const LoadProcess = ipc.Command(Id, .load_process, struct { program: Program }, struct { process: horizon.Process });
    pub const RegisterProgram = ipc.Command(Id, .register_program, struct { base: Filesystem.ProgramInfo, update: Filesystem.ProgramInfo }, struct { program: Program });
    pub const UnregisterProgram = ipc.Command(Id, .unregister_program, struct { program: Program }, struct {});
    pub const GetProgramInfo = ipc.Command(Id, .get_program_info, struct {
        pub const StaticOutput = struct { extended_header: *horizon.fmt.ncch.ExtendedHeader };

        program: Program,
    }, struct {});

    pub const Id = enum(u16) {
        load_process = 0x0001,
        register_program,
        unregister_program,
        get_program_info,
    };
};

const Loader = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Filesystem = horizon.services.Filesystem;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
