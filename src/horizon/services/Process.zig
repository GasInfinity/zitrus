//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Services/

// TODO: Missing methods and check of parameters

pub const service = "ps:ps";

pub const aes = PxiProcess9.aes;

session: ClientSession,

pub fn open(srv: ServiceManager) !Process {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(ps: Process) void {
    ps.session.close();
}

pub const command = struct {
    pub const SignRsaSha256 = ipc.Command(Id, .sign_rsa_sha256, struct {
        sha256: [32]u8,
        size: u32,
        rsa_context: ipc.Static(u8, 0),
        signature: ipc.Mapped(u8, .w),
    }, ipc.Mapped(u8, .w));
    pub const VerifyRsaSha256 = ipc.Command(Id, .verify_rsa_sha256, struct {
        sha256: [32]u8,
        size: u32,
        rsa_context: ipc.Static(u8, 0),
        signature: ipc.Mapped(u8, .r),
    }, ipc.Mapped(u8, .r));
    pub const AesOperation = ipc.Command(Id, .aes_operation, aes.Input, aes.Output);
    pub const AesCcmOperation = ipc.Command(Id, .aes_ccm_operation, aes.CcmInput, void);
    // XXX: Check the real parameters of these!
    pub const GetGamecardUuid = ipc.Command(Id, .get_gamecard_uuid, void, [16]u8);
    pub const GetGamecardMakerEncryptedUuid = ipc.Command(Id, .get_gamecard_maker_encrypted_uuid, void, [17]u8);
    pub const GetGamecardAutostartup = ipc.Command(Id, .get_gamecard_autostartup, void, bool);
    pub const GetGamecardMaker = ipc.Command(Id, .get_gamecard_maker, void, u8);
    pub const GetLocalFriendSeed = ipc.Command(Id, .get_local_friend_seed, void, u64);
    pub const GetDeviceId = ipc.Command(Id, .get_device_id, void, u64);
    pub const SeedRandom = ipc.Command(Id, .seed_random, struct {}, void);
    pub const NextRandomBytes = ipc.Command(Id, .next_random_bytes, struct {
        size: u32,
        output: ipc.Mapped(u8, .w),
    }, ipc.Mapped(u8, .w));

    pub const Id = enum(u16) {
        sign_rsa_sha256 = 0x0001,
        verify_rsa_sha256,
        /// Removed in release 2.29 (2.0.0-2)
        set_aes_key,
        aes_operation,
        aes_ccm_operation,
        get_gamecard_uuid,
        get_gamecard_maker_encrypted_uuid,
        get_gamecard_autostartup,
        get_gamecard_maker,
        get_local_friend_seed,
        get_device_id,
        seed_random,
        next_random_bytes,
    };
};

const Process = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const PxiProcess9 = horizon.services.PxiProcess9;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
