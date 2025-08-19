pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: u32,
});

pub const EntryInfo = union(pica.shader.Type) {
    vertex,
    geometry: pica.shader.GeometryMode,
};

const Entrypoint = struct {
    info: EntryInfo,
    tok_i: u32,
};

pub const LabelMap = std.StringArrayHashMapUnmanaged(u12);
pub const EntrypointMap = std.StringArrayHashMapUnmanaged(Entrypoint);
pub const Outputs = std.EnumMap(register.Destination.Output, pica.OutputMap);

pub const FloatingConstants = std.EnumMap(register.Source.Constant, pica.F7_16x4);
pub const IntegerConstants = std.EnumMap(register.Integral.Integer, [4]i8);
pub const BooleanConstants = std.EnumSet(register.Integral.Boolean);

pub const Assembled = struct {
    pub const ProcessedEntrypoint = struct {
        pub const Map = std.StringArrayHashMapUnmanaged(ProcessedEntrypoint);
        info: EntryInfo,
        offset: u16,
    };

    source: [:0]const u8,
    tokens: TokenList.Slice,
    entries: ProcessedEntrypoint.Map,
    outputs: Outputs,
    flt_const: FloatingConstants,
    int_const: IntegerConstants,
    bool_const: BooleanConstants,
    encoded: Encoder,

    errors: []const Error,

    pub fn deinit(assembled: *Assembled, gpa: std.mem.Allocator) void {
        assembled.tokens.deinit(gpa);
        assembled.entries.deinit(gpa);
        assembled.encoded.deinit(gpa);
        gpa.free(assembled.errors);
        assembled.* = undefined;
    }

    pub fn tokenTag(a: Assembled, tok_index: usize) Token.Tag {
        return a.tokens.items(.tag)[tok_index];
    }

    pub fn tokenStart(a: Assembled, tok_index: usize) u32 {
        return a.tokens.items(.start)[tok_index];
    }

    pub fn tokenSlice(a: Assembled, tok_index: usize) []const u8 {
        const tok_tag = a.tokenTag(tok_index);

        if (tok_tag.lexeme()) |lexeme| {
            return lexeme;
        }

        const tok_start = a.tokenStart(tok_index);
        var tokenizer: shader.as.Tokenizer = .{
            .buffer = a.source,
            .index = tok_start,
        };

        const tok = tokenizer.next();
        std.debug.assert(tok.tag == tok_tag);
        return a.source[tok.loc.start..tok.loc.end];
    }

    pub fn assemble(gpa: std.mem.Allocator, source: [:0]const u8) !Assembled {
        var tokens = TokenList{};
        defer tokens.deinit(gpa);

        {
            var tokenizer: shader.as.Tokenizer = .init(source);

            while (true) {
                const tok = tokenizer.next();

                try tokens.append(gpa, .{
                    .tag = tok.tag,
                    .start = @intCast(tok.loc.start),
                });

                if (tok.tag == .eof) {
                    break;
                }
            }
        }

        var assembler: Assembler = .{
            .gpa = gpa,
            .aliases = .empty,
            .errors = .empty,
            .source = source,
            .tokens = tokens.toOwnedSlice(),
            .encoder = .init,
            .labels = .empty,
            .entrypoints = .empty,
            .outputs = .init(.{}),
            .flt_const = .init(.{}),
            .int_const = .init(.{}),
            .bool_const = .initEmpty(),
            .tok_i = 0,
            .inst_i = 0,
        };
        defer assembler.deinit(gpa);

        assembler.passRoot() catch |e| switch (e) {
            error.ParseError => {},
            else => return e,
        };

        var entrypoints: ProcessedEntrypoint.Map = .empty;
        errdefer entrypoints.deinit(gpa);

        if (assembler.errors.items.len == 0) assemble: {
            assembler.passAssemble() catch |e| switch (e) {
                error.ParseError => break :assemble,
                else => return e,
            };

            var it = assembler.entrypoints.iterator();
            while (it.next()) |entry| {
                const label_offset = assembler.labels.get(entry.key_ptr.*) orelse {
                    try assembler.warnMsg(.{
                        .tag = .undefined_label,
                        .tok_i = entry.value_ptr.*.tok_i,
                    });

                    continue;
                };

                try entrypoints.put(gpa, entry.key_ptr.*, .{
                    .info = entry.value_ptr.*.info,
                    .offset = label_offset,
                });
            }
        }

        return .{
            .source = assembler.source,
            .tokens = assembler.tokens,
            .encoded = assembler.encoder.move(),
            .entries = entrypoints,
            .outputs = assembler.outputs,
            .flt_const = assembler.flt_const,
            .int_const = assembler.int_const,
            .bool_const = assembler.bool_const,
            .errors = try assembler.errors.toOwnedSlice(gpa),
        };
    }
};

pub const Error = struct {
    tag: Tag,
    tok_i: u32,
    expected_tok: Token.Tag = .invalid,

    pub const Tag = enum {
        unknown_directive,
        invalid_register,
        expected_address_register,
        invalid_address_register_mask,

        expected_condition_register,
        invalid_condition_register_mask,

        expected_src_register,
        expected_limited_src_register,
        expected_dst_register,
        expected_bool_register,
        expected_int_register,
        expected_output_register,
        expected_uniform_register,

        invalid_mask,
        swizzled_mask,
        invalid_swizzle,
        cannot_swizzle,

        expected_number,
        number_too_big,

        expected_semantic,
        invalid_semantic_component,
        output_has_semantic,

        expected_primitive,
        expected_winding,
        expected_comparison,
        expected_condition,
        expected_boolean,
        expected_shader_type,

        redefined_label,
        undefined_label,
        label_range_too_big,

        redefined_entry,

        expected_directive_or_label_or_mnemonic,
        expected_token,
    };
};

