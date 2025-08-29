const Self = @This();

const Subcommand = enum { @"asm", disasm };
const OutputFormat = enum {
    zpsh,
};

pub const description =
    \\assemble / dissassemble zitrus PICA200 shader assembly.
;

pub const Arguments = struct {
    pub const description = Self.description;

    command: union(Subcommand) {
        pub const descriptions = .{
            .@"asm" = "assemble a zpsm file",
            .disasm = "TODO: disassemble PICA200 shader assembly",
        };

        @"asm": struct {
            pub const descriptions = .{
                .ofmt = "output binary format",
            };

            pub const switches = .{
                .output = 'o',
            };

            ofmt: OutputFormat = .zpsh,
            output: []const u8,

            positional: struct {
                pub const descriptions = .{
                    .file = "file to assemble",
                };

                file: []const u8,
                // trailing: []const []const u8,
            },
        },
        disasm: struct {},
    },
};

const Diagnostic = struct {
    pub const Location = struct {
        start: u32,
        end: u32,
    };

    const unknown_directive: Diagnostic = .init("unknown directive");
    const invalid_register: Diagnostic = .init("invalid register");
    const expected_address_register: Diagnostic = .init("expected address register (a)");
    const invalid_address_register_mask: Diagnostic = .init("invalid address register mask (xy)");
    const expected_condition_register: Diagnostic = .init("expected condition register (cc)");
    const invalid_condition_register_mask: Diagnostic = .init("invalid condition register mask (xy)");

    const expected_src_register: Diagnostic = .init("expected source register (v0-v15, r0-r15, f0-f95)");
    const expected_limited_src_register: Diagnostic = .init("expected limited source register (v0-v15, r0-r15)");
    const expected_dst_register: Diagnostic = .init("expected destination register (o0-o15, r0-r15)");
    const expected_bool_register: Diagnostic = .init("expected boolean register (b0-b15)");
    const expected_int_register: Diagnostic = .init("expected integer register (i0-i3)");
    const expected_output_register: Diagnostic = .init("expected output register (o0-o15)");
    const expected_uniform_register: Diagnostic = .init("expected uniform constant register (f0-f95, i0-i3, b0-b15)");
    const invalid_mask: Diagnostic = .init("invalid destination mask (xyzw)");
    const swizzled_mask: Diagnostic = .init("destination mask is swizzled");
    const invalid_swizzle: Diagnostic = .init("invalid swizzle");
    const cannot_swizzle: Diagnostic = .init("cannot swizzle register in alias");
    const expected_number: Diagnostic = .init("expected a valid number");
    const number_too_big: Diagnostic = .init("expected a smaller number");

    const expected_semantic: Diagnostic = .init("expected a semantic (position, normal_quaternion, color, texture_coordinate_x, view, dummy)");
    const invalid_semantic_component: Diagnostic = .init("swizzled a semantic component that does not exist");
    const output_has_semantic: Diagnostic = .init("output register component already has a semantic component");
    const expected_primitive: Diagnostic = .init("expected a primitive operation (none, emmiting)");
    const expected_winding: Diagnostic = .init("expected a winding (ccw, cw)");
    const expected_comparison: Diagnostic = .init("expected a comparison (eq, ne, lt, le, gt, ge)");
    const expected_condition: Diagnostic = .init("expected a condition (x, y, and, or)");
    const expected_bool: Diagnostic = .init("expected a boolean value (true, false)");
    const expected_shader_type: Diagnostic = .init("expected a shader type (vertex, geometry)");

    const undefined_label: Diagnostic = .init("undefined label");
    const redefined_label: Diagnostic = .init("redefined label");
    const label_range_too_big: Diagnostic = .init("label range has too many instructions");
    const redefined_entry: Diagnostic = .init("redefined entrypoint");

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

    pub fn report(diagnostic: Diagnostic, writer: *std.Io.Writer, tty_cfg: std.io.tty.Config, file_name: []const u8, source: [:0]const u8) !void {
        try tty_cfg.setColor(writer, .bold);
        try tty_cfg.setColor(writer, .bright_white);

        try writer.print("{s}", .{file_name});

        if (diagnostic.loc) |loc| {
            const line = std.mem.count(u8, source[0..loc.start], &.{'\n'}) + 1;
            const column = (loc.start - (std.mem.lastIndexOfScalar(u8, source[0..loc.start], '\n') orelse 0)) + 1;

            try writer.print(":{}:{}: ", .{ line, column });
        } else try writer.writeAll(": ");

        try tty_cfg.setColor(writer, .bright_red);
        try writer.writeAll("error: ");

        try tty_cfg.setColor(writer, .bright_white);
        try writer.writeAll(diagnostic.message);

        if (diagnostic.tok_ctx) |tag| {
            _ = try writer.print(" '{s}' ", .{@tagName(tag)});
        }

        _ = try writer.writeByte('\n');

        if (diagnostic.loc) |loc| {
            const column_start = if (std.mem.lastIndexOfScalar(u8, source[0..loc.start], '\n')) |col_start| col_start + 1 else 0;
            const column_end = (std.mem.indexOfScalarPos(u8, source, loc.start, '\n') orelse (source.len - 1));

            try tty_cfg.setColor(writer, .reset);
            try writer.print("{s}\n", .{source[column_start..column_end]});

            try tty_cfg.setColor(writer, .bright_green);
            try writer.splatByteAll(' ', (loc.start - column_start));
            try writer.writeByte('^');
            try writer.writeByte('\n');
        }

        try tty_cfg.setColor(writer, .reset);
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
            .expected_condition_register => expected_condition_register.withLocation(loc),
            .invalid_condition_register_mask => invalid_condition_register_mask.withLocation(loc),
            .expected_src_register => expected_src_register.withLocation(loc),
            .expected_limited_src_register => expected_limited_src_register.withLocation(loc),
            .expected_dst_register => expected_dst_register.withLocation(loc),
            .expected_bool_register => expected_bool_register.withLocation(loc),
            .expected_int_register => expected_int_register.withLocation(loc),
            .expected_output_register => expected_output_register.withLocation(loc),
            .expected_uniform_register => expected_uniform_register.withLocation(loc),
            .invalid_mask => invalid_mask.withLocation(loc),
            .swizzled_mask => swizzled_mask.withLocation(loc),
            .invalid_swizzle => invalid_swizzle.withLocation(loc),
            .cannot_swizzle => cannot_swizzle.withLocation(loc),
            .expected_number => expected_number.withLocation(loc),
            .number_too_big => number_too_big.withLocation(loc),
            .expected_semantic => expected_semantic.withLocation(loc),
            .invalid_semantic_component => invalid_semantic_component.withLocation(loc),
            .output_has_semantic => output_has_semantic.withLocation(loc),
            .expected_primitive => expected_primitive.withLocation(loc),
            .expected_winding => expected_winding.withLocation(loc),
            .expected_comparison => expected_comparison.withLocation(loc),
            .expected_condition => expected_condition.withLocation(loc),
            .expected_boolean => expected_bool.withLocation(loc),
            .expected_shader_type => expected_shader_type.withLocation(loc),
            .redefined_label => redefined_label.withLocation(loc),
            .undefined_label => undefined_label.withLocation(loc),
            .label_range_too_big => label_range_too_big.withLocation(loc),
            .redefined_entry => redefined_entry.withLocation(loc),
            .expected_directive_or_label_or_mnemonic => expected_directive_or_label_or_mnemonic.withLocation(loc),
            .expected_token => expected_token.withLocation(loc).withTokenContext(err.expected_tok),
        };
    }
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    const cwd = std.fs.cwd();

    var stderr_buf: [4096]u8 = undefined;
    var stderr_raw = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_raw.interface;
    const tty_cfg: std.Io.tty.Config = .detect(std.fs.File.stderr());

    switch (arguments.command) {
        .@"asm" => |asm_options| {
            const file_path = asm_options.positional.file;
            const file_source = src: {
                const file = cwd.openFile(file_path, .{ .mode = .read_only }) catch |err| {
                    std.debug.print("could not open input file '{s}': {s}\n", .{ file_path, @errorName(err) });
                    return 1;
                };
                defer file.close();

                var buf: [4096]u8 = undefined;
                var file_reader = file.reader(&buf);
                const src_size = try file_reader.getSize();

                if (src_size > std.math.maxInt(u32)) {
                    std.debug.print("could not read file as its larger than 4GB", .{});
                    return 1;
                }

                const file_source = try arena.allocWithOptions(u8, src_size, null, 0);
                try file_reader.interface.readSliceAll(file_source);
                break :src file_source;
            };
            defer arena.free(file_source);

            var assembled: Assembled = try .assemble(arena, file_source);
            defer assembled.deinit(arena);

            if (assembled.errors.len > 0) {
                for (assembled.errors) |err| {
                    const diagnostic: Diagnostic = .fromError(err, assembled);

                    try diagnostic.report(stderr, tty_cfg, file_path, file_source);
                }

                try stderr.flush();
                return 1;
            }

            const output_path = asm_options.output;
            const output_file = try cwd.createFile(output_path, .{});

            var out_buf: [4096]u8 = undefined;
            var output_writer = output_file.writer(&out_buf);
            const out = &output_writer.interface;

            switch (asm_options.ofmt) {
                .zpsh => {
                    if (assembled.encoded.instructions.items.len > 512) {
                        try tty_cfg.setColor(stderr, .red);
                        try stderr.print("cannot output zpsh, encoded shader has too many instructions ({})", .{assembled.encoded.instructions.items.len});
                        try stderr.flush();
                        return 1;
                    }

                    if (assembled.entries.count() > std.math.maxInt(u8)) {
                        try tty_cfg.setColor(stderr, .red);
                        try stderr.print("cannot output zpsh, encoded shader has too many entrypoints ({})", .{assembled.entries.count()});
                        try stderr.flush();
                        return 1;
                    }

                    const encoded = &assembled.encoded;

                    var padded_strings_size: u32 = 0;
                    var entry_it = assembled.entries.iterator();
                    while (entry_it.next()) |entrypoint| {
                        padded_strings_size += @intCast(entrypoint.key_ptr.*.len + 1);
                    }

                    padded_strings_size = std.mem.alignForward(u32, padded_strings_size, @sizeOf(u32));

                    var string_table: std.ArrayList(u8) = try .initCapacity(arena, padded_strings_size);
                    defer string_table.deinit(arena);

                    entry_it.reset();
                    while (entry_it.next()) |entrypoint| {
                        string_table.appendSliceAssumeCapacity(entrypoint.key_ptr.*);
                        string_table.appendAssumeCapacity(0);
                    }

                    // Align the section
                    string_table.appendNTimesAssumeCapacity(0, padded_strings_size - string_table.items.len);

                    try out.writeStruct(zpsh.Header{
                        .shader_size = .init(encoded.instructions.items.len, encoded.allocated_descriptors),
                        .string_table_size = padded_strings_size,
                        .entrypoints = @intCast(assembled.entries.count()),
                    }, .little);

                    try out.writeAll(std.mem.sliceAsBytes(encoded.instructions.items));
                    try out.writeAll(std.mem.sliceAsBytes(encoded.descriptors[0..encoded.allocated_descriptors]));
                    try out.writeAll(string_table.items);

                    var current_string_offset: u32 = 0;

                    entry_it.reset();
                    while (entry_it.next()) |entrypoint| {
                        const processed_info = entrypoint.value_ptr.*;

                        try out.writeStruct(zpsh.EntrypointHeader{
                            .name_string_offset = @intCast(current_string_offset),
                            .code_offset = processed_info.offset,
                            .info = .{
                                .type = .vertex,
                            },
                            .boolean_constant_mask = .fromSet(.{ .bits = assembled.bool_const.bits }),
                            .integer_constant_mask = .fromSet(.{ .bits = assembled.int_const.bits }),
                            .floating_constant_mask = .fromSet(.{ .bits = assembled.flt_const.bits }),
                            .output_mask = .fromSet(.{ .bits = assembled.outputs.bits }),
                        }, .little);

                        // NOTE: We can do this because two entrypoints cannot have the same name.
                        current_string_offset += @intCast(entrypoint.key_ptr.len + 1);

                        var int_it = assembled.int_const.iterator();
                        while (int_it.next()) |entry| {
                            try out.writeAll(std.mem.asBytes(entry.value));
                        }

                        var flt_it = assembled.flt_const.iterator();
                        while (flt_it.next()) |entry| {
                            try out.writeStruct(entry.value.*, .little);
                        }

                        var out_it = assembled.outputs.iterator();
                        while (out_it.next()) |entry| {
                            try out.writeStruct(entry.value.*, .little);
                        }
                    }

                    try out.flush();
                    return 0;
                },
            }
        },
        .disasm => @panic("TODO"),
    }
}

const std = @import("std");

const zitrus = @import("zitrus");

const zpsh = zitrus.fmt.zpsh;

const pica = zitrus.pica;
const shader = pica.shader;

const Assembler = shader.as.Assembler;
const Assembled = Assembler.Assembled;
