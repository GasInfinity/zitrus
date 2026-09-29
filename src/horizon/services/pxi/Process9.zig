//! Based on the documentation found in 3dbrew: https://www.3dbrew.org/wiki/Process_Services_PXI/

pub const service = "pxi:ps9";

pub const aes = struct {
    pub const Algorithm = enum(u8) {
        encrypt_cbc,
        decrypt_cbc,
        encrypt_ctr,
        decrypt_ctr,
        encrypt_ccm,
        decrypt_ccm,
        _,
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
        _,
    };
};

pub const rsa = struct {
    pub const Context = extern struct {
        modulo: [0x100]u8,
        exponent: [0x100]u8,
        bit_size: u32,
        /// When `false`, `exponent` refers to a little-endian `u32`;
        /// usually used to load the common public exponent 0x10001.
        ///
        /// Otherwise `exponent` is a big-endian number.
        long_exponent: bool,
        _pad0: [3]u8 = @splat(0),
    };
};

session: ClientSession,

pub const open = horizon.services.Methods(@This()).openService;
pub const openWithResult = horizon.services.Methods(@This()).openServiceWithResult;
pub const close = horizon.services.Methods(@This()).close;
pub const send = horizon.services.Methods(@This()).send;
pub const sendWithResult = horizon.services.Methods(@This()).sendWithResult;

pub const command = struct {
    pub const RsaSignSha256 = ipc.Command(Id, .rsa_sign_sha256, struct {
        sha256: [32]u8,
        rsa_byte_size: u32,
        context_size: u32,
        signature: ipc.Pxi(u8, 0, true),
        rsa_context: ipc.Pxi(rsa.Context, 1, false),

        pub fn init(sha256: [32]u8, signature: []u8, rsa_context: *const rsa.Context) @This() {
            const rsa_byte_size = rsa_context.bit_size >> 3;
            return .{
                .sha256 = sha256,
                .rsa_byte_size = rsa_byte_size,
                .context_size = @sizeOf(rsa.Context),
                .signature = .pxi(signature[0..rsa_byte_size]),
                .rsa_context = .pxi(rsa_context[0..1]),
            };
        }
    }, struct { invalidate: ipc.PxiInvalidate = .invalidate });
    pub const RsaVerifySha256 = ipc.Command(Id, .rsa_verify_sha256, struct {
        sha256: [32]u8,
        rsa_byte_size: u32,
        context_size: u32,
        signature: ipc.Pxi(u8, 0, false),
        rsa_context: ipc.Pxi(rsa.Context, 1, false),

        pub fn init(sha256: [32]u8, signature: []const u8, rsa_context: *const rsa.Context) @This() {
            const rsa_byte_size = rsa_context.bit_size >> 3;
            return .{
                .sha256 = sha256,
                .rsa_byte_size = rsa_byte_size,
                .context_size = @sizeOf(rsa.Context),
                .signature = .pxi(signature[0..rsa_byte_size]),
                .rsa_context = .pxi(rsa_context[0..1]),
            };
        }
    }, struct { invalidate: ipc.PxiInvalidate = .invalidate });
    pub const AesCrypt = ipc.Command(Id, .aes_crypt, struct {
        size: u32,
        iv_ctr: [16]u8,
        algorithm: aes.Algorithm,
        key: aes.Key,
        input: ipc.Pxi(u8, 0, false),
        output: ipc.Pxi(u8, 1, true),

        pub fn init(iv_ctr: [16]u8, algorithm: aes.Algorithm, key: aes.Key, input: []const u8, output: []u8) @This() {
            std.debug.assert(input.len == output.len);

            return .{
                .size = input.len,
                .iv_ctr = iv_ctr,
                .algorithm = algorithm,
                .key = key,
                .input = .pxi(input),
                .output = .pxi(output),
            };
        }
    }, struct { feedback_iv_ctr: [16]u8, invalidate: ipc.PxiInvalidate = .invalidate });
    pub const AesCcmCrypt = ipc.Command(Id, .aes_ccm_crypt, struct {
        input_size: u32,
        output_size: u32,
        cbc_mac_data_size: u32,
        data_size: u32,
        mac_size: u32,
        nonce: [12]u8,
        algorithm: aes.Algorithm,
        key: aes.Key,
        input: ipc.Pxi(u8, 0, false),
        output: ipc.Pxi(u8, 1, true),

        pub fn init(cbc_mac_data_size: u32, data_size: u32, mac_size: u32, nonce: [12]u8, algorithm: aes.Algorithm, key: aes.Key, input: []const u8, output: []u8) @This() {
            return .{
                .input_size = input.len,
                .output_size = output.len,
                .cbc_mac_data_size = cbc_mac_data_size,
                .data_size = data_size,
                .mac_size = mac_size,
                .nonce = nonce,
                .algorithm = algorithm,
                .key = key,
                .input = .pxi(input),
                .output = .pxi(output),
            };
        }
    }, struct { invalidate: ipc.PxiInvalidate = .invalidate });
    pub const GetGameCardUid = ipc.Command(Id, .get_game_card_uid, void, [16]u8);
    pub const GetGameCardMakerEncryptedUid = ipc.Command(Id, .get_game_card_maker_encrypted_uid, void, [17]u8);
    pub const IsGameCardAutostarted = ipc.Command(Id, .is_game_card_autostarted, void, bool);
    pub const GetGameCardMaker = ipc.Command(Id, .get_game_card_maker, void, u8);
    pub const GetLocalFriendCodeSeed = ipc.Command(Id, .get_local_friend_code_seed, void, u64);
    pub const GetDeviceId = ipc.Command(Id, .get_device_id, void, u32);
    pub const SeedRandom = ipc.Command(Id, .seed_random, struct {
        size: u32,
        entropy: ipc.Pxi(u8, 0, false),

        pub fn init(buffer: []const u8) @This() {
            return .{ .size = buffer.len, .entropy = .pxi(buffer) };
        }
    }, struct { invalidate: ipc.PxiInvalidate = .invalidate });
    pub const NextRandomBytes = ipc.Command(Id, .next_random_bytes, struct {
        size: u32,
        random: ipc.Pxi(u8, 0, true),

        pub fn init(buffer: []u8) @This() {
            return .{ .size = buffer.len, .random = .pxi(buffer) };
        }
    }, struct { invalidate: ipc.PxiInvalidate = .invalidate });

    pub const Id = enum(u16) {
        rsa_crypt = 0x0001,
        rsa_sign_sha256 = 0x0002,
        rsa_verify_sha256 = 0x0003,
        // Removed in 2.0.0-2, it literallt shifted all other ids by 1 down
        // set_aes_key = 0x0004,
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
        // Removed in 9.3.0-21
        // amiibo_generate_hmac = 0x0401,
        // Removed in 9.3.0-21
        // amiibo_generate_key_data = 0x0402,
        // Removed in 9.3.0-21
        // amiibo_crypt = 0x0403,
        // Removed in 9.3.0-21
        // amiibo_crypt_dev = 0x0404,
    };
};

const Process9 = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const horizon = zitrus.horizon;
const tls = horizon.tls;
const ipc = horizon.ipc;

const ClientSession = horizon.Session.Client;
const ServiceManager = horizon.ServiceManager;