const Directive = enum {
    /// .entry <label> (TODO: add [gsh/vsh] if gsh <point/variable/fixed> <arg>)
    entry,
    /// .out oX[.mask] <semantic>[.swizzle]
    out,
    /// .alias <name> dX[.swizzle]
    alias,
    /// .set <f/i/b>X <(X, Y, Z, W)/X>
    set,
};

const Mnemonic = enum {
    pub const Kind = enum {
        unparametized,
        unary,
        binary,
        flow_conditional,
        flow_uniform,
        comparison,
        setemit,
        mad,
    };

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

    pub fn kind(mnemonic: Mnemonic) Kind {
        return switch (mnemonic) {
            .@"break", .nop, .emit, .end => .unparametized,
            .add, .dp3, .dp4, .dph, .dst, .mul, .max, .min => .binary,
            .ex2, .lg2, .litp, .sge, .slt, .flr, .rcp, .rsq, .mova, .mov => .unary,
            .breakc, .call, .callc, .ifc, .jmpc => .flow_conditional,
            .callu, .ifu, .jmpu, .loop => .flow_uniform,
            .cmp => .comparison,
            .setemit => .setemit,
            .mad => .mad,
        };
    }

    pub fn toOpcode(mnemonic: Mnemonic) encoding.Instruction.Opcode {
        return switch (mnemonic) {
            .add => .add,
            .dp3 => .dp3,
            .dp4 => .dp4,
            .dph => .dph,
            .dst => .dst,
            .ex2 => .ex2,
            .lg2 => .lg2,
            .litp => .litp,
            .mul => .mul,
            .sge => .sge,
            .slt => .slt,
            .flr => .flr,
            .max => .max,
            .min => .min,
            .rcp => .rcp,
            .rsq => .rsq,
            .mova => .mova,
            .mov => .mov,
            .@"break" => .@"break",
            .nop => .nop,
            .end => .end,
            .breakc => .breakc,
            .call => .call,
            .callc => .callc,
            .callu => .callu,
            .ifu => .ifu,
            .ifc => .ifc,
            .loop => .loop,
            .emit => .emit,
            .setemit => .setemit,
            .jmpc => .jmpc,
            .jmpu => .jmpu,
            .cmp => .cmp,
            .mad => .mad,
        };
    }

    pub fn fromToken(tag: Token.Tag) Mnemonic {
        return switch (tag) {
            .mnemonic_add => .add,
            .mnemonic_dp3 => .dp3,
            .mnemonic_dp4 => .dp4,
            .mnemonic_dph => .dph,
            .mnemonic_dst => .dst,
            .mnemonic_ex2 => .ex2,
            .mnemonic_lg2 => .lg2,
            .mnemonic_litp => .litp,
            .mnemonic_mul => .mul,
            .mnemonic_sge => .sge,
            .mnemonic_slt => .slt,
            .mnemonic_flr => .flr,
            .mnemonic_max => .max,
            .mnemonic_min => .min,
            .mnemonic_rcp => .rcp,
            .mnemonic_rsq => .rsq,
            .mnemonic_mova => .mova,
            .mnemonic_mov => .mov,
            .mnemonic_break => .@"break",
            .mnemonic_nop => .nop,
            .mnemonic_end => .end,
            .mnemonic_breakc => .breakc,
            .mnemonic_call => .call,
            .mnemonic_callc => .callc,
            .mnemonic_callu => .callu,
            .mnemonic_ifu => .ifu,
            .mnemonic_ifc => .ifc,
            .mnemonic_loop => .loop,
            .mnemonic_emit => .emit,
            .mnemonic_setemit => .setemit,
            .mnemonic_jmpc => .jmpc,
            .mnemonic_jmpu => .jmpu,
            .mnemonic_cmp => .cmp,
            .mnemonic_mad => .mad,
            else => unreachable,
        };
    }
};

const UniformRegister = enum(u8) {
    // zig fmt: off
    f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15,
    f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29,
    f30, f31, f32, f33, f34, f35, f36, f37, f38, f39, f40, f41, f42, f43,
    f44, f45, f46, f47, f48, f49, f50, f51, f52, f53, f54, f55, f56, f57,
    f58, f59, f60, f61, f62, f63, f64, f65, f66, f67, f68, f69, f70, f71,
    f72, f73, f74, f75, f76, f77, f78, f79, f80, f81, f82, f83, f84, f85,
    f86, f87, f88, f89, f90, f91, f92, f93, f94, f95,
    i0, i1, i2, i3,
    b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15,
    // zig fmt: on
};

const Semantic = enum {
    /// xyzw
    position,
    /// xyzw
    normal_quaternion,
    /// xyzw
    color,
    /// xyz
    texture_coordinate_0,
    /// xy
    texture_coordinate_1,
    /// xy
    texture_coordinate_2,
    /// xyzw
    view,
    /// xyzw
    dummy,

    pub fn native(semantic: Semantic) [4]pica.OutputMap.Semantic {
        return switch (semantic) {
            .position => .{ .position_x, .position_y, .position_z, .position_w },
            .normal_quaternion => .{ .normal_quaternion_x, .normal_quaternion_y, .normal_quaternion_z, .normal_quaternion_w },
            .color => .{ .color_r, .color_g, .color_b, .color_a },
            .texture_coordinate_0 => .{ .texture_coordinate_0_u, .texture_coordinate_0_v, .texture_coordinate_0_w, .unused },
            .texture_coordinate_1 => .{ .texture_coordinate_1_u, .texture_coordinate_1_v, .unused, .unused },
            .texture_coordinate_2 => .{ .texture_coordinate_2_u, .texture_coordinate_2_v, .unused, .unused },
            .view => .{ .view_x, .view_y, .view_z, .unused },
            .dummy => .{ .unused, .unused, .unused, .unused },
        };
    }
};

