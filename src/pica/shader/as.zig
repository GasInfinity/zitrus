// TODO:
// - Handle assembler correctness
// - Diagnostic reporting

pub const Tokenizer = tokenizer.Tokenizer;
pub const Token = tokenizer.Token;
pub const Assembler = @import("as/Assembler.zig");

comptime {
    _ = Tokenizer;
    _ = Token;
    _ = Assembler;
}

const tokenizer = @import("as/tokenizer.zig");
