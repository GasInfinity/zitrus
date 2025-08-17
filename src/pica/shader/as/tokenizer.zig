// This simple tokenizer hass been greatly inspired the zig tokenizer

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "add", .mnemonic_add },
        .{ "dp3", .mnemonic_dp3 },
        .{ "dp4", .mnemonic_dp4 },
        .{ "dph", .mnemonic_dph },
        .{ "dst", .mnemonic_dst },
        .{ "ex2", .mnemonic_ex2 },
        .{ "lg2", .mnemonic_lg2 },
        .{ "litp", .mnemonic_litp },
        .{ "mul", .mnemonic_mul },
        .{ "sge", .mnemonic_sge },
        .{ "slt", .mnemonic_slt },
        .{ "flr", .mnemonic_flr },
        .{ "max", .mnemonic_max },
        .{ "min", .mnemonic_min },
        .{ "rcp", .mnemonic_rcp },
        .{ "rsq", .mnemonic_rsq },
        .{ "mova", .mnemonic_mova },
        .{ "mov", .mnemonic_mov },
        .{ "break", .mnemonic_break },
        .{ "nop", .mnemonic_nop },
        .{ "end", .mnemonic_end },
        .{ "breakc", .mnemonic_breakc },
        .{ "call", .mnemonic_call },
        .{ "callc", .mnemonic_callc },
        .{ "callu", .mnemonic_callu },
        .{ "ifu", .mnemonic_ifu },
        .{ "ifc", .mnemonic_ifc },
        .{ "loop", .mnemonic_loop },
        .{ "emit", .mnemonic_emit },
        .{ "setemit", .mnemonic_setemit },
        .{ "jmpc", .mnemonic_jmpc },
        .{ "jmpu", .mnemonic_jmpu },
        .{ "cmp", .mnemonic_cmp },
        .{ "mad", .mnemonic_mad },
        .{ "true", .@"true" },
        .{ "false", .@"false" },
    });

    pub fn getKeyword(str: []const u8) ?Tag {
        return keywords.get(str);
    }

    pub const Tag = enum {
        invalid,
        eof,
        identifier,
        minus,
        number_literal,
        comma,
        l_paren,
        r_paren,
        l_square,
        r_square,
        colon,
        dot,
        newline,
        @"true",
        @"false",

        mnemonic_add,
        mnemonic_dp3,
        mnemonic_dp4,
        mnemonic_dph,
        mnemonic_dst,
        mnemonic_ex2,
        mnemonic_lg2,
        mnemonic_litp,
        mnemonic_mul,
        mnemonic_sge,
        mnemonic_slt,
        mnemonic_flr,
        mnemonic_max,
        mnemonic_min,
        mnemonic_rcp,
        mnemonic_rsq,
        mnemonic_mova,
        mnemonic_mov,
        mnemonic_break,
        mnemonic_nop,
        mnemonic_end,
        mnemonic_breakc,
        mnemonic_call,
        mnemonic_callc,
        mnemonic_callu,
        mnemonic_ifu,
        mnemonic_ifc,
        mnemonic_loop,
        mnemonic_emit,
        mnemonic_setemit,
        mnemonic_jmpc,
        mnemonic_jmpu,
        mnemonic_cmp,
        mnemonic_mad,

        pub fn lexeme(tag: Tag) ?[:0]const u8 {
            return switch (tag) {
                .comma => ",",
                .minus => "-",
                .l_paren => "(",
                .r_paren => ")",
                .l_square => "[",
                .r_square => "]",
                .colon => ":",
                .dot => ".",
                .@"true" => "true",
                .@"false" => "false",

                else => null,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn dump(tok: Tokenizer, tk: Token) void {
        std.debug.print("{s}: '{s}'\n", .{ @tagName(tk.tag), tok.buffer[tk.loc.start..tk.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{
            .buffer = buffer,
            // Skip UTF-8 BOM if present
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        };
    }

    const State = enum {
        start,
        invalid,
        expect_newline,
        line_comment,
        identifier,
        int,
        int_period,
        int_exponent,
        float,
        float_exponent,
    };

    pub fn next(tok: *Tokenizer) Token {
        var result: Token = .{ .tag = undefined, .loc = .{
            .start = tok.index,
            .end = undefined,
        } };

        state: switch (State.start) {
            .start => switch (tok.buffer[tok.index]) {
                0 => {
                    if (tok.index == tok.buffer.len) {
                        return .{
                            .tag = .eof,
                            .loc = .{ .start = tok.index, .end = tok.index },
                        };
                    } else {
                        continue :state .invalid;
                    }
                },
                'A'...'Z', 'a'...'z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    tok.index += 1;
                    continue :state .int;
                },
                '\n' => continue :state .expect_newline,
                '\r' => {
                    tok.index += 1;
                    continue :state .expect_newline;
                },
                ' ', '\t' => {
                    tok.index += 1;
                    result.loc.start = tok.index;
                    continue :state .start;
                },
                ':' => {
                    tok.index += 1;
                    result.tag = .colon;
                },
                '-' => {
                    tok.index += 1;
                    result.tag = .minus;
                },
                ',' => {
                    tok.index += 1;
                    result.tag = .comma;
                },
                '(' => {
                    tok.index += 1;
                    result.tag = .l_paren;
                },
                ')' => {
                    tok.index += 1;
                    result.tag = .r_paren;
                },
                '[' => {
                    tok.index += 1;
                    result.tag = .l_square;
                },
                ']' => {
                    tok.index += 1;
                    result.tag = .r_square;
                },
                ';' => {
                    tok.index += 1;
                    continue :state .line_comment;
                },
                '.' => {
                    tok.index += 1;
                    result.tag = .dot;
                },
                else => continue :state .invalid,
            },
            .invalid => {
                tok.index += 1;

                switch (tok.buffer[tok.index]) {
                    0 => if (tok.index == tok.buffer.len) {
                        result.tag = .invalid;
                    } else {
                        continue :state .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },
            .expect_newline => switch (tok.buffer[tok.index]) {
                0 => if (tok.index == tok.buffer.len) {
                    result.tag = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => {
                    result.loc.start = tok.index;
                    tok.index += 1;
                    result.tag = .newline;
                },
                else => continue :state .invalid,
            },
            .line_comment => {
                tok.index += 1;
                switch (tok.buffer[tok.index]) {
                    0 => if (tok.index != tok.buffer.len) {
                        continue :state .invalid;
                    } else return .{ .tag = .eof, .loc = .{ .start = tok.index, .end = tok.index } },
                    '\n' => continue :state .expect_newline,
                    '\r' => {
                        tok.index += 1;
                        continue :state .expect_newline;
                    },
                    else => continue :state .line_comment,
                }
            },
            .identifier => {
                tok.index += 1;

                switch (tok.buffer[tok.index]) {
                    'A'...'Z', 'a'...'z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        if (Token.getKeyword(tok.buffer[result.loc.start..tok.index])) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },
            // ensure we tokenize integers/floats the same way the tokenizer does to reuse std.zig.parseNumberLiteral
            .int => switch (tok.buffer[tok.index]) {
                '.' => continue :state .int_period,
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    tok.index += 1;
                    continue :state .int;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .int_exponent;
                },
                else => {},
            },
            .int_exponent => {
                tok.index += 1;
                switch (tok.buffer[tok.index]) {
                    '-', '+' => {
                        tok.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .int,
                }
            },
            .int_period => {
                tok.index += 1;
                switch (tok.buffer[tok.index]) {
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                        tok.index += 1;
                        continue :state .float;
                    },
                    'e', 'E', 'p', 'P' => {
                        continue :state .float_exponent;
                    },
                    else => tok.index -= 1,
                }
            },
            .float => switch (tok.buffer[tok.index]) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    tok.index += 1;
                    continue :state .float;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .float_exponent;
                },
                else => {},
            },
            .float_exponent => {
                tok.index += 1;
                switch (tok.buffer[tok.index]) {
                    '-', '+' => {
                        tok.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .float,
                }
            },
        }

        result.loc.end = tok.index;
        return result;
    }
};

const testing = std.testing;

test "tokenize label" {
    try testTokenize("a_label:", &.{ .identifier, .colon });
}

test "tokenize directive" {
    try testTokenize(".directive_with an_identifier_parameter 0b10", &.{ .dot, .identifier, .identifier, .number_literal });
}

test "tokenize 'mov r0, v0'" {
    try testTokenize("mov r0, v0", &.{ .mnemonic_mov, .identifier, .comma, .identifier });
}

test "tokenize multiple instructions" {
    try testTokenize(
        \\ mov r0, v0
        \\ add r0, v1
    , &.{
        // zig fmt: off
        .mnemonic_mov, .identifier, .comma, .identifier, .newline,
        .mnemonic_add, .identifier, .comma, .identifier,
        // zig fmt: on 
    });
}

test "tokenize multiple instructions with comments in-between" {
    try testTokenize(
        \\ mov r0, v0 ; this is a comment
        \\ ; this is a comment in-between
        \\ add r0, v1 ; this is another comment
    , &.{
        // zig fmt: off
        .mnemonic_mov, .identifier, .comma, .identifier, .newline,
        .newline,
        .mnemonic_add, .identifier, .comma, .identifier,
        // zig fmt: on 
    });
}

test "tokenize number literals" {
    try testTokenize("0", &.{.number_literal});
    try testTokenize("1", &.{.number_literal});
    try testTokenize("3.1415926535", &.{.number_literal});
    try testTokenize("0x200", &.{.number_literal});
    try testTokenize("0b11", &.{.number_literal});
    try testTokenize("0.1", &.{.number_literal});
    try testTokenize("2e+20", &.{.number_literal});
    try testTokenize("2e-1", &.{.number_literal});
}

// TODO: fuzz, look how it works and how the zig tokenizer is being fuzzed

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);

    for (expected_token_tags) |expected_tag| {
        const tk = tokenizer.next();

        try testing.expectEqual(expected_tag, tk.tag);
    }

    const last = tokenizer.next();
    try testing.expectEqual(Token.Tag.eof, last.tag);
    try testing.expectEqual(source.len, last.loc.start);
    try testing.expectEqual(source.len, last.loc.end);
}

const std = @import("std");