const Alias = packed struct(u16) {
    pub const Map = std.StringArrayHashMapUnmanaged(Alias);

    pub const Register = enum(u8) {
        // zig fmt: off
        v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15,
        r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15,

        f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15,
        f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29,
        f30, f31, f32, f33, f34, f35, f36, f37, f38, f39, f40, f41, f42, f43,
        f44, f45, f46, f47, f48, f49, f50, f51, f52, f53, f54, f55, f56, f57,
        f58, f59, f60, f61, f62, f63, f64, f65, f66, f67, f68, f69, f70, f71,
        f72, f73, f74, f75, f76, f77, f78, f79, f80, f81, f82, f83, f84, f85,
        f86, f87, f88, f89, f90, f91, f92, f93, f94, f95,

        i0, i1, i2, i3, 
        b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15,

        o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10, o11, o12, o13, o14, o15,
        // zig fmt: on
    };

    register: Register,
    swizzle: Component.Selector,

    pub const SourceSwizzlePair = struct { register.Source, Component.Selector };

    pub fn toSourceRegister(aliased: Alias) ?SourceSwizzlePair {
        return switch (@intFromEnum(aliased.register)) {
            @intFromEnum(Register.v0)...@intFromEnum(Register.v15) => .{ .initInput(@enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.v0))), aliased.swizzle },
            @intFromEnum(Register.r0)...@intFromEnum(Register.r15) => .{ .initTemporary(@enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.r0))), aliased.swizzle },
            @intFromEnum(Register.f0)...@intFromEnum(Register.f95) => .{ .initConstant(@enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.f0))), aliased.swizzle },
            else => null,
        };
    }

    pub fn toDestinationRegister(aliased: Alias) ?register.Destination {
        return switch (@intFromEnum(aliased.register)) {
            @intFromEnum(Register.o0)...@intFromEnum(Register.o15) => .initOutput(@enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.o0))),
            @intFromEnum(Register.r0)...@intFromEnum(Register.r15) => if (aliased.swizzle != Component.Selector.xyzw) null else .initTemporary(@enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.r0))),
            else => null,
        };
    }

    pub fn toIntegerRegister(aliased: Alias) ?register.Integral.Integer {
        return switch (@intFromEnum(aliased.register)) {
            @intFromEnum(Register.i0)...@intFromEnum(Register.i3) => @enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.i0)),
            else => null,
        };
    }

    pub fn toBooleanRegister(aliased: Alias) ?register.Integral.Boolean {
        return switch (@intFromEnum(aliased.register)) {
            @intFromEnum(Register.b0)...@intFromEnum(Register.b15) => @enumFromInt(@intFromEnum(aliased.register) - @intFromEnum(Register.b0)),
            else => null,
        };
    }
};

gpa: std.mem.Allocator,
aliases: Alias.Map,
errors: std.ArrayListUnmanaged(Error),
source: [:0]const u8,
tokens: TokenList.Slice,
encoder: Encoder,
labels: LabelMap,
entrypoints: EntrypointMap,
outputs: Outputs,
flt_const: FloatingConstants,
int_const: IntegerConstants,
bool_const: BooleanConstants,
tok_i: u32,
inst_i: u12,

pub fn deinit(a: *Assembler, gpa: std.mem.Allocator) void {
    a.errors.deinit(gpa);
    a.labels.deinit(gpa);
    a.entrypoints.deinit(gpa);
    a.encoder.deinit(gpa);
    a.aliases.deinit(gpa);
    a.* = undefined;
}

pub fn tokenTag(a: Assembler, tok_index: usize) Token.Tag {
    return a.tokens.items(.tag)[tok_index];
}

pub fn tokenStart(a: Assembler, tok_index: usize) u32 {
    return a.tokens.items(.start)[tok_index];
}

pub fn tokenSlice(a: Assembler, tok_index: usize) []const u8 {
    const tok_tag = a.tokenTag(tok_index);

    if (tok_tag.lexeme()) |lexeme| {
        return lexeme;
    }

    const tok_start = a.tokenStart(tok_index);
    var tokenizer: shader.as.Tokenizer = .{
        .buffer = a.source,
        .index = tok_start,
    };

    const tok = tokenizer.next();
    std.debug.assert(tok.tag == tok_tag);
    return a.source[tok.loc.start..tok.loc.end];
}

/// Does a pass to process labels and directives.
pub fn passRoot(a: *Assembler) !void {
    a.tok_i = 0;
    a.inst_i = 0;

    root: switch (a.tokenTag(a.tok_i)) {
        .eof => {},
        .newline => {
            _ = a.nextToken();
            continue :root a.tokenTag(a.tok_i);
        },
        .invalid, .minus, .number_literal, .comma, .l_paren, .r_paren, .l_square, .r_square, .colon, .@"true", .@"false" => {
            _ = try a.warn(.expected_directive_or_label_or_mnemonic);
            _ = a.nextToken();
            continue :root a.tokenTag(a.tok_i);
        },
        .identifier => {
            try a.processLabel();
            continue :root a.tokenTag(a.tok_i);
        },
        .dot => {
            a.processDirective() catch |e| switch (e) {
                error.ParseError => a.eatUntil(.newline),
                else => return e,
            };
            continue :root a.tokenTag(a.tok_i);
        },
        .mnemonic_add, .mnemonic_dp3, .mnemonic_dp4, .mnemonic_dph, .mnemonic_dst, .mnemonic_ex2, .mnemonic_lg2, .mnemonic_litp, .mnemonic_mul, .mnemonic_sge, .mnemonic_slt, .mnemonic_flr, .mnemonic_max, .mnemonic_min, .mnemonic_rcp, .mnemonic_rsq, .mnemonic_mova, .mnemonic_mov, .mnemonic_break, .mnemonic_nop, .mnemonic_end, .mnemonic_breakc, .mnemonic_call, .mnemonic_callc, .mnemonic_callu, .mnemonic_ifu, .mnemonic_ifc, .mnemonic_loop, .mnemonic_emit, .mnemonic_setemit, .mnemonic_jmpc, .mnemonic_jmpu, .mnemonic_cmp, .mnemonic_mad => {
            a.inst_i += 1;
            a.eatUntil(.newline);
            continue :root a.tokenTag(a.tok_i);
        },
    }
}

