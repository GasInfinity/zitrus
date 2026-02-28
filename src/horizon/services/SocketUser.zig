//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Socket_Services

// TODO : Missing methods and check of parameters

pub const service = "soc:U";

pub const E = enum(u32) {
    pub const Maybe = enum(i32) {
        _,
        
        pub fn errno(maybe: Maybe) E {
            return if (@intFromEnum(maybe) < 0) @enumFromInt(@abs(@intFromEnum(maybe))) else .SUCCESS;
        }
    };

    SUCCESS,
    @"2BIG",
    ACCES,
    ADDRINUSE,
    ADDRNOTAVAIL,
    AFNOSUPPORT,
    AGAIN,
    ALREADY,
    BADF,
    BADMSG,
    BUSY,
    CANCELED,
    CHILD,
    CONNABORTED,
    CONNREFUSED,
    CONNRESET,
    DEADLK,
    DESTADDRREQ,
    DOM,
    DQUOT,
    EXIST,
    FAULT,
    FBIG,
    HOSTUNREACH,
    IDRM,
    ILSEQ,
    INPROGRESS,
    INTR,
    INVAL,
    IO,
    ISCONN,
    ISDIR,
    LOOP,
    MFILE,
    MLINK,
    MSGSIZE,
    MULTIHOP,
    NAMETOOLONG,
    NETDOWN,
    NETRESET,
    NETUNREACH,
    NFILE,
    NOBUFS,
    NODATA,
    NODEV,
    NOENT,
    NOEXEC,
    NOLCK,
    NOLINK,
    NOMEM,
    NOMSG,
    NOPROTOOPT,
    NOSPC,
    NOSR,
    NOSTR,
    NOSYS,
    NOTCONN,
    NOTDIR,
    NOTEMPTY,
    NOTSOCK,
    NOTSUP,
    NOTTY,
    NXIO,
    OPNOTSUPP,
    OVERFLOW,
    PERM,
    PIPE,
    PROTO,
    PROTONOSUPPORT,
    PROTOTYPE,
    RANGE,
    ROFS,
    SPIPE,
    SRCH,
    STALE,
    TIME,
    TIMEDOUT,

    AI_FAMILY = 303,
    AI_MEMORY,
    AI_NONAME,
    AI_SOCKTYPE = 307,
    _,
};

pub const Family = enum(u8) {
    unspec = 0,
    inet = 2,
    inet6 = 23,
    _,
};

pub const Type = enum(u32) {
    any = 0,
    stream = 1,
    dgram,
    _,
};

pub const Protocol = enum(u32) {
    any = 0,
    _,
};

pub const Ip4Address = extern struct {
    header: IpAddress.Header = .{ .len = @sizeOf(Ip4Address), .family = .inet },
    /// Big endian
    port: u16,
    bytes: [4]u8,
};

pub const Ip6Address = extern struct {
    header: IpAddress.Header = .{ .len = @sizeOf(Ip6Address), .family = .inet6 },
    /// Big endian
    port: u16,
    bytes: [16]u8,
    flow: u32,
    interface: u32,
};

pub const IpAddress = extern union {
    pub const Header = extern struct {
        len: u8,
        family: Family,
    };

    header: Header,
    ip4: Ip4Address,
    ip6: Ip6Address,
};

pub const DatagramFlags = packed struct(u8) {
    out_of_band: bool = false,
    peek: bool = false,
    dont_wait: bool = false,
    _: u5 = 0,
};

pub const ShutdownHow = enum(u8) {
    recv = 1,
    send,
    both,
};

pub const HostEntry = extern struct {
    address_type: i16,
    address_len: u16,
    addresses_len: u16,
    aliases_len: u16,
    name: [256]u8,
    aliases: [24][256]u8,
    addresses: [24][16]u8,
};

