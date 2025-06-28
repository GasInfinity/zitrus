// TODO:
// - Handle assembler correctness
// - Diagnostic reporting

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

const OperandKind = enum {
    dst,
    src,
    src_limited,
    src_boolean,
    src_integer,
    condition,
    bit,
    comparison,
    label,
    label_exclusive,
    label_relative_last,
    vertex_id,
    winding,
    primitive,
};

const Directive = enum {
    /// .entry <label> (TODO: add [gsh/vsh] if gsh <point/variable/fixed> <arg>)
    entry,
    /// .in vX
    in,
    /// .out oX <semantic>
    out,
    /// .alias <name> dX[.swizzle]
    alias,
    /// .set <name> <f/i/b>X <(X, Y, Z, W)/X>
    set,
};

const AliasedRegister = union(Kind) {
    const Kind = enum {
        input,
        temporary,
        floating_constant,
        output,
        integer_constant,
        boolean_constant,
    };

    fn SwizzableRegister(comptime Register: type) type {
        return struct {
            register: Register,
            selector: Component.Selector,
        };
    }

    input: SwizzableRegister(SourceRegister.Input),
    temporary: SwizzableRegister(TemporaryRegister),
    floating_constant: SwizzableRegister(SourceRegister.Constant),
    output: DestinationRegister.Output,
    integer_constant: IntegerRegister,
    boolean_constant: BooleanRegister,

    pub const SourceSwizzlePair = struct { SourceRegister, Component.Selector };

    pub fn toSourceRegister(aliased: AliasedRegister) ?SourceSwizzlePair {
        return switch (aliased) {
            .input => |v| .{ .initInput(v.register), v.selector },
            .temporary => |t| .{ .initTemporary(t.register), t.selector },
            .floating_constant => |f| .{ .initConstant(f.register), f.selector },
            else => null,
        };
    }

    pub fn toDestinationRegister(aliased: AliasedRegister) ?DestinationRegister {
        return switch (aliased) {
            .output => |o| .initOutput(o),
            .temporary => |t| if (!std.meta.eql(t.selector, .xyzw)) null else .initTemporary(t.register),
            else => null,
        };
    }

    pub fn toIntegerRegister(aliased: AliasedRegister) ?IntegerRegister {
        return switch (aliased) {
            .integer_constant => |i| i,
            else => null,
        };
    }

    pub fn toBooleanRegister(aliased: AliasedRegister) ?BooleanRegister {
        return switch (aliased) {
            .boolean_constant => |b| b,
            else => null,
        };
    }

    pub fn parse(expression: []const u8) !AliasedRegister {
        if (expression.len < 2 or !std.ascii.isAlphabetic(expression[0]) or !std.ascii.isDigit(expression[1])) {
            return error.Syntax;
        }

        const reg_type: Kind = @enumFromInt(mem.indexOfScalar(u8, "vrfoib", expression[0]) orelse return error.InvalidRegister);
        const reg_index_swzl = expression[1..];

        return switch (reg_type) {
            inline .input, .temporary, .floating_constant => |kind| alias: {
                const swizzle: Component.Selector, const reg_end_idx: usize = if (mem.indexOfScalar(u8, reg_index_swzl, '.')) |dot|
                    .{ try Component.Selector.parseSequential(reg_index_swzl[(dot + 1)..]), dot }
                else
                    .{ .xyzw, reg_index_swzl.len };

                const reg_index_str = reg_index_swzl[0..reg_end_idx];
                const reg_index = std.fmt.parseUnsigned(switch (kind) {
                    .input, .temporary => u4,
                    .floating_constant => u7,
                    else => unreachable,
                }, reg_index_str, 10) catch |err| switch (err) {
                    error.Overflow => return error.InvalidIndex,
                    error.InvalidCharacter => return error.Syntax,
                };

                break :alias switch (kind) {
                    .input => .{ .input = .{ .register = @enumFromInt(reg_index), .selector = swizzle } },
                    .temporary => .{ .temporary = .{ .register = @enumFromInt(reg_index), .selector = swizzle } },
                    .floating_constant => if (reg_index > 95) error.InvalidIndex else .{ .floating_constant = .{ .register = @enumFromInt(reg_index), .selector = swizzle } },
                    else => unreachable,
                };
            },
            .output => .{ .output = @enumFromInt(std.fmt.parseUnsigned(u4, reg_index_swzl, 10) catch |err| return switch (err) {
                error.Overflow => return error.InvalidIndex,
                error.InvalidCharacter => return error.Syntax,
            }) },
            .integer_constant => .{ .integer_constant = @enumFromInt(std.fmt.parseUnsigned(u2, reg_index_swzl, 10) catch |err| switch (err) {
                error.Overflow => return error.InvalidIndex,
                error.InvalidCharacter => return error.Syntax,
            }) },
            .boolean_constant => .{ .boolean_constant = @enumFromInt(std.fmt.parseUnsigned(u4, reg_index_swzl, 10) catch |err| switch (err) {
                error.Overflow => return error.InvalidIndex,
                error.InvalidCharacter => return error.Syntax,
            }) },
        };
    }
};