/// Does a second pass to encode all mnemonics
pub fn passAssemble(a: *Assembler) !void {
    a.tok_i = 0;
    a.inst_i = 0;

    root: switch (a.tokenTag(a.tok_i)) {
        .eof => {},
        .newline => {
            _ = a.nextToken();
            continue :root a.tokenTag(a.tok_i);
        },
        .invalid, .minus, .number_literal, .comma, .l_paren, .r_paren, .l_square, .r_square, .colon, .@"true", .@"false"=> unreachable,
        .identifier => {
            _ = a.nextToken();
            _ = a.nextToken();
            continue :root a.tokenTag(a.tok_i);
        },
        .dot => {
            a.eatUntil(.newline);
            continue :root a.tokenTag(a.tok_i);
        },
        .mnemonic_add, .mnemonic_dp3, .mnemonic_dp4, .mnemonic_dph, .mnemonic_dst, .mnemonic_ex2, .mnemonic_lg2, .mnemonic_litp, .mnemonic_mul, .mnemonic_sge, .mnemonic_slt, .mnemonic_flr, .mnemonic_max, .mnemonic_min, .mnemonic_rcp, .mnemonic_rsq, .mnemonic_mova, .mnemonic_mov, .mnemonic_break, .mnemonic_nop, .mnemonic_end, .mnemonic_breakc, .mnemonic_call, .mnemonic_callc, .mnemonic_callu, .mnemonic_ifu, .mnemonic_ifc, .mnemonic_loop, .mnemonic_emit, .mnemonic_setemit, .mnemonic_jmpc, .mnemonic_jmpu, .mnemonic_cmp, .mnemonic_mad, => |mne_tok| {
            defer a.inst_i += 1;
            _ = a.nextToken();

            a.assembleMnemonic(.fromToken(mne_tok)) catch |e| switch(e) {
                error.ParseError => a.eatUntil(.newline),
                else => return e,
            };

            if(a.tokenTag(a.tok_i) != .eof) {
                _ = try a.expectToken(.newline);
            }

            continue :root a.tokenTag(a.tok_i);
        },
    }
}

