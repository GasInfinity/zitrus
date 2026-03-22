pub const description = "Assemble a zitrus PICA200 shader assembly (ZPSM) file";

pub const OutputFormat = enum {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .zpsh = "Simpler shader format which is currently specific to zitrus",
        .dvl = "Shader format used in official and homebrew 3DS titles",
    };

    zpsh,
    dvl,
};

pub const descriptions: plz.Descriptions(@This()) = .{
    .ofmt = "Output binary format",
    .output = "Output file, if none stdout is used",
};

pub const short: plz.Short(@This()) = .{
    .output = 'o',
};

ofmt: OutputFormat = .zpsh,
output: ?[]const u8,

@"--": struct {
    pub const descriptions: plz.Descriptions(@This()) = .{
        .input = "File to assemble, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn run(args: Assemble, io: std.Io, arena: std.mem.Allocator) !u8 {
    const cwd = std.Io.Dir.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |input|
        .{ cwd.openFile(io, input, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ input, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdin(), false };
    defer if (input_should_close) input_file.close(io);

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(io, out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.Io.File.stdout(), false };
    defer if (output_should_close) output_file.close(io);

    // const tty_cfg: std.Io.tty.Config = .detect(std.Io.File.stderr());

    const input_source = src: {
        var input_reader = input_file.readerStreaming(io, &.{});
        var source: std.ArrayList(u8) = .empty;
        try input_reader.interface.appendRemaining(arena, &source, .unlimited);

        break :src try source.toOwnedSliceSentinel(arena, 0);
    };
    defer arena.free(input_source);

    if (input_source.len > std.math.maxInt(u32)) {
        log.err("input file too big!", .{});
        return 1;
    }

    var assembled: Assembled = try .assemble(arena, input_source);
    defer assembled.deinit(arena);

    if (assembled.errors.len > 0) {
        var stderr_buf: [4096]u8 = undefined;
        const stderr = try io.lockStderr(&stderr_buf, null);
        defer io.unlockStderr();

        for (assembled.errors) |err| {
            const diagnostic: Diagnostic = .fromError(err, assembled);

            try diagnostic.render(stderr.terminal(), args.@"--".input orelse "", input_source);
        }

        try stderr.file_writer.interface.flush();
        return 1;
    }

    var out_buf: [4096]u8 = undefined;
    var output_writer = output_file.writer(io, &out_buf);
    const out = &output_writer.interface;

    switch (args.ofmt) {
        .dvl => @panic("TODO"),
        .zpsh => {
            if (assembled.encoded.instructions.items.len == 0) {
                log.err("cannot output zpsh, shader has no instructions", .{});
                return 1;
            }

            if (assembled.encoded.instructions.items.len > std.math.maxInt(u12)) {
                log.err("cannot output zpsh, encoded shader has too many instructions ({})", .{assembled.encoded.instructions.items.len});
                return 1;
            }

            if (assembled.entrypoints.count() > std.math.maxInt(u12)) {
                log.err("cannot output zpsh, encoded shader has too many entrypoints ({})", .{assembled.entrypoints.count()});
                return 1;
            }

            const encoded = &assembled.encoded;

            var padded_strings_size: usize = 0;
            var entry_it = assembled.entrypoints.iterator();
            while (entry_it.next()) |entrypoint| {
                padded_strings_size += entrypoint.key_ptr.*.len + 1;
            }

            padded_strings_size = std.mem.alignForward(usize, padded_strings_size, @sizeOf(u32));

            var string_table: std.ArrayList(u8) = try .initCapacity(arena, padded_strings_size);
            defer string_table.deinit(arena);

            var current_entrypoint_offset: u32 = 0;
            var entrypoint_offsets: std.ArrayList(u32) = try .initCapacity(arena, assembled.entrypoints.count());
            defer entrypoint_offsets.deinit(arena);

            entry_it.reset();
            while (entry_it.next()) |entrypoint| {
                const entry_info = entrypoint.value_ptr.*;
                
                string_table.appendSliceAssumeCapacity(entrypoint.key_ptr.*);
                string_table.appendAssumeCapacity(0);

                entrypoint_offsets.appendAssumeCapacity(current_entrypoint_offset);
                current_entrypoint_offset += @intCast(@sizeOf(zpsh.EntrypointHeader) + (entry_info.constants.int.count() * @sizeOf([4]i8)) + (entry_info.constants.float.count() * @sizeOf(pica.F7_16x4)) + (entry_info.outputs.count() * @sizeOf(pica.OutputMap)));
            }

            // Align the section
            string_table.appendNTimesAssumeCapacity(0, padded_strings_size - string_table.items.len);

            var code_hasher: std.hash.XxHash32 = .init(67);
            code_hasher.update(@ptrCast(assembled.encoded.instructions.items));
            code_hasher.update(@ptrCast(assembled.encoded.constDescriptorSlice()));
            const code_hash = code_hasher.final();

            try out.writeStruct(zpsh.Header{
                .shader = .init(assembled.entrypoints.count(), encoded.instructions.items.len, encoded.allocated_descriptors),
                .entry_string_table_size = @intCast(@divExact(padded_strings_size, @sizeOf(u32))),
                .code_hash = code_hash,
            }, .little);

            try out.writeSliceEndian(u32, entrypoint_offsets.items, .little);
            try out.writeSliceEndian(u32, @ptrCast(encoded.instructions.items), .little);
            try out.writeSliceEndian(u32, @ptrCast(encoded.constDescriptorSlice()), .little);
            try out.writeAll(string_table.items);

            var current_string_offset: u32 = 0;

            entry_it.reset();
            while (entry_it.next()) |entrypoint| {
                const processed_info = entrypoint.value_ptr;

                try out.writeStruct(zpsh.EntrypointHeader{
                    .name_string_offset = @intCast(current_string_offset),
                    .instruction_offset = processed_info.offset,
                    .info = switch (processed_info.info) {
                        .vertex => .vertex,
                        .geometry => |g| switch (g) {
                            .point => |p| .{
                                .type = .geometry_point,
                                .geometry = .initPoint(p.inputs),
                            },
                            .variable => |v| .{
                                .type = .geometry_variable,
                                .geometry = .initVariable(v.full_vertices),
                            },
                            .fixed => |f| .{
                                .type = .geometry_fixed,
                                .geometry = .initFixed(f.vertices, f.uniform_start),
                            },
                        },
                    },
                    .flags = .{},
                    .boolean_constant_mask = .fromSet(.{ .bits = processed_info.constants.bool.bits }),
                    .integer_constant_mask = .fromSet(.{ .bits = processed_info.constants.int.bits }),
                    .floating_constant_mask = .fromSet(.{ .bits = processed_info.constants.float.bits }),
                    .output_mask = .fromSet(.{ .bits = processed_info.outputs.bits }),
                }, .little);

                // NOTE: We can do this because two entrypoints cannot have the same name.
                current_string_offset += @intCast(entrypoint.key_ptr.len + 1);

                var int_it = processed_info.constants.int.iterator();
                while (int_it.next()) |entry| {
                    try out.writeAll(entry.value);
                }

                var flt_it = processed_info.constants.float.iterator();
                while (flt_it.next()) |entry| {
                    try out.writeStruct(entry.value.*, .little);
                }

                var out_it = processed_info.outputs.iterator();
                while (out_it.next()) |entry| {
                    try out.writeStruct(entry.value.*, .little);
                }
            }

            try out.flush();
            return 0;
        },
    }
}

const Diagnostic = struct {
    pub const Location = struct {
        start: u32,
        end: u32,
    };

    const unknown_directive: Diagnostic = .init("unknown directive");
    const invalid_register: Diagnostic = .init("invalid register");
    const expected_address_register: Diagnostic = .init("expected address register (a)");
    const invalid_address_register_mask: Diagnostic = .init("invalid address register mask (xy)");
    const expected_address_component: Diagnostic = .init("expected valid address component (a.x, a.y, a.l)");
    const cannot_address_relative: Diagnostic = .init("register cannot be addressed at runtime");

    const expected_condition_register: Diagnostic = .init("expected condition register (cc)");
    const invalid_condition_register_mask: Diagnostic = .init("invalid condition register mask (xy)");

    const expected_src_register: Diagnostic = .init("expected source register (v0-v15, r0-r15, f0-f95)");
    const expected_limited_src_register: Diagnostic = .init("expected limited source register (v0-v15, r0-r15)");
    const expected_dst_register: Diagnostic = .init("expected destination register (o0-o15, r0-r15)");
    const expected_bool_register: Diagnostic = .init("expected boolean register (b0-b15)");
    const expected_int_register: Diagnostic = .init("expected integer register (i0-i3)");
    const expected_float_register: Diagnostic = .init("expected float register (f0-f95)");
    const expected_output_register: Diagnostic = .init("expected output register (o0-o15)");
    const expected_uniform_register: Diagnostic = .init("expected uniform constant register (f0-f95, i0-i3, b0-b15)");
    const invalid_mask: Diagnostic = .init("invalid destination mask (xyzw)");
    const swizzled_mask: Diagnostic = .init("destination mask is swizzled");
    const invalid_swizzle: Diagnostic = .init("invalid swizzle");
    const cannot_swizzle: Diagnostic = .init("cannot swizzle register in alias");
    const expected_number: Diagnostic = .init("expected a valid number");
    const number_too_big: Diagnostic = .init("expected a smaller number");
    const number_too_small: Diagnostic = .init("expected a bigger number");

    const expected_semantic: Diagnostic = .init("expected a semantic (position, normal_quaternion, color, texture_coordinates_x, view, dummy)");
    const invalid_semantic_component: Diagnostic = .init("swizzled a semantic component that does not exist");
    const output_has_semantic: Diagnostic = .init("output register component already has a semantic component");
    const expected_primitive: Diagnostic = .init("expected a primitive operation (none, emmiting)");
    const expected_winding: Diagnostic = .init("expected a winding (ccw, cw)");
    const expected_comparison: Diagnostic = .init("expected a comparison (eq, ne, lt, le, gt, ge)");
    const expected_condition: Diagnostic = .init("expected a condition (x, y, and, or)");
    const expected_bool: Diagnostic = .init("expected a boolean value (true, false)");
    const expected_shader_type: Diagnostic = .init("expected a shader type (vertex, geometry)");
    const expected_geometry_kind: Diagnostic = .init("expected a geometry kind (point, variable, fixed)");

    const undefined_label: Diagnostic = .init("undefined label");
    const redefined_label: Diagnostic = .init("redefined label");
    const label_range_too_big: Diagnostic = .init("label range has too many instructions");

    const redefined_entry: Diagnostic = .init("redefined entrypoint");
    const undefined_entry: Diagnostic = .init("undefined entrypoint");

    const expected_directive_or_label_or_mnemonic: Diagnostic = .init("expected a directive, label or mnemonic");
    const expected_token: Diagnostic = .init("expected a specific token");

    message: []const u8,
    tok_ctx: ?shader.as.Token.Tag = null,
    loc: ?Location = null,

    pub fn init(message: []const u8) Diagnostic {
        return .{ .message = message };
    }

    pub fn withTokenContext(diagnostic: Diagnostic, tok_ctx: shader.as.Token.Tag) Diagnostic {
        return .{
            .message = diagnostic.message,
            .tok_ctx = tok_ctx,
            .loc = diagnostic.loc,
        };
    }

    pub fn withLocation(diagnostic: Diagnostic, loc: Location) Diagnostic {
        return .{
            .message = diagnostic.message,
            .tok_ctx = diagnostic.tok_ctx,
            .loc = loc,
        };
    }

    pub fn render(diagnostic: Diagnostic, terminal: std.Io.Terminal, file_name: []const u8, source: [:0]const u8) !void {
        const w = terminal.writer;

        try terminal.setColor(.bold);
        try terminal.setColor(.bright_white);

        try w.print("{s}", .{file_name});

        if (diagnostic.loc) |loc| {
            const line = std.mem.count(u8, source[0..loc.start], &.{'\n'}) + 1;
            const column = (loc.start - (std.mem.lastIndexOfScalar(u8, source[0..loc.start], '\n') orelse 0)) + 1;

            try w.print(":{}:{}: ", .{ line, column });
        } else try w.writeAll(": ");

        try terminal.setColor(.bright_red);
        try w.writeAll("error: ");

        try terminal.setColor(.bright_white);
        try w.writeAll(diagnostic.message);

        if (diagnostic.tok_ctx) |tag| {
            _ = try w.print(" '{s}' ", .{@tagName(tag)});
        }

        _ = try w.writeByte('\n');

        if (diagnostic.loc) |loc| {
            const column_start = if (std.mem.lastIndexOfScalar(u8, source[0..loc.start], '\n')) |col_start| col_start + 1 else 0;
            const column_end = (std.mem.indexOfScalarPos(u8, source, loc.start, '\n') orelse (source.len - 1));

            try terminal.setColor(.reset);
            try w.print("{s}\n", .{source[column_start..column_end]});

            try terminal.setColor(.bright_green);
            try w.splatByteAll(' ', (loc.start - column_start));
            try w.writeByte('^');
            try w.writeByte('\n');
        }

        try terminal.setColor(.reset);
    }

    pub fn fromError(err: Assembler.Error, assembled: Assembled) Diagnostic {
        const tok_i = err.tok_i;
        const tok_start = assembled.tokenStart(tok_i);
        const tok_slice = assembled.tokenSlice(tok_i);
        const tok_end = tok_start + @as(u32, @intCast(tok_slice.len));

        const loc: Location = .{
            .start = tok_start,
            .end = tok_end,
        };

        return switch (err.tag) {
            .unknown_directive => unknown_directive.withLocation(loc),
            .invalid_register => invalid_register.withLocation(loc),
            .expected_address_register => expected_address_register.withLocation(loc),
            .invalid_address_register_mask => invalid_address_register_mask.withLocation(loc),
            .expected_address_component => expected_address_component.withLocation(loc),
            .cannot_address_relative => cannot_address_relative.withLocation(loc),
            .expected_condition_register => expected_condition_register.withLocation(loc),
            .invalid_condition_register_mask => invalid_condition_register_mask.withLocation(loc),
            .expected_src_register => expected_src_register.withLocation(loc),
            .expected_limited_src_register => expected_limited_src_register.withLocation(loc),
            .expected_dst_register => expected_dst_register.withLocation(loc),
            .expected_bool_register => expected_bool_register.withLocation(loc),
            .expected_int_register => expected_int_register.withLocation(loc),
            .expected_float_register => expected_float_register.withLocation(loc),
            .expected_output_register => expected_output_register.withLocation(loc),
            .expected_uniform_register => expected_uniform_register.withLocation(loc),
            .invalid_mask => invalid_mask.withLocation(loc),
            .swizzled_mask => swizzled_mask.withLocation(loc),
            .invalid_swizzle => invalid_swizzle.withLocation(loc),
            .cannot_swizzle => cannot_swizzle.withLocation(loc),
            .expected_number => expected_number.withLocation(loc),
            .number_too_big => number_too_big.withLocation(loc),
            .number_too_small => number_too_small.withLocation(loc),
            .expected_semantic => expected_semantic.withLocation(loc),
            .invalid_semantic_component => invalid_semantic_component.withLocation(loc),
            .output_has_semantic => output_has_semantic.withLocation(loc),
            .expected_primitive => expected_primitive.withLocation(loc),
            .expected_winding => expected_winding.withLocation(loc),
            .expected_comparison => expected_comparison.withLocation(loc),
            .expected_condition => expected_condition.withLocation(loc),
            .expected_boolean => expected_bool.withLocation(loc),
            .expected_shader_type => expected_shader_type.withLocation(loc),
            .expected_geometry_kind => expected_geometry_kind.withLocation(loc),
            .redefined_label => redefined_label.withLocation(loc),
            .undefined_label => undefined_label.withLocation(loc),
            .label_range_too_big => label_range_too_big.withLocation(loc),
            .redefined_entry => redefined_entry.withLocation(loc),
            .undefined_entry => undefined_entry.withLocation(loc),
            .expected_directive_or_label_or_mnemonic => expected_directive_or_label_or_mnemonic.withLocation(loc),
            .expected_token => expected_token.withLocation(loc).withTokenContext(err.expected_tok),
        };
    }
};

const Assemble = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const plz = @import("plz");
const zitrus = @import("zitrus");

const zpsh = zitrus.fmt.zpsh;

const pica = zitrus.hardware.pica;
const shader = pica.shader;

const Assembler = shader.as.Assembler;
const Assembled = Assembler.Assembled;
