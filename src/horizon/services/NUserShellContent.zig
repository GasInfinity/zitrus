//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/NS_and_APT_Services

pub const service = "ns:c";

pub const SpecialContent = struct {
    media_type: Filesystem.MediaType,
    title_id: u64,
    special_content: Filesystem.SpecialContentType,
};

session: ClientSession,

pub fn open(srv: ServiceManager) !NUserShellContent {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(nsc: NUserShellContent) void {
    nsc.session.close();
}

pub fn sendLockSpecialContent(nsc: NUserShellContent, content: SpecialContent) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(nsc.session, command.LockSpecialContent, content, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub fn sendUnlockSpecialContent(nsc: NUserShellContent, content: SpecialContent) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(nsc.session, command.UnlockSpecialContent, content, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code),
    };
}

pub const command = struct {
    pub const LockSpecialContent = ipc.Command(Id, .lock_special_content, SpecialContent, struct {});
    pub const UnlockSpecialContent = ipc.Command(Id, .unlock_special_content, SpecialContent, struct {});

    pub const Id = enum(u16) {
        lock_special_content = 0x0001,
        unlock_special_content,
    };
};

const NUserShellContent = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const Filesystem = horizon.services.Filesystem;
const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