// TODO: relative component handling
fn assembleMnemonic(a: *Assembler, mnemonic: Mnemonic) !void {
    const opcode = mnemonic.toOpcode();

    switch (mnemonic.kind()) {
        .unparametized => try a.encoder.unparametized(a.gpa, opcode),
        .unary => {
            const dest: register.Destination, const dst_mask: Component.Mask, const src1_neg: Encoder.Negate, const src1: register.Source, const src1_selector: Component.Selector, const src_rel: register.RelativeComponent = switch (opcode) {
                .mova => mova: {
                    const address_reg = try a.parseMaskedIdentifier();
                    const address_slice = a.tokenSlice(address_reg.identifier_tok_i);

                    if(!std.mem.eql(u8, address_slice, "a")) {
                        return a.failMsg(.{ .tag = .expected_address_register, .tok_i = address_reg.identifier_tok_i });
                    }

                    if(address_reg.mask.enable_z or address_reg.mask.enable_w) {
                        return a.failMsg(.{ .tag = .invalid_address_register_mask, .tok_i = address_reg.identifier_tok_i });
                    }

                    _ = try a.expectToken(.comma);

                    const src_info = try a.parseSourceRegister();

                    break :mova .{ .o0, address_reg.mask, src_info.negated, src_info.src, src_info.swizzle, .none };
                },
                else => unary: {
                    const dst_info = try a.parseDestinationRegister();
                    _ = try a.expectToken(.comma);
                    const src_info = try a.parseSourceRegister();
                    
                    break :unary .{ dst_info.dst, dst_info.mask, src_info.negated, src_info.src, src_info.swizzle, .none };
                },
            };

            try a.encoder.unary(a.gpa, opcode, dest, dst_mask, src1_neg, src1, src1_selector, src_rel);
        },
        .binary => {
            const dst_info = try a.parseDestinationRegister();
            _ = try a.expectToken(.comma);
            const src1_info = try a.parseSourceRegister();
            _ = try a.expectToken(.comma);
            const src2_info = try a.parseSourceRegister();

            try a.encoder.binary(a.gpa, opcode, dst_info.dst, dst_info.mask, src1_info.negated, src1_info.src, src1_info.swizzle, src2_info.negated, src2_info.src, src2_info.swizzle, .none);
        },
        .flow_conditional => {
            const num: u8, const dest: u12, const condition: encoding.Condition, const x: bool, const y: bool = values: switch (opcode) {
                .breakc => {
                    const condition = try a.parseEnum(encoding.Condition, .expected_condition);                 
                    _ = try a.expectToken(.comma);
                    const x = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const y = try a.parseBoolean();

                    break :values .{ 0, 0, condition, x, y };
                },
                .call => {
                    const label_range = try a.parseLabelRange();
                    break :values .{ label_range.num, label_range.dest, .@"and", false, false };
                },
                .jmpc => {
                    const condition = try a.parseEnum(encoding.Condition, .expected_condition);                 
                    _ = try a.expectToken(.comma);
                    const x = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const y = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const dest = try a.parseLabel();

                    break :values .{ 0, dest.offset, condition, x, y };
                },
                else => {
                    const condition = try a.parseEnum(encoding.Condition, .expected_condition);                 
                    _ = try a.expectToken(.comma);
                    const x = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const y = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const label_range = try a.parseLabelRange();

                    break :values .{ label_range.num, label_range.dest, condition, x, y };
                },
            };

            try a.encoder.flow(a.gpa, opcode, num, dest, condition, x, y);
        },
        .flow_uniform => {
            const i_reg: register.Integral, const num: u8, const dest: u12 = values: switch (opcode) {
                .loop => {
                    const int_info = try a.parseIntegerRegister();
                    _ = try a.expectToken(.comma);
                    const end = try a.parseLabel();

                    break :values .{ .{ .int = .{ .used = int_info.int } }, 0, end.offset - 1 };
                },
                .jmpu => {
                    const b_info = try a.parseBooleanRegister();
                    _ = try a.expectToken(.comma);
                    const if_true = try a.parseBoolean();
                    _ = try a.expectToken(.comma);
                    const dest = try a.parseLabel();

                    break :values .{ .{ .bool = b_info.bool }, @intFromBool(!if_true), dest.offset };
                },
                else => {
                    const b_info = try a.parseBooleanRegister();
                    _ = try a.expectToken(.comma);
                    const label_range = try a.parseLabelRange();

                    break :values .{ .{ .bool = b_info.bool }, label_range.num, label_range.dest }; 
                },
            };

            try a.encoder.flowConstant(a.gpa, opcode, num, dest, i_reg);
        },
        .comparison => {
            const src1_info = try a.parseSourceRegister();
            _ = try a.expectToken(.comma);
            const src2_info = try a.parseSourceRegister();
            _ = try a.expectToken(.comma);
            const x = try a.parseEnum(encoding.ComparisonOperation, .expected_comparison);
            _ = try a.expectToken(.comma);
            const y = try a.parseEnum(encoding.ComparisonOperation, .expected_comparison);

            try a.encoder.cmp(a.gpa, src1_info.negated, src1_info.src, src1_info.swizzle, src2_info.negated, src2_info.src, src2_info.swizzle, .none, x, y);
        },
        .setemit => {
            const vtx_id = try a.parseInt(u2, 2);
            _ = try a.expectToken(.comma);
            const primitive = try a.parseEnum(encoding.Primitive, .expected_primitive);
            _ = try a.expectToken(.comma);
            const winding = try a.parseEnum(encoding.Winding, .expected_winding);

            try a.encoder.setemit(a.gpa, vtx_id, primitive, winding);
        },
        .mad => {
            const dst_info = try a.parseDestinationRegister();
            _ = try a.expectToken(.comma);
            const src1_info = try a.parseSourceRegister();
            _ = try a.expectToken(.comma);
            const src2_info = try a.parseSourceRegister(); 
            _ = try a.expectToken(.comma);
            const src3_info = try a.parseSourceRegister(); 

            const src1_limited = if(src1_info.src.toLimited()) |src1_lim|
                src1_lim
            else return a.failMsg(.{ .tag = .expected_limited_src_register, .tok_i = src1_info.register_tok_i });

            try a.encoder.mad(a.gpa, dst_info.dst, dst_info.mask, src1_info.negated, src1_limited, src1_info.swizzle, src2_info.negated, src2_info.src, src2_info.swizzle, src3_info.negated, src3_info.src, src3_info.swizzle, .none);
        },
    }
}

fn processLabel(a: *Assembler) !void {
    const label = a.tokenSlice(a.tok_i);
    
    if(a.labels.get(label) != null) {
        try a.warn(.redefined_label);
    }

    _ = a.nextToken();
    _ = try a.expectToken(.colon);

    try a.labels.put(a.gpa, label, a.inst_i);
}

