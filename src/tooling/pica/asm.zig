// TODO:
// - Handle assembler correctness
// - Implement assembler

pub const Mnemonic = enum {
    add,
    dp3,
    dp4,
    dph,
    dst,
    ex2,
    lg2,
    litp,
    mul,
    sge,
    slt,
    flr,
    max,
    min,
    rcp,
    rsq,
    mova,
    mov,
    @"break",
    nop,
    end,
    breakc,
    call,
    callc,
    callu,
    ifu,
    ifc,
    loop,
    emit,
    setemit,
    jmpc,
    jmpu,
    cmp,
    mad,
};

const Operand = enum {
    dst,
    src,
    src_limited,
    src_boolean,
    src_integer,
    condition,
    bit,
    comparison,
    label_or_constant,
};

pub const Assembler = struct {
    tk: Tokenizer,

    pub const Tokenizer = struct {};
};

const encoding = @import("encoding.zig");
