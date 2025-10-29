//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Services_PXI/

// TODO: Missing methods and check of parameters

pub const service = "pxi:ps9";

pub const aes = struct {
    pub const Algorithm = enum(u8) {
        encrypt_cbc,
        decrypt_cbc,
        encrypt_ctr,
        decrypt_ctr,
        encrypt_ccm,
        decrypt_ccm,
    };

    pub const Key = enum(u8) {
        ssl,
        uds,
        apt,
        boss,
        unknown,
        download_play,
        streetpass,
        friend = 8,
        nfc,
    };

    pub const Input = struct {
        input_size: u32,
        output_size: u32,
        iv_ctr: [16]u8,
        algorithm: Algorithm,
        key: Key,
        source: ipc.Mapped(.r),
        destination: ipc.Static(.w),
    };

    pub const Output = struct {
        feedback_iv_ctr: [16]u8,
        source: ipc.Mapped(.r),
        destination: ipc.Static(.w),
    };

    pub const CcmInput = struct {
        input_size: u32,
        output_size: u32,
        cbc_mac_size: u32,
        data_size: u32,
        mac_size: u32,
        nonce: [12]u8,
        algorithm: Algorithm,
        key: Key,
        source: ipc.Mapped(.r),
        destination: ipc.Static(.w),
    };
};

session: ClientSession,

pub fn open(srv: ServiceManager) !PxiProcess9 {
    return .{ .session = try srv.getService(service, .wait) };
}

pub fn close(ps: PxiProcess9) void {
    ps.session.close();
}

pub const command = struct {
    pub const AesOperation = ipc.Command(Id, .aes_operation, aes.Input, aes.Output);
    pub const AesCcmOperation = ipc.Command(Id, .aes_ccm_operation, aes.CcmInput, struct {});
    // XXX: Check the real parameters of these!
    pub const GetGamecardUuid = ipc.Command(Id, .get_gamecard_uuid, struct {}, struct { uuid: [16]u8 });
    pub const GetGamecardMakerEncryptedUuid = ipc.Command(Id, .get_gamecard_maker_encrypted_uuid, struct {}, struct { maker_uuid: [17]u8 });
    pub const GetGamecardAutostartup = ipc.Command(Id, .get_gamecard_autostartup, struct {}, struct { autostartup: bool });
    pub const GetGamecardMaker = ipc.Command(Id, .get_gamecard_maker, struct {}, struct { maker: u8 });
    pub const GetLocalFriendSeed = ipc.Command(Id, .get_local_friend_seed, struct {}, struct { seed: u64 });
    pub const GetDeviceId = ipc.Command(Id, .get_device_id, struct {}, struct { id: u32 });
    // XXX: The translate parameter is arbitrary, I don't know if its a mapped or a static one but it makes more sense that it is a static one
    pub const SeedRandom = ipc.Command(Id, .seed_random, struct { size: u32, source: ipc.Static(0) }, struct { source: ipc.Static(0) });
    pub const NextRandomBytes = ipc.Command(Id, .next_random_bytes, struct { size: u32, output: ipc.Mapped(.w) }, struct { output: ipc.Mapped(.w) });

    pub const Id = enum(u16) {
        encrypt_rsa = 0x0001,
        sign_rsa_sha256,
        verify_rsa_sha256,
        aes_operation = 0x0003,
        aes_ccm_operation,
        get_gamecard_uuid,
        get_gamecard_maker_encrypted_uuid,
        get_gamecard_autostartup,
        get_gamecard_maker,
        get_local_friend_code_seed,
        get_device_id,
        seed_random,
        next_random_bytes,
    };
};

const PxiProcess9 = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.ClientSession;
const ServiceManager = horizon.ServiceManager;