fn processDirective(a: *Assembler) !void {
    _ = a.nextToken();
    const directive_tok_i = try a.expectToken(.identifier);
    const directive_slice = a.tokenSlice(directive_tok_i);

    if (std.meta.stringToEnum(Directive, directive_slice)) |directive| {
        switch (directive) {
            .entry => {
                const entry_label_tok_i = try a.expectToken(.identifier);
                const entry_label = a.tokenSlice(entry_label_tok_i);

                if(a.entrypoints.get(entry_label) != null) {
                    return a.failMsg(.{
                        .tag = .redefined_entry,
                        .tok_i = entry_label_tok_i,
                    });
                } 

                const entry_type = try a.parseEnum(shader.Type, .expected_shader_type);

                if(entry_type == .geometry) @panic("TODO: Geometry shaders");

                try a.entrypoints.put(a.gpa, entry_label, .{
                    .info = .vertex,
                    .tok_i = entry_label_tok_i,
                });
            },
            .out => {
                const output_masked = try a.parseMaskedIdentifier();
                const output_slice = a.tokenSlice(output_masked.identifier_tok_i);

                const output_reg = std.meta.stringToEnum(register.Destination.Output, output_slice) orelse return a.failMsg(.{
                    .tag = .expected_output_register,
                    .tok_i = output_masked.identifier_tok_i,
                });

                const semantic_swizzled = try a.parseSwizzledIdentifier();

                const semantic_slice = a.tokenSlice(semantic_swizzled.identifier_tok_i);

                const semantic = std.meta.stringToEnum(Semantic, semantic_slice) orelse return a.failMsg(.{
                    .tag = .expected_semantic,
                    .tok_i = semantic_swizzled.identifier_tok_i,
                });

                const native_semantics = semantic.native();
                const swizzled_semantics = sw: {
                    var sw: [4]pica.OutputMap.Semantic = undefined;

                    inline for (&.{semantic_swizzled.swizzle.@"0", semantic_swizzled.swizzle.@"1", semantic_swizzled.swizzle.@"2", semantic_swizzled.swizzle.@"3"}, 0..) |f, i| {
                        sw[i] = native_semantics[@intFromEnum(f)]; 
                    }

                    break :sw sw;
                };
                
                var current_output_map: pica.OutputMap = a.outputs.get(output_reg) orelse .{
                    .x = .unused,
                    .y = .unused,
                    .z = .unused,
                    .w = .unused,
                };

                var current_semantic: usize = 0;
                inline for (0..4) |i| {
                    const output, const enabled = switch (i) {
                        0 => .{ &current_output_map.x, output_masked.mask.enable_x }, 
                        1 => .{ &current_output_map.y, output_masked.mask.enable_y }, 
                        2 => .{ &current_output_map.z, output_masked.mask.enable_z }, 
                        3 => .{ &current_output_map.w, output_masked.mask.enable_w }, 
                        else => unreachable,
                    };

                    if(enabled) {
                        if(native_semantics[current_semantic] != swizzled_semantics[current_semantic] and swizzled_semantics[current_semantic] == .unused) {
                            return a.failMsg(.{
                                .tag = .invalid_semantic_component,
                                .tok_i = semantic_swizzled.identifier_tok_i,
                            });
                        } else if(output.* != .unused) {
                            return a.failMsg(.{
                                .tag = .output_has_semantic,
                                .tok_i = output_masked.identifier_tok_i,
                            });
                        }

                        output.* = swizzled_semantics[current_semantic];
                        current_semantic += 1;
                    }
                }

                a.outputs.put(output_reg, current_output_map);
            },
            .set => {
                const uniform_reg = try a.parseEnum(UniformRegister, .expected_uniform_register);

                switch (@intFromEnum(uniform_reg)) {
                    @intFromEnum(UniformRegister.f0)...@intFromEnum(UniformRegister.f95) => {
                        _ = try a.expectToken(.l_paren);
                        const x = try a.parseFloat();
                        _ = try a.expectToken(.comma);
                        const y = try a.parseFloat();
                        _ = try a.expectToken(.comma);
                        const z = try a.parseFloat();
                        _ = try a.expectToken(.comma);
                        const w = try a.parseFloat();
                        _ = try a.expectToken(.r_paren);

                        const f_reg: register.Source.Constant = @enumFromInt(@intFromEnum(uniform_reg) - @intFromEnum(UniformRegister.f0));
                        a.flt_const.put(f_reg, .pack(.of(x), .of(y), .of(z), .of(w)));
                    },
                    @intFromEnum(UniformRegister.i0)...@intFromEnum(UniformRegister.i3) => {
                        _ = try a.expectToken(.l_paren);
                        const x = try a.parseInt(i8, 127);
                        _ = try a.expectToken(.comma);
                        const y = try a.parseInt(i8, 127);
                        _ = try a.expectToken(.comma);
                        const z = try a.parseInt(i8, 127);
                        _ = try a.expectToken(.comma);
                        const w = try a.parseInt(i8, 127);
                        _ = try a.expectToken(.r_paren);

                        const i_reg: register.Integral.Integer = @enumFromInt(@intFromEnum(uniform_reg) - @intFromEnum(UniformRegister.i0));
                        a.int_const.put(i_reg, .{ x, y, z, w});
                    },
                    @intFromEnum(UniformRegister.b0)...@intFromEnum(UniformRegister.b15) => {
                        const b_reg: register.Integral.Boolean = @enumFromInt(@intFromEnum(uniform_reg) - @intFromEnum(UniformRegister.b0));
                        const b_value = try a.parseBoolean();

                        a.bool_const.setPresent(b_reg, b_value);
                    },
                    else => unreachable,
                }
            },
            .alias => {
                const alias_identifier_tok_i = try a.expectToken(.identifier);
                const alias_slice = a.tokenSlice(alias_identifier_tok_i);

                const swizzled_identifier = try a.parseSwizzledIdentifier();
                const aliased_slice = a.tokenSlice(swizzled_identifier.identifier_tok_i);

                const aliased_reg: Alias.Register = std.meta.stringToEnum(Alias.Register, aliased_slice) orelse {
                    try a.warnMsg(.{
                        .tag = .invalid_register,
                        .tok_i = swizzled_identifier.identifier_tok_i,
                    });

                    return a.eatUntil(.newline);
                };

                if (swizzled_identifier.swizzle != Component.Selector.xyzw) switch (@intFromEnum(aliased_reg)) {
                    @intFromEnum(Alias.Register.o0)...@intFromEnum(Alias.Register.o15), @intFromEnum(Alias.Register.i0)...@intFromEnum(Alias.Register.i3), @intFromEnum(Alias.Register.b0)...@intFromEnum(Alias.Register.b15) => {
                        try a.warnMsg(.{
                            .tag = .cannot_swizzle,
                            .tok_i = swizzled_identifier.identifier_tok_i,
                        });

                        return a.eatUntil(.newline);
                    },
                    else => {},
                };

                try a.aliases.put(a.gpa, alias_slice, .{
                    .register = aliased_reg,
                    .swizzle = swizzled_identifier.swizzle,
                });
            },
        }
    } else {
        try a.warn(.unknown_directive);
        a.eatUntil(.newline);
    }
}

const SourceRegisterInfo = struct {
    register_tok_i: u32,

    negated: Encoder.Negate,
    src: register.Source,
    swizzle: Component.Selector,
};