pub const AddressInfo = extern struct {
    pub const Flags = packed struct(u32) {
        passive: bool = false,
        canonical_name: bool = false,
        numeric_host: bool = false,
        numeric_service: bool = false,
        _: u28 = 0,
    };

    flags: Flags,
    family: Family,
    type: Type,
    protocol: Protocol,
    address_len: u32,
    canonical_name: [256]u8,
    address: IpAddress,

    comptime { std.debug.assert(@sizeOf(AddressInfo) == 0x130); }
};

pub const SocketLevel = enum(u16) {
    pub const Socket = enum(u32) {
        reuse_address = 0x4,
        linger = 0x80,
        oob_inline = 0x100,
        send_buffer = 0x1001,
        recv_buffer,
        send_low_water_mark,
        recv_low_water_mark,
        type = 0x1008,
        @"error",
    };

    socket = 0xFFFF,
};

pub const SocketOption = packed union {
    socket: SocketLevel.Socket,
};

pub const Descriptor = enum(u32) {
    pub const Command = enum(u32) {
        pub const Arg = packed union {
            flags: Flags,
            none: void,
        };

        get_flags = 3,
        set_flags = 4,
        _,
    };

    pub const Flags = packed struct(u32) {
        _unknown0: u2 = 0,
        non_block: bool = false,
        _unknown1: u29 = 0,
    };

    pub const Poll = extern struct {
        pub const Events = packed struct(u32) {
            in: bool = false,
            pri: bool = false,
            _unused0: u1 = 0,
            out: bool = false,
            wrband: bool = false,
            nval: bool = false,
            _unused1: u26 = 0,
        };

        fd: Descriptor,
        poll: Events,
        received: Events,
    };

    _,

    pub fn close(desc: Descriptor, soc: SocketUser) void {
        soc.sendClose(desc);
    }
};

session: ClientSession,

