pub const Interrupt = packed struct(u32) {
    pub const Registers = extern struct {
        enable: Interrupt,
        flags: Interrupt,
    };

    pub const Pxi = packed struct(u3) {
        sync: bool,
        send_emoty: bool,
        receive_full: bool,
    };

    pub const Sdio = packed struct(u2) {
        controller: bool,
        async: bool,
    };

    pub const Debug = packed struct(u2) {
        receive: bool,
        send: bool,
    };

    pub const Gamecard = packed struct(u2) {
        power_off: bool,
        insert: bool,
    };

    pub const Xdma = packed struct(u2) {
        event: bool,
        fault: bool,
    };

    ndma: BitpackedArray(bool, 8),
    timer: BitpackedArray(bool, 4),
    pxi: Pxi,
    aes: bool,
    sdio: BitpackedArray(Sdio, 2),
    debug: Debug,
    rsa: bool,
    ctr_card: BitpackedArray(bool, 2),
    gamecard: Gamecard,
    ntr_card: bool,
    xdma: Xdma,
    _unused0: u2 = 0,
};

const zitrus = @import("zitrus");
const hardware = zitrus.hardware;
const BitpackedArray = hardware.BitpackedArray;