fn parseSourceRegister(a: *Assembler) !SourceRegisterInfo {
    const negated: Encoder.Negate = if (a.tokenTag(a.tok_i) == .minus) negated: {
        _ = a.nextToken();
        break :negated .@"-";
    } else .@"+";

    const parsed_src = try a.parseSwizzledIdentifier();
    const src_slice = a.tokenSlice(parsed_src.identifier_tok_i);

    const src: register.Source, const initial_swizzle: Component.Selector = if (a.aliases.get(src_slice)) |alias| aliased: {
        if (alias.toSourceRegister()) |src_pair| {
            break :aliased src_pair;
        } else return a.failMsg(.{ .tag = .expected_src_register, .tok_i = parsed_src.identifier_tok_i });
    } else .{ register.Source.parse(src_slice) catch return a.failMsg(.{ .tag = .expected_src_register, .tok_i = parsed_src.identifier_tok_i }), .xyzw };

    return .{
        .register_tok_i = parsed_src.identifier_tok_i,
        .negated = negated,
        .src = src,
        .swizzle = initial_swizzle.swizzle(parsed_src.swizzle),
    };
}

const DestinationRegisterInfo = struct {
    register_tok_i: u32,
    
    dst: register.Destination,
    mask: Component.Mask,
};

fn parseDestinationRegister(a: *Assembler) !DestinationRegisterInfo {
    const parsed_dst = try a.parseMaskedIdentifier();
    const dst_slice = a.tokenSlice(parsed_dst.identifier_tok_i);

    const dst: register.Destination = if (a.aliases.get(dst_slice)) |alias| aliased: {
        if (alias.toDestinationRegister()) |dst| {
            break :aliased dst;
        } else return a.failMsg(.{ .tag = .expected_dst_register, .tok_i = parsed_dst.identifier_tok_i });
    } else register.Destination.parse(dst_slice) catch return a.failMsg(.{ .tag = .expected_dst_register, .tok_i = parsed_dst.identifier_tok_i });

    return .{
        .register_tok_i = parsed_dst.identifier_tok_i,
        .dst = dst,
        .mask = parsed_dst.mask,
    };
}

const BooleanRegisterInfo = struct {
    register_tok_i: u32,
    bool: register.Integral.Boolean,
};

fn parseBooleanRegister(a: *Assembler) !BooleanRegisterInfo{
    const b_tok_i = try a.expectToken(.identifier);
    const b_slice = a.tokenSlice(b_tok_i);

    const b: register.Integral.Boolean = if (a.aliases.get(b_slice)) |alias| aliased: {
        if (alias.toBooleanRegister()) |b| {
            break :aliased b;
        } else return a.failMsg(.{ .tag = .expected_bool_register, .tok_i = b_tok_i });
    } else std.meta.stringToEnum(register.Integral.Boolean, b_slice) orelse return a.failMsg(.{ .tag = .expected_bool_register, .tok_i = b_tok_i });

    return .{
        .register_tok_i = b_tok_i,
        .bool = b,
    };
}

const IntegerRegisterInfo = struct {
    register_tok_i: u32,
    int: register.Integral.Integer,
};

fn parseIntegerRegister(a: *Assembler) !IntegerRegisterInfo {
    const int_tok_i = try a.expectToken(.identifier);
    const int_slice = a.tokenSlice(int_tok_i);

    const int: register.Integral.Integer = if (a.aliases.get(int_slice)) |alias| aliased: {
        if (alias.toIntegerRegister()) |int| {
            break :aliased int;
        } else return a.failMsg(.{ .tag = .expected_int_register, .tok_i = int_tok_i });
    } else std.meta.stringToEnum(register.Integral.Integer, int_slice) orelse return a.failMsg(.{ .tag = .expected_int_register, .tok_i = int_tok_i });

    return .{
        .register_tok_i = int_tok_i,
        .int = int,
    };
}

const MaskedIdentifier = struct {
    identifier_tok_i: u32,
    mask: Component.Mask,
};

fn parseMaskedIdentifier(a: *Assembler) !MaskedIdentifier {
    const idenfier_tok_i = try a.expectToken(.identifier);

    const mask: Component.Mask = if (a.tokenTag(a.tok_i) == .dot) mask: {
        _ = a.nextToken();

        const mask_tok_i = try a.expectToken(.identifier);
        const mask_slice = a.tokenSlice(mask_tok_i);
        const mask = Component.Mask.parse(mask_slice) catch |e| {
            return a.failMsg(.{
                .tag = switch (e) {
                    error.Syntax, error.InvalidComponent => .invalid_mask,
                    error.InvalidMask => .swizzled_mask,
                },
                .tok_i = mask_tok_i,
            });
        };

        break :mask mask;
    } else .xyzw;

    return .{
        .identifier_tok_i = idenfier_tok_i,
        .mask = mask,
    };
}

const SwizzledIdentifier = struct {
    identifier_tok_i: u32,
    swizzle: Component.Selector,
};

fn parseSwizzledIdentifier(a: *Assembler) !SwizzledIdentifier {
    const idenfier_tok_i = try a.expectToken(.identifier);
    var swizzle: Component.Selector = .xyzw;

    while (a.tokenTag(a.tok_i) == .dot) {
        _ = a.nextToken();

        const swizzle_tok_i = try a.expectToken(.identifier);
        const swizzle_slice = a.tokenSlice(swizzle_tok_i);
        const new_swizzle = Component.Selector.parse(swizzle_slice) catch |e| {
            return a.failMsg(.{
                .tag = switch (e) {
                    error.Syntax, error.InvalidComponent => .invalid_swizzle,
                },
                .tok_i = swizzle_tok_i,
            });
        };

        swizzle = swizzle.swizzle(new_swizzle);
    }

    return .{
        .identifier_tok_i = idenfier_tok_i,
        .swizzle = swizzle,
    };
}

pub const LabelInfo = struct {
    tok_i: u32,
    offset: u12,
};

fn parseLabel(a: *Assembler) !LabelInfo {
    const label_tok_i = try a.expectToken(.identifier);
    const label_slice = a.tokenSlice(label_tok_i);

    if(a.labels.get(label_slice)) |offset| {
        return .{
            .tok_i = label_tok_i,
            .offset = offset,
        };
    }

    return a.failMsg(.{
        .tag = .undefined_label,
        .tok_i = label_tok_i,
    });
}