pub fn open(srv: ServiceManager) !SocketUser {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(soc: SocketUser) void {
    soc.session.close();
}

/// The memory block must be created with (this: none, other: rw) 
/// if you don't want `permanent(os): incompatible_permissions (wrong_arg) (0xD900182E)`
pub fn sendInitialize(soc: SocketUser, buffer: horizon.MemoryBlock, buffer_len: usize) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Initialize, .{
        .buffer_len = buffer_len,
        .process_id = .replace,
        .buffer = buffer,
    }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendDeinitialize(soc: SocketUser) !void {
    _ = tls.get().ipc.sendRequest(soc.session, command.Deinitialize, .{}, .{}) catch {};
}

pub fn sendCloseAll(soc: SocketUser) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.CloseAll, .{}, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendAddGlobalSocket(soc: SocketUser, socket: Descriptor) !void {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.AddGlobalSocket, .{
        .socket = socket,
    }, .{})).cases()) {
        .success => {},
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendSocket(soc: SocketUser, domain: Family, typ: Type, protocol: Protocol) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Socket, .{
        .domain = domain,
        .type = typ,
        .protocol = protocol,
    }, .{})).cases()) {
        .success => |s| s.value.descriptor,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendListen(soc: SocketUser, socket: Descriptor, backlog: u32) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Listen, .{
        .socket = socket,
        .backlog = backlog,
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendAccept(soc: SocketUser, socket: Descriptor, address: *IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Accept, .{
        .socket = socket,
        .address_len = @sizeOf(IpAddress),
    }, .{ .address = address })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendBind(soc: SocketUser, socket: Descriptor, address: *const IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Bind, .{
        .socket = socket,
        .address_len = @sizeOf(IpAddress),
        .address = .static(@ptrCast(address)),
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendConnect(soc: SocketUser, socket: Descriptor, address: *const IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Connect, .{
        .socket = socket,
        .address_len = @sizeOf(IpAddress),
        .address = .static(@ptrCast(address)),
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendReceiveFromOther(soc: SocketUser, socket: Descriptor, flags: DatagramFlags, output: []u8, src_address: ?*IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.ReceiveFromOther, .{
        .socket = socket,
        .output_len = output.len,
        .flags = flags,
        .src_address_len = if (src_address) |_| @sizeOf(IpAddress) else 0,
        .output = .mapped(output),
    }, .{ .src_address = if (src_address) |addr| @ptrCast(addr) else &.{} })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

/// Asserts `output` is less than `0x2000` bytes.
pub fn sendReceiveFrom(soc: SocketUser, socket: Descriptor, flags: DatagramFlags, output: []u8, src_address: ?*IpAddress) !E.Maybe {
    std.debug.assert(output.len <= 0x2000);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.ReceiveFrom, .{
        .socket = socket,
        .output_len = output.len,
        .flags = flags,
        .src_address_len = if (src_address) |_| @sizeOf(IpAddress) else 0,
    }, .{ .output = output, .src_address = if (src_address) |addr| @ptrCast(addr) else &.{} })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendSendToOther(soc: SocketUser, socket: Descriptor, flags: DatagramFlags, input: []const u8, dest_address: ?*const IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.SendToOther, .{
        .socket = socket,
        .input_len = input.len,
        .flags = flags,
        .dest_address_len = if (dest_address) |_| @sizeOf(IpAddress) else 0,
        .dest_address = .static(if (dest_address) |addr| @ptrCast(addr) else &.{}),
        .input = .mapped(input),
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

/// Asserts `output` is less than `0x2000` bytes.
pub fn sendSendTo(soc: SocketUser, socket: Descriptor, flags: DatagramFlags, input: []const u8, dest_address: ?*const IpAddress) !E.Maybe {
    std.debug.assert(input.len <= 0x2000);

    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.SendTo, .{
        .socket = socket,
        .input_len = input.len,
        .flags = flags,
        .dest_address_len = if (dest_address) |_| @sizeOf(IpAddress) else 0,
        .input = .static(input),
        .dest_address = .static(if (dest_address) |addr| @ptrCast(addr) else &.{}),
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendClose(soc: SocketUser, socket: Descriptor) void {
    _ = tls.get().ipc.sendRequest(soc.session, command.Close, .{ .socket = socket }, .{}) catch {};
}

pub fn sendShutdown(soc: SocketUser, socket: Descriptor, how: ShutdownHow) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Shutdown, .{
        .socket = socket,
        .how = how,
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendGetHostByName(soc: SocketUser, hostname: []const u8, entry: *HostEntry) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.GetHostByName, .{
        .hostname_len = hostname.len,
        .entry_len = @sizeOf(HostEntry),
        .hostname = .static(hostname),
    }, .{ .entry = entry })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendGetAddrInfo(soc: SocketUser, node: []const u8, serv: []const u8, hints: ?*const AddressInfo, results: []AddressInfo) !struct { E.Maybe, u32 } {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.GetAddrInfo, .{
        .node_len = node.len,
        .service_len = serv.len,
        .hints_len = if (hints) |_| @sizeOf(AddressInfo) else 0,
        .results_len = @sizeOf(AddressInfo) * results.len,
        .node = .static(node),
        .service = .static(serv),
        .hints = .static(if (hints) |hint| @ptrCast(hint) else &.{}),
    }, .{ .results = results })).cases()) {
        .success => |s| .{ s.value.errno, s.value.count },
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendSetSockOpt(soc: SocketUser, socket: Descriptor, level: SocketLevel, name: SocketOption, opt: []const u8) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.SetSockOpt, .{
        .socket = socket,
        .level = level,
        .name = name,
        .opt_len = opt.len,
        .opt = .static(opt),
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendFcntl(soc: SocketUser, socket: Descriptor, cmd: Descriptor.Command, arg: Descriptor.Command.Arg) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Fcntl, .{
        .socket = socket,
        .cmd = cmd,
        .arg = arg,
    }, .{})).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendPoll(soc: SocketUser, polls: []Descriptor.Poll, timeout: i32) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.Poll, .{
        .nfds = polls.len,
        .timeout = timeout,
        .poll = .static(@ptrCast(polls))
    }, .{ .polls = polls })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendGetSockName(soc: SocketUser, socket: Descriptor, address: *IpAddress) !E.Maybe {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.GetSockName, .{
        .socket = socket,
        .address_len = @sizeOf(IpAddress),
    }, .{ .address = address })).cases()) {
        .success => |s| s.value.errno,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub fn sendGetHostId(soc: SocketUser) ![4]u8 {
    const data = tls.get();
    return switch ((try data.ipc.sendRequest(soc.session, command.GetHostId, .{}, .{})).cases()) {
        .success => |s| s.value.bytes,
        .failure => |code| horizon.unexpectedResult(code), 
    };
}

pub const command = struct {
    // XXX: I'm sure the responses are missing some translate parameters
    pub const Initialize = ipc.Command(Id, .initialize, struct {
        buffer_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        buffer: horizon.MemoryBlock,
    }, struct {});
    pub const Socket = ipc.Command(Id, .socket, struct {
        domain: Family,
        type: Type,
        protocol: Protocol,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { descriptor: E.Maybe });
    pub const Listen = ipc.Command(Id, .listen, struct {
        socket: Descriptor,
        backlog: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe });
    pub const Accept = ipc.Command(Id, .accept, struct {
        pub const StaticOutput = struct { address: *IpAddress };
        socket: Descriptor,
        address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe, address: ipc.Static(0) });
    pub const Bind = ipc.Command(Id, .bind, struct {
        socket: Descriptor,
        address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        address: ipc.Static(0),
    }, struct { errno: E.Maybe });
    pub const Connect = ipc.Command(Id, .connect, struct {
        socket: Descriptor,
        address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        address: ipc.Static(0),
    }, struct { errno: E.Maybe });
    pub const ReceiveFromOther = ipc.Command(Id, .recvfrom_other, struct {
        pub const StaticOutput = struct { src_address: []u8 };

        socket: Descriptor,
        output_len: u32,
        flags: DatagramFlags,
        src_address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        output: ipc.Mapped(.w),
    }, struct { errno: E.Maybe, src_address: ipc.Static(0), output: ipc.Mapped(.w) });
    pub const ReceiveFrom = ipc.Command(Id, .recvfrom, struct {
        pub const StaticOutput = struct {
            output: []u8,
            src_address: []u8,
        };

        socket: Descriptor,
        output_len: u32,
        flags: DatagramFlags,
        src_address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe, total_received: u32, output: ipc.Static(0), src_address: ipc.Static(1) });
    pub const SendToOther = ipc.Command(Id, .sendto_other, struct {
        socket: Descriptor,
        input_len: u32,
        flags: DatagramFlags,
        dest_address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        dest_address: ipc.Static(1),
        input: ipc.Mapped(.r),
    }, struct { errno: E.Maybe, input: ipc.Mapped(.r) });
    pub const SendTo = ipc.Command(Id, .sendto, struct {
        socket: Descriptor,
        input_len: u32,
        flags: DatagramFlags,
        dest_address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        input: ipc.Static(2),
        dest_address: ipc.Static(1),
    }, struct { errno: E.Maybe });
    pub const Close = ipc.Command(Id, .close, struct {
        socket: Descriptor,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E });
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {
        socket: Descriptor,
        how: ShutdownHow,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe });
    pub const GetHostByName = ipc.Command(Id, .gethostbyname, struct {
        pub const StaticOutput = struct { entry: *HostEntry };

        hostname_len: u32,
        entry_len: u32,
        hostname: ipc.Static(3),
    }, struct { errno: E, entry: ipc.Static(0) });
    pub const GetHostByAddr = ipc.Command(Id, .gethostbyaddr, struct {
        pub const StaticOutput = struct { entry: *HostEntry };

        address_len: u32,
        type: Family,
        entry_len: u32,
        address: ipc.Static(4),
    }, struct { errno: E.Maybe });
    pub const GetAddrInfo = ipc.Command(Id, .getaddrinfo, struct {
        pub const StaticOutput = struct { results: []AddressInfo };

        node_len: u32,
        service_len: u32,
        hints_len: u32,
        results_len: u32,
        node: ipc.Static(5),
        service: ipc.Static(6),
        hints: ipc.Static(7),
    }, struct { errno: E.Maybe, count: u32, results: ipc.Static(0) });
    pub const GetNameInfo = ipc.Command(Id, .getnameinfo, struct {
        pub const StaticOutput = struct {};

        sockaddr_len: u32,
        host_len: u32,
        serv_len: u32,
        flags: u32,
        sockaddr: ipc.Static(8),
    }, struct { errno: E.Maybe });
    pub const GetSockOpt = ipc.Command(Id, .getsockopt, struct {
        pub const StaticOutput = struct { opt: []u8 };

        socket: Descriptor,
        level: SocketLevel,
        name: SocketOption,
        len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe, opt_len: u32 });
    pub const SetSockOpt = ipc.Command(Id, .setsockopt, struct {
        socket: Descriptor,
        level: SocketLevel,
        name: SocketOption,
        opt_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        opt: ipc.Static(9),
    }, struct { errno: E.Maybe });
    pub const Fcntl = ipc.Command(Id, .fcntl, struct {
        socket: Descriptor,
        cmd: Descriptor.Command,
        arg: Descriptor.Command.Arg,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe });
    pub const Poll = ipc.Command(Id, .poll, struct {
        pub const StaticOutput = struct { polls: []Descriptor.Poll };

        nfds: u32,
        timeout: i32,
        process_id: ipc.ReplaceByProcessId = .replace,
        poll: ipc.Static(10),
    }, struct { errno: E.Maybe });
    pub const SockAtMark = ipc.Command(Id, .sockatmark, struct {
        socket: Descriptor,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe });
    pub const GetHostId = ipc.Command(Id, .gethostid, struct {}, struct { bytes: [4]u8 });
    pub const GetSockName = ipc.Command(Id, .getsockname, struct {
        pub const StaticOutput = struct { address: *IpAddress };

        socket: Descriptor,
        address_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe, address: ipc.Static(0) });
    pub const GetPeerName = ipc.Command(Id, .getpeername, struct {
        pub const static_buffers = 1;
        socket: Descriptor,
        max_addr_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { errno: E.Maybe });
    pub const Deinitialize = ipc.Command(Id, .deinitialize, struct {}, struct {});
    pub const GetNetworkOpt = ipc.Command(Id, .get_network_opt, struct {
        pub const static_buffers = 1;
        level: u32,
        opt_name: u32,
        opt_len: u32,
    }, struct { errno: E.Maybe, opt_len: u32 });
    // TODO: ICMP commands
    pub const GetResolverInfo = ipc.Command(Id, .get_resolver_info, struct {
        pub const static_buffers = 1;
        output_len: u32,
    }, struct { errno: E.Maybe });
    // TODO: SendToMultiple
    pub const CloseAll = ipc.Command(Id, .close_all, struct {
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct {});
    pub const AddGlobalSocket = ipc.Command(Id, .add_global_socket, struct {
        socket: Descriptor,
    }, struct {});

    pub const Id = enum(u16) {
        initialize = 0x0001,
        socket,
        listen,
        accept,
        bind,
        connect,
        recvfrom_other,
        recvfrom,
        sendto_other,
        sendto,
        close,
        shutdown,
        gethostbyname,
        gethostbyaddr,
        getaddrinfo,
        getnameinfo,
        getsockopt,
        setsockopt,
        fcntl,
        poll,
        sockatmark,
        gethostid,
        getsockname,
        getpeername,
        deinitialize,
        get_network_opt,
        icmp_socket,
        icmp_ping,
        icmp_cancel,
        icmp_close,
        get_resolver_info,
        send_to_multiple,
        close_all,
        remove_global_socket,
        add_global_socket,
    };
};

const SocketUser = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