pub const Diagnostic = union(enum) {
    invalid_identifier: struct {
        identifier: []const u8,
        loc: Assembler.Location,
    },
    invalid_register: struct {
        register: []const u8,
        loc: Assembler.Location,
    },
    invalid_register_kind: struct {
        register: []const u8,
        expected: []const u8,
        loc: Assembler.Location,
    },
    invalid_mask: struct {
        mask: []const u8,
        loc: Assembler.Location,
    },
    invalid_swizzle: struct {
        mask: []const u8,
        loc: Assembler.Location,
    },
    undeclared_identifier: struct {
        identifier: []const u8,
        loc: Assembler.Location,
    },
    redefined_identifier: struct {
        identifier: []const u8,
        loc: Assembler.Location,
    },
    invalid_value: struct {
        value: []const u8,
        loc: Assembler.Location,
    },
    expected_operand: struct {
        loc: Assembler.Location,
    },
    expected_mnemonic: struct {
        found: []const u8,
        loc: Assembler.Location,
    },
    expected_directive: struct {
        found: []const u8,
        loc: Assembler.Location,
    },
};

// Each assembler should be unique to the file it's assembling, however the encoder could be shared (as the binary and operand descriptor table is in the DVLP)
pub const Assembler = struct {
    pub const empty: Assembler = .{};

    pub const Location = struct { start: u32, end: u32 };
    const Diagnostics = std.ArrayListUnmanaged(Diagnostic);
    const Aliases = std.StringArrayHashMapUnmanaged(AliasedRegister);
    // TODO: const Uniforms = std.StringArrayHashMapUnmanaged();

    diagnostics: Diagnostics = .empty,
    encoder: Encoder = .init(),
    labels: Labels = .empty,
    aliases: Aliases = .empty,
    floating_constants: std.EnumMap(SourceRegister.Constant, [4]f32) = .init(.{}),
    integer_constants: std.EnumMap(IntegerRegister, [4]i8) = .init(.{}),
    boolean_constants: std.EnumMap(BooleanRegister, bool) = .init(.{}),
    entry: ?[]const u8 = null,

    pub fn deinit(assembler: *Assembler, alloc: mem.Allocator) void {
        assembler.encoder.deinit(alloc);
        assembler.labels.deinit(alloc);
        assembler.aliases.deinit(alloc);
        assembler.* = undefined;
    }

    pub fn assemble(assembler: *Assembler, alloc: mem.Allocator, buffer: []const u8) !void {
        const UnprocessedLine = struct { index: u32, len: u32 };

        var unprocessed_line_info: std.ArrayListUnmanaged(UnprocessedLine) = .empty;
        defer unprocessed_line_info.deinit(alloc);

        var lines = mem.tokenizeAny(u8, buffer, "\n\r");
        var index: usize = 0;
        var had_error = false;

        line_loop: while (lines.next()) |line| : (index = lines.index) {
            const left_trimmed_line = mem.trimLeft(u8, line, " \t");
            const fully_trimmed_line = mem.trimRight(u8, left_trimmed_line, " \t");

            if (left_trimmed_line.len == 0) continue :line_loop;

            const real_index = mem.indexOfNonePos(u8, buffer, index, "\n\r") orelse unreachable;
            const line_start_index: u32 = @intCast(real_index + (line.len - left_trimmed_line.len));
            const line_len: u32 = @intCast(fully_trimmed_line.len);

            switch (left_trimmed_line[0]) {
                ';' => continue :line_loop,
                '.' => {
                    const full_directive_line = fully_trimmed_line[1..];
                    const directive_str = full_directive_line[0..(mem.indexOf(u8, full_directive_line, " ") orelse full_directive_line.len)];
                    const directive = std.meta.stringToEnum(Directive, directive_str) orelse {
                        try assembler.fail(alloc, .{ .expected_directive = .{
                            .found = directive_str,
                            .loc = .{ .start = line_start_index + 1, .end = @intCast(line_start_index + 1 + directive_str.len) },
                        } });
                        had_error = true;
                        continue :line_loop;
                    };

                    const directive_args = full_directive_line[directive_str.len..];
                    var directive_args_tok = mem.tokenizeAny(u8, directive_args, " \t");

                    switch (directive) {
                        .entry => {
                            const label = directive_args_tok.next() orelse {
                                try assembler.fail(alloc, .{ .expected_operand = .{
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });

                                had_error = true;
                                continue :line_loop;
                            };

                            if (!isValidIdentifier(label)) {
                                // TODO: Proper location
                                try assembler.fail(alloc, .{ .invalid_identifier = .{
                                    .identifier = label,
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            }

                            assembler.entry = label;
                        },
                        .alias => {
                            const alias_name = directive_args_tok.next() orelse {
                                try assembler.fail(alloc, .{ .expected_operand = .{
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });

                                had_error = true;
                                continue :line_loop;
                            };

                            if (!isValidIdentifier(alias_name)) {
                                // TODO: Proper location
                                try assembler.fail(alloc, .{ .invalid_identifier = .{
                                    .identifier = alias_name,
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            }

                            if (assembler.aliases.contains(alias_name)) {
                                // TODO: Proper location
                                try assembler.fail(alloc, .{ .redefined_identifier = .{
                                    .identifier = alias_name,
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            }

                            const reg_expr = std.mem.trim(u8, directive_args[directive_args_tok.index..], " \t");
                            const alias = AliasedRegister.parse(reg_expr) catch {
                                try assembler.fail(alloc, .{ .invalid_register = .{
                                    .register = reg_expr,
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            };

                            try assembler.aliases.put(alloc, alias_name, alias);
                        },
                        .set => {
                            const reg_str = directive_args_tok.next() orelse {
                                try assembler.fail(alloc, .{ .expected_operand = .{
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });

                                had_error = true;
                                continue :line_loop;
                            };

                            if (reg_str.len < 2 or !std.ascii.isAlphabetic(reg_str[0]) or !std.ascii.isDigit(reg_str[1])) {
                                // TODO: Proper location
                                try assembler.fail(alloc, .{ .invalid_register = .{
                                    .register = reg_str,
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            }

                            const reg_kind = mem.indexOfScalar(u8, "fib", reg_str[0]) orelse {
                                // TODO: Proper location
                                try assembler.fail(alloc, .{ .invalid_register_kind = .{
                                    .register = reg_str,
                                    .expected = "fib",
                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                } });
                                had_error = true;
                                continue :line_loop;
                            };

                            switch (reg_kind) {
                                else => unreachable,
                                inline 0, 1, 2 => |kind| {
                                    const RegisterType, const ScalarType = switch (kind) {
                                        0 => .{ SourceRegister.Constant, f32 },
                                        1 => .{ IntegerRegister, i8 },
                                        2 => .{ BooleanRegister, bool },
                                        else => unreachable,
                                    };

                                    const reg = std.meta.stringToEnum(RegisterType, reg_str) orelse {
                                        try assembler.fail(alloc, .{ .invalid_register = .{
                                            .register = reg_str,
                                            .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                        } });
                                        had_error = true;
                                        continue :line_loop;
                                    };

                                    switch (kind) {
                                        0, 1 => {
                                            const vec_str = std.mem.trim(u8, directive_args[directive_args_tok.index..], " \t");

                                            if (vec_str.len <= 2 or vec_str[0] != '(' or vec_str[vec_str.len - 1] != ')') {
                                                try assembler.fail(alloc, .{ .invalid_value = .{
                                                    .value = vec_str,
                                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                                } });
                                                had_error = true;
                                                continue :line_loop;
                                            }

                                            var vec_values_tok = mem.tokenizeAny(u8, vec_str[1..(vec_str.len - 1)], ", ");

                                            var vec_buf: [4]ScalarType = undefined;
                                            inline for (0..4) |i| {
                                                const scalar_str = vec_values_tok.next() orelse {
                                                    try assembler.fail(alloc, .{ .expected_operand = .{
                                                        .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                                    } });

                                                    had_error = true;
                                                    continue :line_loop;
                                                };

                                                const scalar = (if (kind == 0)
                                                    std.fmt.parseFloat(ScalarType, scalar_str)
                                                else
                                                    std.fmt.parseInt(ScalarType, scalar_str, 0)) catch {
                                                    try assembler.fail(alloc, .{ .invalid_value = .{
                                                        .value = scalar_str,
                                                        .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                                    } });
                                                    had_error = true;
                                                    continue :line_loop;
                                                };

                                                vec_buf[i] = scalar;
                                            }

                                            const map = if (kind == 0) &assembler.floating_constants else &assembler.integer_constants;

                                            map.put(reg, vec_buf);
                                        },
                                        2 => {
                                            const value_str = directive_args_tok.next() orelse {
                                                try assembler.fail(alloc, .{ .expected_operand = .{
                                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                                } });

                                                had_error = true;
                                                continue :line_loop;
                                            };

                                            const value = if (mem.eql(u8, value_str, "true"))
                                                true
                                            else if (mem.eql(u8, value_str, "false"))
                                                false
                                            else {
                                                try assembler.fail(alloc, .{ .invalid_value = .{
                                                    .value = value_str,
                                                    .loc = .{ .start = line_start_index, .end = line_start_index + line_len },
                                                } });
                                                had_error = true;
                                                continue :line_loop;
                                            };

                                            assembler.boolean_constants.put(reg, value);
                                        },
                                        else => unreachable,
                                    }
                                },
                            }
                        },
                        else => @panic("TODO"),
                    }
                },
                else => {
                    if (mem.endsWith(u8, fully_trimmed_line, ":")) {
                        const label = fully_trimmed_line[0..(fully_trimmed_line.len - 1)];

                        if (!isValidIdentifier(label)) {
                            try assembler.fail(alloc, .{ .invalid_identifier = .{
                                .identifier = label,
                                .loc = .{ .start = line_start_index, .end = @intCast(line_start_index + label.len) },
                            } });
                            had_error = true;
                            continue;
                        }

                        if (assembler.labels.contains(label)) {
                            try assembler.fail(alloc, .{ .redefined_identifier = .{
                                .identifier = label,
                                .loc = .{ .start = line_start_index, .end = @intCast(line_start_index + label.len) },
                            } });
                            had_error = true;
                            continue;
                        }

                        try assembler.labels.put(alloc, label, @intCast(assembler.encoder.instructions.items.len + unprocessed_line_info.items.len));
                        continue;
                    }

                    try unprocessed_line_info.append(alloc, .{
                        .index = line_start_index,
                        .len = line_len,
                    });
                },
            }
        }

        unproc_line_loop: for (unprocessed_line_info.items) |line_info| {
            const line = buffer[line_info.index..][0..line_info.len];
            const operands_start = mem.indexOfAny(u8, line, " \t") orelse line.len;
            const mnemonic_str = line[0..operands_start];
            const mnemonic = std.meta.stringToEnum(Mnemonic, mnemonic_str) orelse {
                try assembler.fail(alloc, .{ .expected_mnemonic = .{
                    .found = mnemonic_str,
                    .loc = .{ .start = line_info.index, .end = line_info.index + line_info.len },
                } });
                had_error = true;
                continue :unproc_line_loop;
            };

            (switch (mnemonic) {
                inline else => |m| assembler.encodeInstruction(alloc, m, mem.trim(u8, line[operands_start..], " \t"), line_info.index, line_info.index + line_info.len),
            }) catch |err| switch (err) {
                error.Syntax => {
                    had_error = true;
                    continue :unproc_line_loop;
                },
                else => return err,
            };
        }

        if (had_error) {
            return error.Syntax;
        }
    }

    fn encodeInstruction(assembler: *Assembler, alloc: mem.Allocator, comptime mnemonic: Mnemonic, operands: []const u8, start_index: u32, end_index: u32) !void {
        _ = start_index;
        _ = end_index;

        const fmt = comptime format.get(mnemonic);
        var operand_list = mem.tokenizeScalar(u8, operands, ',');

        const fun = @field(Encoder, @tagName(mnemonic));
        var args: std.meta.ArgsTuple(@TypeOf(fun)) = undefined;
        args[0] = &assembler.encoder;
        args[1] = alloc;

        comptime var arg: comptime_int = 2;
        comptime var last_src: ?comptime_int = null;
        const parsed_relative: RelativeComponent = .none;
        var last_label_addr: ?u16 = null;

        inline for (fmt.operands, 0..) |op, i| {
            const current = mem.trim(u8, operand_list.next() orelse return error.Syntax, " \t");

            switch (op) {
                .src, .src_limited => {
                    const negated: bool, const reg_str: []const u8 = if (mem.startsWith(u8, current, "-"))
                        .{ true, current[1..] }
                    else
                        .{ false, current };

                    const reg_str_end: usize, const extra_swizzle: Component.Selector = if (mem.indexOf(u8, reg_str, ".")) |swizzle_start| swzl: {
                        const swizzles_str = reg_str[(swizzle_start + 1)..];
                        const extra_swizzle = try Component.Selector.parseSequential(swizzles_str);
                        break :swzl .{ swizzle_start, extra_swizzle };
                    } else .{ reg_str.len, .xyzw };

                    const src_str = reg_str[0..reg_str_end];

                    // TODO: Parse relative

                    const src: SourceRegister, const initial_swizzle: Component.Selector = try assembler.getSourceRegisterOrAlias(src_str);

                    // Source registers MUST be sequential
                    if (last_src) |l| std.debug.assert((i - l) == 1);
                    last_src = i;

                    const final_src = if (op == .src_limited) (src.toLimited() orelse return error.Syntax) else src;

                    args[arg] = final_src;
                    args[arg + 1] = initial_swizzle.swizzle(extra_swizzle);
                    args[arg + 2] = negated;
                    arg += 3;
                },
                else => |non_src_op| {
                    if (last_src) |_| {
                        args[arg] = parsed_relative;
                        arg += 1;

                        last_src = null;
                    }

                    switch (non_src_op) {
                        .dst => {
                            const dst_reg_end: usize, const mask: Component.Mask = if (mem.indexOf(u8, current, ".")) |mask_start| msk: {
                                const mask_str = current[(mask_start + 1)..];

                                if (mem.indexOf(u8, mask_str, &.{'.'})) |_| {
                                    return error.Syntax;
                                }

                                break :msk .{ mask_start, try Component.Mask.parse(mask_str) };
                            } else .{ current.len, .xyzw };

                            const dst_str = current[0..dst_reg_end];
                            const dst = try assembler.getDestinationRegisterOrAlias(dst_str);

                            args[arg] = dst;
                            args[arg + 1] = mask;
                            arg += 2;
                        },
                        .src, .src_limited => unreachable,
                        .bit => {
                            const value = if (mem.eql(u8, current, "true"))
                                true
                            else if (mem.eql(u8, current, "false"))
                                false
                            else
                                return error.Syntax;

                            args[arg] = value;
                            arg += 1;
                        },
                        .label, .label_exclusive, .label_relative_last => {
                            if (!isValidIdentifier(current)) return error.Syntax;
                            const label_addr = assembler.labels.get(current) orelse return error.UndeclaredLabel;

                            const current_addr: u16 = @intCast(assembler.encoder.instructions.items.len + 1);

                            args[arg] = @intCast(switch (op) {
                                .label, .label_exclusive => @as(isize, label_addr) - @as(isize, current_addr) - (if (op == .label_exclusive) 1 else 0),
                                .label_relative_last => (@as(isize, label_addr) - (last_label_addr orelse unreachable)),
                                else => unreachable,
                            });

                            last_label_addr = label_addr;
                            arg += 1;
                        },
                        .src_boolean, .src_integer => {
                            const value = std.meta.stringToEnum(switch (op) {
                                .src_boolean => BooleanRegister,
                                .src_integer => IntegerRegister,
                                else => unreachable,
                            }, current) orelse val: {
                                const aliased = assembler.aliases.get(current) orelse return error.Syntax;

                                break :val (switch (op) {
                                    .src_boolean => aliased.toBooleanRegister(),
                                    .src_integer => aliased.toIntegerRegister(),
                                    else => unreachable,
                                }) orelse return error.Syntax;
                            };

                            args[arg] = value;
                            arg += 1;
                        },
                        .condition, .comparison, .winding, .primitive => {
                            const value = std.meta.stringToEnum(switch (op) {
                                .condition => Condition,
                                .comparison => ComparisonOperation,
                                .winding => Winding,
                                .primitive => Primitive,
                                else => unreachable,
                            }, current) orelse return error.Syntax;

                            args[arg] = value;
                            arg += 1;
                        },
                        .vertex_id => {
                            const value = try std.fmt.parseUnsigned(u2, current, 0);

                            args[arg] = value;
                            arg += 1;
                        },
                    }
                },
            }
        }

        if (last_src) |_| {
            args[arg] = parsed_relative;
            arg += 1;

            last_src = null;
        }

        if (operand_list.next()) |_| {
            return error.Syntax;
        }

        try @call(.auto, fun, args);
    }

    fn fail(assembler: *Assembler, alloc: std.mem.Allocator, diagnostic: Diagnostic) !void {
        try assembler.diagnostics.append(alloc, diagnostic);
    }

    fn getSourceRegisterOrAlias(assembler: *Assembler, reg_str: []const u8) !AliasedRegister.SourceSwizzlePair {
        const src = SourceRegister.parse(reg_str) catch |err| switch (err) {
            error.Syntax => {
                const aliased_src, const aliased_swizzle = (assembler.aliases.get(reg_str) orelse return error.Syntax).toSourceRegister() orelse return error.Syntax;
                return .{ aliased_src, aliased_swizzle };
            },
            else => return err,
        };

        return .{ src, .xyzw };
    }

    fn getDestinationRegisterOrAlias(assembler: *Assembler, reg_str: []const u8) !DestinationRegister {
        return DestinationRegister.parse(reg_str) catch |err| switch (err) {
            error.Syntax => (assembler.aliases.get(reg_str) orelse return error.Syntax).toDestinationRegister() orelse return error.Syntax,
            else => return err,
        };
    }

    fn isValidIdentifier(buffer: []const u8) bool {
        return iden: for (buffer, 0..) |c, i| switch (c) {
            '0'...'9' => if (i == 0) break :iden false,
            'A'...'Z', 'a'...'z', '.', '_', '$' => {},
            else => break :iden false,
        } else true;
    }

    const Format = struct {
        operands: []const OperandKind,
        shader: Shader,
    };

    const format = fmt: {
        const Entry = struct { Mnemonic, []const OperandKind, Shader };
        const format_entries: []const Entry = @import("as-format.zon");

        var map: std.EnumArray(Mnemonic, Format) = .initUndefined();
        for (format_entries) |e| {
            map.set(e[0], .{ .operands = e[1], .shader = e[2] });
        }

        break :fmt map;
    };
};

const testing = std.testing;

test Assembler {
    var assembler: Assembler = .{};
    defer assembler.deinit(testing.allocator);

    // TODO: Check the output (descriptors, instructions, exports, ins, outs, ...)
    // TODO: embed file
    try assembler.assemble(testing.allocator,
        \\    ; Public domain code translated from the examples: https://github.com/devkitPro/3ds-examples/blob/master/graphics/gpu/lenny/source/vshader.v.pica
        \\    
        \\    ; TODO: .uniform <name> X Y
        \\    .set f95 (0, 1, -1, 0.5)
        \\    .alias zeros f95.xxxx
        \\    .alias ones f95.yyyy
        \\    .alias half f95.wwww
        \\    
        \\    ; TODO
        \\    ; .out o0 position
        \\    ; .out o1 color
        \\    ; .out o2 view
        \\    ; .out o3 normal_quaternion
        \\
        \\    ; TODO
        \\    ; .in v0
        \\    ; .in v1
        \\
        \\    main:
        \\      ; const screen_position = model_view * f24x4{i_position.xyz, 1};
        \\      mov r0.xyz, v0
        \\      mov r0.w, ones
        \\      
        \\      dp4 r1.x, r0, f0
        \\      dp4 r1.y, r0, f1
        \\      dp4 r1.z, r0, f2
        \\      dp4 r1.w, r0, f3
        \\
        \\      mov o2, -r1
        \\
        \\      ; o_position = u_proj * screen_position;
        \\      dp4 o0.x, r1, f4
        \\      dp4 o0.y, r1, f5
        \\      dp4 o0.z, r1, f6
        \\      dp4 o0.w, r1, f7
        \\
        \\      ; quaternion ops, lazy rn
        \\      dp3 r14.x, v1, f0
        \\      dp3 r14.y, v1, f1
        \\      dp3 r14.z, v1, f2
        \\      dp3 r6.x, r14, r14
        \\      rsq r6.x, r6.x
        \\      mul r14.xyz, r14.xyz, r6.x
        \\
        \\      mov r0, f95.yxxx
        \\      add r4, ones, r14.z
        \\      mul r4, half, r4
        \\      cmp zeros, r4.x, ge, ge
        \\      rsq r4, r4.x
        \\      mul r5, half, r4
        \\      jmpc x, true, false, main.degenerate
        \\      
        \\      rcp r0.z, r4.x
        \\      mul r0.xy, r5, r4
        \\
        \\    main.degenerate:
        \\      mov o3, r0
        \\      mov o1, ones
        \\
        \\      end
    );
}

const std = @import("std");
const Labels = std.StringArrayHashMapUnmanaged(u16);

const mem = std.mem;

const encoding = @import("encoding.zig");
const Encoder = @import("Encoder.zig");
const Shader = encoding.Shader;
const Condition = encoding.Condition;
const ComparisonOperation = encoding.ComparisonOperation;
const Primitive = encoding.Primitive;
const Winding = encoding.Winding;
const Component = encoding.Component;

const register = @import("register.zig");
const RelativeComponent = register.RelativeComponent;
const TemporaryRegister = register.TemporaryRegister;
const SourceRegister = register.SourceRegister;
const DestinationRegister = register.DestinationRegister;
const BooleanRegister = register.BooleanRegister;
const IntegerRegister = register.IntegerRegister;