pub const LabelRangeInfo = struct {
    dest: u12,
    num: u8,
};

fn parseLabelRange(a: *Assembler) !LabelRangeInfo {
    const start_info = try a.parseLabel();
    _ = try a.expectToken(.comma);
    const end_info = try a.parseLabel();

    const num_instructions = end_info.offset - start_info.offset;

    if(num_instructions > std.math.maxInt(u8)) {
        return a.failMsg(.{
            .tag = .label_range_too_big,
            .tok_i = end_info.tok_i,
        });
    }

    return .{
        .dest = @intCast(start_info.offset),
        .num = @intCast(num_instructions),
    };
}

fn parseInt(a: *Assembler, comptime T: type, max_value: T) !T {
    const negate: i2 = if(a.tokenTag(a.tok_i) == .minus) neg: {
        if(@typeInfo(T).int.signedness == .unsigned) return a.fail(.expected_number);

        _ = a.nextToken();
        break :neg -1;
    } else 1;

    const number_literal_tok = try a.expectToken(.number_literal); 
    const number_literal_slice = a.tokenSlice(number_literal_tok);

    const int = std.fmt.parseInt(T, number_literal_slice, 0) catch |e| return a.failMsg(.{
        .tag = switch(e) {
            error.InvalidCharacter => .expected_number,
            error.Overflow => .number_too_big,
        },
        .tok_i = number_literal_tok,
    });

    if(int > max_value) {
        return a.failMsg(.{
            .tag = .number_too_big,
            .tok_i = number_literal_tok,
        });
    }

    return @intCast(int * negate);
}

fn parseFloat(a: *Assembler) !f32 {
    const negate: f32 = if(a.tokenTag(a.tok_i) == .minus) neg: {
        _ = a.nextToken();
        break :neg -1.0;
    } else 1.0;

    const number_literal_tok = try a.expectToken(.number_literal); 
    const number_literal_slice = a.tokenSlice(number_literal_tok);

    return negate * (std.fmt.parseFloat(f32, number_literal_slice) catch |e| switch (e) {
        error.InvalidCharacter => return a.failMsg(.{
            .tag = .expected_number,
            .tok_i = number_literal_tok,
        }),
        else => return e,
    });
}

fn parseEnum(a: *Assembler, comptime T: type, error_tag: Error.Tag) !T {
    const enum_tok_i = try a.expectToken(.identifier);
    
    return if(std.meta.stringToEnum(T, a.tokenSlice(enum_tok_i))) |enum_value| 
        enum_value
    else return a.failMsg(.{ .tag = error_tag, .tok_i = enum_tok_i });
}

fn parseBoolean(a: *Assembler) !bool {
    return switch (a.tokenTag(a.tok_i)) {
        .@"true" => {
            _ = a.nextToken();
            return true;
        },
        .@"false" => {
            _ = a.nextToken();
            return false;
        },
        else => a.failMsg(.{
            .tag = .expected_boolean,
            .tok_i = a.tok_i,
        })
    };
}

fn fail(a: *Assembler, tag: Error.Tag) error{ OutOfMemory, ParseError } {
    @branchHint(.cold);
    return a.failMsg(.{ .tag = tag, .tok_i = a.tok_i });
}

fn failMsg(a: *Assembler, msg: Error) error{ OutOfMemory, ParseError } {
    @branchHint(.cold);
    try a.errors.append(a.gpa, msg);
    return error.ParseError;
}

fn warn(a: *Assembler, tag: Error.Tag) !void {
    @branchHint(.cold);
    try a.warnMsg(.{ .tag = tag, .tok_i = a.tok_i });
}

fn warnMsg(a: *Assembler, msg: Error) !void {
    @branchHint(.cold);
    try a.errors.append(a.gpa, msg);
}

fn eatUntil(a: *Assembler, tag: Token.Tag) void {
    while (true) {
        const current_tag = a.tokenTag(a.tok_i);

        switch (current_tag) {
            .eof => break,
            else => |non_eof| if (non_eof == tag)
                break
            else {
                _ = a.nextToken();
            },
        }
    }
}

fn expectToken(a: *Assembler, tag: Token.Tag) !u32 {
    if (a.tokenTag(a.tok_i) != tag) {
        return a.failMsg(.{
            .tag = .expected_token,
            .tok_i = a.tok_i,
            .expected_tok = tag,
        });
    }

    return a.nextToken();
}

fn nextToken(a: *Assembler) u32 {
    defer a.tok_i += 1;
    return a.tok_i;
}

test "assemble" {
    var assembled: Assembled = try .assemble(std.testing.allocator,
        \\ main:
        \\   mov o0, v1
        \\   mov r0, v2
        \\   end
    ); 
    defer assembled.deinit(std.testing.allocator);

    for(assembled.errors) |err| {
        if(err.tag == .expected_token) {
            std.debug.print("Error: {s} (token value: '{s}', expected: {s})\n{s}", .{@tagName(err.tag), assembled.tokenSlice(err.tok_i), @tagName(err.expected_tok), assembled.source[assembled.tokenStart(err.tok_i)..]});
        } else std.debug.print("Error: {s} (token value: {s})\n{s}", .{@tagName(err.tag), assembled.tokenSlice(err.tok_i), assembled.source[assembled.tokenStart(err.tok_i)..]});
    }

    if(assembled.errors.len > 0) {
        return error.ParseError;
    }
}

const Assembler = @This();

const std = @import("std");
const zitrus = @import("zitrus");
const pica = zitrus.pica;
const shader = zitrus.pica.shader;

const encoding = shader.encoding;
const Component = encoding.Component;

const register = shader.register;

const Encoder = shader.Encoder;
const Token = shader.as.Token;
