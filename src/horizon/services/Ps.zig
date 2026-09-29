//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Services/

pub const service = "ps:ps";

pub const aes = PxiProcess9.aes;
pub const rsa = PxiProcess9.rsa;

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const RsaSignSha256 = ipc.Command(Id, .rsa_sign_sha256, struct {
        sha256: [32]u8,
        /// Unused though
        signature_size: u32,
        context: ipc.Static(rsa.Context, 0),
        signature: ipc.Mapped(u8, .w),

        pub fn init(sha256: [32]u8, rsa_context: *const rsa.Context, signature: []u8) @This() {
            return .{
                .sha256 = sha256,
                .signature_size = 0x100,
                .context = .static(rsa_context[0..1]),
                .signature = .mapped(signature),
            };
        }
    }, ipc.Mapped(u8, .w));
    pub const RsaVerifySha256 = ipc.Command(Id, .rsa_verify_sha256, struct {
        sha256: [32]u8,
        /// Unused though
        signature_size: u32,
        context: ipc.Static(rsa.Context, 0),
        signature: ipc.Mapped(u8, .r),

        pub fn init(sha256: [32]u8, rsa_context: *const rsa.Context, signature: []const u8) @This() {
            return .{
                .sha256 = sha256,
                .signature_size = 0x100,
                .context = .static(rsa_context[0..1]),
                .signature = .mapped(signature),
            };
        }
    }, ipc.Mapped(u8, .r));
    /// May fail with 0xc90107e8 (using ccm, use `AesCcmCrypt`)
    pub const AesCrypt = ipc.Command(Id, .aes_crypt, struct {
        input_size: u32,
        output_size: u32,
        iv_ctr: [16]u8,
        algorithm: aes.Algorithm,
        key: aes.Key,
        input: ipc.Mapped(u8, .r),
        output: ipc.Mapped(u8, .w),
    }, struct {
        feedback_iv_ctr: [16]u8,
        input: ipc.Mapped(u8, .r),
        output: ipc.Mapped(u8, .w),

        pub fn init(feedback_iv_ctr: [16]u8, input: []const u8, output: []u8) @This() {
            return .{ .feedback_iv_ctr = feedback_iv_ctr, .input = .mapped(input), .output = .mapped(output) };
        }
    });
    /// May fail with 0xc90107e8 (not using ccm, use `AesCrypt`) or 0xc90107ec (invalid size)
    pub const AesCcmCrypt = ipc.Command(Id, .aes_ccm_crypt, struct {
        input_size: u32,
        cbc_mac_data_size: u32,
        data_size: u32,
        output_size: u32,
        mac_size: u32,
        nonce: [12]u8,
        algorithm: aes.Algorithm,
        key: aes.Key,
        input: ipc.Mapped(u8, .r),
        output: ipc.Mapped(u8, .w),
    }, struct {
        input: ipc.Mapped(u8, .r),
        output: ipc.Mapped(u8, .w),

        pub fn init(input: []const u8, output: []u8) @This() {
            return .{ .input = .mapped(input), .output = .mapped(output) };
        }
    });
    /// May fail with 0xc90107fa (could not get program info from pid)
    pub const GetGameCardUid = ipc.Command(Id, .get_game_card_uid, struct { pid: ipc.ReplaceByProcessId = .replace }, [16]u8);
    /// May fail with 0xc90107fa (could not get program info from pid)
    pub const GetGameCardMakerEncryptedUid = ipc.Command(Id, .get_game_card_maker_encrypted_uid, struct { pid: ipc.ReplaceByProcessId = .replace }, [17]u8);
    /// May fail with 0xc90107fa (could not get program info from pid)
    pub const IsGameCardAutostarted = ipc.Command(Id, .is_game_card_autostarted, struct { pid: ipc.ReplaceByProcessId = .replace }, bool);
    /// May fail with 0xc90107fa (could not get program info from pid)
    pub const GetGameCardMaker = ipc.Command(Id, .get_game_card_maker, struct { pid: ipc.ReplaceByProcessId = .replace }, u8);
    /// Cannot fail
    pub const GetLocalFriendCodeSeed = ipc.Command(Id, .get_local_friend_code_seed, void, u64);
    /// Cannot fail
    pub const GetDeviceId = ipc.Command(Id, .get_device_id, void, u32);
    /// Cannot fail
    pub const SeedRandom = ipc.Command(Id, .seed_random, void, void);
    /// Cannot fail
    pub const NextRandomBytes = ipc.Command(Id, .next_random_bytes, struct {
        size: u32,
        output: ipc.Mapped(u8, .w),
    }, ipc.Mapped(u8, .w));

    pub const Id = enum(u16) {
        rsa_sign_sha256 = 0x0001,
        rsa_verify_sha256 = 0x0002,
        // Removed in 2.0.0-2
        set_aes_key,
        aes_crypt = 0x0004,
        aes_ccm_crypt = 0x0005,
        get_game_card_uid = 0x0006,
        get_game_card_maker_encrypted_uid = 0x0007,
        is_game_card_autostarted = 0x0008,
        get_game_card_maker = 0x0009,
        get_local_friend_code_seed = 0x000A,
        get_device_id = 0x000B,
        seed_random = 0x000C,
        next_random_bytes = 0x000D,
        // PXIPS9 commands removed in 9.3.0-21
        amiibo_generate_hmac = 0x000E,
        amiibo_generate_key_data = 0x000F,
        amiibo_crypt = 0x0010,
        amiibo_crypt_dev = 0x0011,
    };
};

const Process = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const PxiProcess9 = horizon.services.pxi.Process9;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
