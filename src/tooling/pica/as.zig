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

const Operand = union {
    const Kind = enum {
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
};

const Directive = enum {
    entry,
    @"export"
};

// Each assembler should be unique to the file it's assembling, however the encoder could be shared (as the binary and operand descriptor table is in the DVLP)
pub const Assembler = struct {
    encoder: Encoder = .init(),
    labels: Labels = .empty,
    entry: ?[]const u8 = null,

    pub fn deinit(assembler: *Assembler, alloc: mem.Allocator) void {
        assembler.encoder.deinit(alloc);
        assembler.labels.deinit(alloc);
        assembler.* = undefined;
    }

    pub fn assemble(assembler: *Assembler, alloc: mem.Allocator, buffer: []const u8) !void {
        var line_instructions: UnprocessedLines = .empty; 
        defer line_instructions.deinit(alloc);

        var lines = mem.tokenizeAny(u8, buffer, "\n\r");

        while (lines.next()) |line| {
            const trimmed_line = mem.trim(u8, line, " \t");

            if(trimmed_line.len == 0) continue;

            switch (trimmed_line[0]) {
                ';' => continue,
                '.' => {
                    // TODO: Process directives
                    const directive_str = trimmed_line[1..][0..(mem.indexOf(u8, trimmed_line[1..], " ") orelse trimmed_line[1..].len)];
                    const directive = std.meta.stringToEnum(Directive, directive_str) orelse return error.Syntax;

                    switch (directive) {
                        else => @panic("TODO"),
                    }
                },
                else => {
                    if(mem.endsWith(u8, trimmed_line, ":")) {
                        const label = trimmed_line[0..(trimmed_line.len - 1)];
                        
                        if(!isValidIdentifier(label)) {
                            return error.InvalidIdentifier;
                        }

                        if(assembler.labels.contains(label)) {
                            return error.RedefinedLabel;
                        }
                        
                        try assembler.labels.put(alloc, label, @intCast(line_instructions.items.len));
                        continue;
                    }

                    try line_instructions.append(alloc, trimmed_line);
                }
            }
        }

        for (line_instructions.items) |trimmed_line| {
            const operands_start = mem.indexOfAny(u8, trimmed_line, " \t") orelse trimmed_line.len;
            const mnemonic = std.meta.stringToEnum(Mnemonic, trimmed_line[0..operands_start]) orelse return error.ExpectedInstruction;

            switch (mnemonic) {
                inline else => |m| try assembler.encodeInstruction(alloc, m, mem.trim(u8, trimmed_line[operands_start..], " \t")),
            }
        }
    }

    // TODO: Proper error reporting
    fn encodeInstruction(assembler: *Assembler, alloc: mem.Allocator, comptime mnemonic: Mnemonic, operands: []const u8) !void {
        const fmt = comptime format.get(mnemonic);
        var operand_list = mem.tokenizeAny(u8, operands, ", ");
        
        const fun = @field(Encoder, @tagName(mnemonic));
        var args: std.meta.ArgsTuple(@TypeOf(fun)) = undefined;
        args[0] = &assembler.encoder;
        args[1] = alloc;

        comptime var arg: comptime_int = 2;
        comptime var last_src: ?comptime_int = null;
        var parsed_relative: RelativeComponent = .none;
        // TODO
        var last_label_addr: ?u16 = null;

        inline for (fmt.operands, 0..) |op, i| {
            parsed_relative = .none;
            const current = operand_list.next() orelse return error.Syntax;
            
            switch (op) {
                .src, .src_limited => {
                    // TODO: aliases, relative
                    const negated: bool, const reg_str: []const u8 = if(mem.startsWith(u8, current, "-"))
                        .{true, current[1..]}
                    else 
                        .{false, current};

                    const src: SourceRegister, const final_swizzle: Component.Selector = if(mem.indexOf(u8, reg_str, ".")) |swizzle_start| swzl: {
                        const swizzles_str = reg_str[(swizzle_start + 1)..]; 
                        var swizzles = mem.tokenizeScalar(u8, swizzles_str, '.');

                        var final_swizzle: Component.Selector = .xyzw;
                        while (swizzles.next()) |swizzle_str| {
                            const swizzle = try Component.Selector.parse(swizzle_str);
                            final_swizzle = final_swizzle.swizzle(swizzle);
                        }
                        const src_str = reg_str[0..swizzle_start];
                        const src = try SourceRegister.parse(src_str);
                        break :swzl .{src, final_swizzle};
                    } else .{try SourceRegister.parse(reg_str), .xyzw};

                    // Source registers MUST be sequential
                    if(last_src) |l| std.debug.assert((i - l) == 1);
                    last_src = i;

                    const final_src = if(op == .src_limited) (src.toLimited() orelse return error.Syntax) else src;

                    args[arg] = final_src;
                    args[arg + 1] = final_swizzle;
                    args[arg + 2] = negated;
                    arg += 3;
                },
                else => |non_src_op| {
                    if(last_src) |_| {
                        args[arg] = parsed_relative;
                        arg += 1;

                        last_src = null;
                    }

                    switch (non_src_op) {
                        .dst => {
                            // TODO: aliases
                            const dst: DestinationRegister, const mask: Component.Mask = if(mem.indexOf(u8, current, ".")) |mask_start| msk: {
                                const mask_str = current[(mask_start + 1)..]; 

                                if(mem.indexOf(u8, mask_str, &.{'.'})) |_| {
                                    return error.Syntax;
                                }

                                const dst_str = current[0..mask_start];
                                const dst = try DestinationRegister.parse(dst_str);
                                break :msk .{dst, try Component.Mask.parse(mask_str)};
                            } else .{try DestinationRegister.parse(current), .xyzw};

                            args[arg] = dst;
                            args[arg + 1] = mask;
                            arg += 2;
                        },
                        .src, .src_limited => unreachable,
                        .bit => {
                            const value = if(mem.eql(u8, current, "true"))
                                true
                            else if(mem.eql(u8, current, "false"))
                                false
                            else return error.Syntax;

                            args[arg] = value;
                            arg += 1;
                        },
                        .label, .label_exclusive, .label_relative_last => {
                            if(!isValidIdentifier(current)) return error.Syntax;
                            const label_addr = assembler.labels.get(current) orelse return error.UndeclaredLabel;

                            const current_addr: u16 = @intCast(assembler.encoder.instructions.items.len + 1);

                            args[arg] = @intCast(switch (op) {
                                .label, .label_exclusive => @as(isize, label_addr) - @as(isize, current_addr) - (if(op == .label_exclusive) 1 else 0),
                                .label_relative_last => (@as(isize, label_addr) - (last_label_addr orelse unreachable)),
                                else => unreachable,
                            });

                            last_label_addr = label_addr;
                            arg += 1;
                        },
                        .src_boolean, .src_integer, .condition, .comparison, .winding, .primitive => {
                            const value = std.meta.stringToEnum(switch(op) {
                                .src_boolean => BooleanRegister,
                                .src_integer => IntegerRegister,
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

        if(last_src) |_| {
            args[arg] = parsed_relative;
            arg += 1;

            last_src = null;
        }

        if(operand_list.next()) |_| {
            return error.Syntax;
        }

        try @call(.auto, fun, args);
    }

    fn isValidIdentifier(buffer: []const u8) bool {
        return iden: for (buffer, 0..) |c, i| switch (c) {
            '0'...'9' => if(i == 0) break :iden false,
            'A'...'Z', 'a'...'z', '.', '_', '$' => {},
            else => break :iden false,
        } else true;
    }

    const Format = struct {
        operands: []const Operand.Kind,
        shader: Shader,
    };

    const format = fmt: {
        const Entry = struct { Mnemonic, []const Operand.Kind, Shader };
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
    try assembler.assemble(testing.allocator, 
        \\    ; Test PICA200 assembly program
        \\    
        \\    ; TODO: .in <name> [vX]
        \\    ; TODO: .out <name> <semantic> [oX]
        \\    ; TODO: .alias <name> <reg>
        \\    ; TODO: .entry <label>
        \\
        \\    main:
        \\      mov r0, r1
        \\      add r0, r1, r2
        \\      mul r0, f0, r0
        \\      add r0, r0, f0
        \\      flr r15, r1.xyz
        \\      ifu b0, main.else.0, main.end.0
        \\      nop
        \\      main.else.0:
        \\      call other, other.end
        \\      nop
        \\      main.end.0:
        \\      nop
        \\      end
        \\
        \\    other:
        \\      mov r0 r1
        \\    other.end:
    );
    
    // var labels_iterator = assembler.labels.iterator();
    // std.debug.print("LABELS:\n", .{});
    // while (labels_iterator.next()) |label| {
    //     std.debug.print("{s}: 0x{X}\n", .{label.key_ptr.*, label.value_ptr.*});
    // }
    //
    // std.debug.print("INSTRUCTIONS:\n", .{});
    // for (assembler.encoder.instructions.items, 0..) |ins, i| {
    //     std.debug.print("0x{X}: {b}\n", .{i, @as(u32, @bitCast(ins))});
    // }
}

const std = @import("std");
const Labels = std.StringArrayHashMapUnmanaged(u16);
const UnprocessedLines = std.ArrayListUnmanaged([]const u8);

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
const SourceRegister = register.SourceRegister;
const DestinationRegister = register.DestinationRegister;
const BooleanRegister = register.BooleanRegister;
const IntegerRegister = register.IntegerRegister;
