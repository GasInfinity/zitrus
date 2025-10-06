//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Socket_Services

// TODO : Missing methods and check of parameters

pub const service = "soc:U";

session: ClientSession,

pub fn open(srv: ServiceManager) !SocketUser {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(soc: SocketUser) void {
    soc.session.close();
}

pub const command = struct {
    // XXX: I'm sure the responses are missing some translate parameters
    pub const InitializeSockets = ipc.Command(Id, .initialize_sockets, struct {
        memory_size: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        memory: horizon.MemoryBlock,
    }, struct {});
    pub const Socket = ipc.Command(Id, .socket, struct {
        domain: u32,
        type: u32,
        protocol: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { descriptor: u32 });
    pub const Listen = ipc.Command(Id, .listen, struct {
        socket: u32,
        backlog: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const Accept = ipc.Command(Id, .accept, struct {
        pub const static_buffers = 1;
        socket: u32,
        max_addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const Bind = ipc.Command(Id, .bind, struct {
        socket: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        sockaddr: ipc.StaticSlice(0),
    }, struct { posix_return: u32 });
    pub const Connect = ipc.Command(Id, .connect, struct {
        socket: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        sockaddr: ipc.StaticSlice(0),
    }, struct { posix_return: u32 });
    pub const RecvFromOther = ipc.Command(Id, .recvfrom_other, struct {
        pub const static_buffers = 1;
        socket: u32,
        output_len: u32,
        flags: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        output: ipc.MappedSlice(.write),
    }, struct { posix_return: u32 });
    pub const RecvFrom = ipc.Command(Id, .recvfrom, struct {
        pub const static_buffers = 2;
        socket: u32,
        output_len: u32,
        flags: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32, total_received: u32 });
    pub const SendToOther = ipc.Command(Id, .sendto_other, struct {
        socket: u32,
        input_len: u32,
        flags: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        dest_addr: ipc.StaticSlice(1),
        input: ipc.MappedSlice(.read),
    }, struct { posix_return: u32 });
    pub const SendTo = ipc.Command(Id, .sendto, struct {
        socket: u32,
        input_len: u32,
        flags: u32,
        addrlen: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        input: ipc.StaticSlice(2),
        dest_addr: ipc.StaticSlice(1),
    }, struct { posix_return: u32 });
    pub const Close = ipc.Command(Id, .close, struct {
        socket: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const Shutdown = ipc.Command(Id, .shutdown, struct {
        socket: u32,
        how: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const GetHostByName = ipc.Command(Id, .gethostbyname, struct {
        pub const static_buffers = 1;
        hostname_len: u32,
        output_len: u32,
        hostname: ipc.StaticSlice(3),
    }, struct { posix_return: u32 });
    pub const GetHostByAddr = ipc.Command(Id, .gethostbyaddr, struct {
        pub const static_buffers = 1;
        input_len: u32,
        type: u32,
        output_len: u32,
        input: ipc.StaticSlice(4),
    }, struct { posix_return: u32 });
    pub const GetAddrInfo = ipc.Command(Id, .getaddrinfo, struct {
        pub const static_buffers = 1;
        node_len: u32,
        service_len: u32,
        hints_len: u32,
        info_len: u32,
        node: ipc.StaticSlice(5),
        service: ipc.StaticSlice(6),
        hints: ipc.StaticSlice(7),
    }, struct { posix_return: u32, count: u32 });
    pub const GetNameInfo = ipc.Command(Id, .getnameinfo, struct {
        pub const static_buffers = 2;
        sockaddr_len: u32,
        host_len: u32,
        serv_len: u32,
        flags: u32,
        sockaddr: ipc.StaticSlice(8),
    }, struct { posix_return: u32 });
    pub const GetSockOpt = ipc.Command(Id, .getsockopt, struct {
        pub const static_buffers = 1;
        socket: u32,
        level: u32,
        opt_name: u32,
        opt_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32, opt_len: u32 });
    pub const SetSockOpt = ipc.Command(Id, .setsockopt, struct {
        socket: u32,
        level: u32,
        opt_name: u32,
        opt_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        opt: ipc.StaticSlice(9),
    }, struct { posix_return: u32 });
    pub const Fnctl = ipc.Command(Id, .fnctl, struct {
        socket: u32,
        cmd: u32,
        arg: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const Poll = ipc.Command(Id, .poll, struct {
        pub const static_buffers = 1;
        nfds: u32,
        timeout: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
        input: ipc.StaticSlice(10),
    }, struct { posix_return: u32 });
    pub const SockAtMark = ipc.Command(Id, .sockatmark, struct {
        socket: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const GetHostId = ipc.Command(Id, .gethostid, struct {}, struct { posix_return: u32 });
    pub const GetSockName = ipc.Command(Id, .getsockname, struct {
        pub const static_buffers = 1;
        socket: u32,
        max_addr_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const GetPeerName = ipc.Command(Id, .getpeername, struct {
        pub const static_buffers = 1;
        socket: u32,
        max_addr_len: u32,
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct { posix_return: u32 });
    pub const ShutdownSockets = ipc.Command(Id, .shutdown_sockets, struct {}, struct {});
    pub const GetNetworkOpt = ipc.Command(Id, .get_network_opt, struct {
        pub const static_buffers = 1;
        level: u32,
        opt_name: u32,
        opt_len: u32,
    }, struct { posix_return: u32, opt_len: u32 });
    // TODO: ICMP commands
    pub const GetResolverInfo = ipc.Command(Id, .get_resolver_info, struct {
        pub const static_buffers = 1;
        output_len: u32,
    }, struct { posix_return: u32 });
    // TODO: SendToMultiple
    pub const CloseSockets = ipc.Command(Id, .close_sockets, struct {
        process_id: ipc.ReplaceByProcessId = .replace,
    }, struct {});
    pub const AddGlobalSocket = ipc.Command(Id, .add_global_socket, struct {
        socket: u32,
    }, struct {});

    pub const Id = enum(u16) {
        initialize_sockets = 0x0001,
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
        shutdown_sockets,
        get_network_opt,
        icmp_socket,
        icmp_ping,
        icmp_cancel,
        icmp_close,
        get_resolver_info,
        send_to_multiple,
        close_sockets,
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

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
