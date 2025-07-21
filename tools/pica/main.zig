const Self = @This();

const Subcommand = enum { @"asm", disasm };
const OutputFormat = enum { bin, shbin };

pub const description =
    \\assemble / dissassemble PICA200 zitrus shader assembly.
    // \\compile PICA200 zitrus shader lang. TODO
;

pub const Arguments = struct {
    pub const description = Self.description;

    command: union(Subcommand) {
        pub const descriptions = .{
            .@"asm" = "assemble a PICA200 zitrus shader assembly file",
            .disasm = "TODO: disassemble PICA200 shader assembly",
        };

        @"asm": struct {
            pub const descriptions = .{
                .summary = "(DEBUG) Show a summary of the state of the assembled file",
                .ofmt = "TODO: output format",
            };

            pub const switches = .{
                .summary = 's',
            };

            summary: bool = false,
            ofmt: OutputFormat = .shbin,

            positional: struct {
                pub const descriptions = .{
                    .file = "file to assemble",
                };

                file: []const u8,
                trailing: []const []const u8,
            },
        },
        disasm: struct {},
    },
};

pub fn main(arena: std.mem.Allocator, arguments: Arguments) !u8 {
    const cwd = std.fs.cwd();

    switch (arguments.command) {
        .@"asm" => |asm_options| {
            const extra_files_paths = asm_options.positional.trailing;

            if (extra_files_paths.len > 0) {
                @panic("TODO: assemble multiple files");
            }

            const file_path = asm_options.positional.file;
            const file = cwd.openFile(file_path, .{ .mode = .read_only }) catch |err| {
                std.debug.print("could not open input file '{s}': {s}\n", .{ file_path, @errorName(err) });
                return 1;
            };

            const file_source = file.readToEndAlloc(arena, std.math.maxInt(u32)) catch |err| switch (err) {
                error.FileTooBig => {
                    std.debug.print("could not read file as its larger than 4GB", .{});
                    return 1;
                },
                else => return err,
            };
            defer arena.free(file_source);

            var assembler: Assembler = .empty;
            defer assembler.deinit(arena);

            assembler.assemble(arena, file_source) catch |err| switch (err) {
                error.Syntax => {
                    std.debug.print("errors found while assembling file {s}:\n", .{file_path});

                    for (assembler.diagnostics.items) |d| {
                        std.debug.print("{}\n", .{d});
                    }

                    return 1;
                },
                else => {
                    std.debug.print("error while assembling file '{s}': {s}\n", .{ file_path, @errorName(err) });
                    return 1;
                },
            };

            if (asm_options.summary) {
                var labels_iterator = assembler.labels.iterator();
                std.debug.print("LABELS:\n", .{});
                while (labels_iterator.next()) |label| {
                    std.debug.print("{s}: 0x{X}\n", .{ label.key_ptr.*, label.value_ptr.* });
                }

                std.debug.print("INSTRUCTIONS:\n", .{});
                for (assembler.encoder.instructions.items, 0..) |ins, i| {
                    std.debug.print("0x{X}: {b}\n", .{ i, @as(u32, @bitCast(ins)) });
                }

                std.debug.print("FLOATING CONSTANTS:\n", .{});
                var f_it = assembler.floating_constants.iterator();
                while (f_it.next()) |e| {
                    std.debug.print("{} -> {any}\n", .{ e.key, e.value.* });
                }

                std.debug.print("INTEGER CONSTANTS:\n", .{});
                var i_it = assembler.integer_constants.iterator();
                while (i_it.next()) |e| {
                    std.debug.print("{} -> {any}\n", .{ e.key, e.value.* });
                }

                std.debug.print("BOOLEAN CONSTANTS:\n", .{});
                var b_it = assembler.boolean_constants.iterator();
                while (b_it.next()) |e| {
                    std.debug.print("{} -> {}\n", .{ e.key, e.value.* });
                }

                std.debug.print("UNIFORMS:\n", .{});
                var u_it = assembler.uniforms.iterator();
                while (u_it.next()) |e| {
                    std.debug.print("{s} -> {}\n", .{ e.key_ptr.*, e.value_ptr.* });
                }

                std.debug.print("INPUTS:\n", .{});
                var in_it = assembler.inputs.iterator();
                while (in_it.next()) |e| {
                    std.debug.print("{}\n", .{e});
                }

                std.debug.print("OUTPUTS:\n", .{});
                var out_it = assembler.outputs.iterator();
                while (out_it.next()) |e| {
                    std.debug.print("{} -> {s}\n", .{ e.key, @tagName(e.value.*) });
                }

                std.debug.print("ENTRY: {?}\n", .{assembler.entry});
                return 0;
            }

            const entry = assembler.entry orelse {
                std.debug.print("cannot write shbin: no entry was found in {s}\n", .{file_path});
                return 1;
            };

            if (!assembler.labels.contains(entry.start) or !assembler.labels.contains(entry.end)) {
                std.debug.print("start or end entry label was not found in '{s}'", .{file_path});
                return 1;
            }

            @panic("TODO");
            // const output_path = file_path[0..(file_path.len - std.fs.path.extension(file_path).len)];
            // const output_file = try cwd.createFile(output_path, .{});
            //
            // var output_buffered = std.io.bufferedWriter(output_file.writer());
            // const out = output_buffered.writer();
            //
            // try out.writeStructEndian(shbin.Header{
            //     .dvle_num = 1,
            // }, .little);
            //
            // const encoder = assembler.encoder;
            // const encoded_shader_binary_len: u32 = @intCast(encoder.instructions.items.len * @sizeOf(pica.encoding.Instruction));
            // const dvlp_section_size: u32 = @intCast(@sizeOf(shbin.Dvlp) + encoded_shader_binary_len + encoder.descriptors.len * @sizeOf(pica.encoding.OperandDescriptor));
            //
            // const dvle_offset: u32 = @intCast(@sizeOf(shbin.Header) + @sizeOf(u32) * 1 + dvlp_section_size);
            // try out.writeInt(u32, dvle_offset, .little);
            //
            // try out.writeStructEndian(shbin.Dvlp{
            //     .version = 0,
            //     .shader_binary_offset = @sizeOf(shbin.Dvlp),
            //     .shader_binary_size = @intCast(encoder.instructions.items.len),
            //     .operand_descriptor_offset = @intCast(@sizeOf(shbin.Dvlp) + encoded_shader_binary_len),
            //     .operand_descriptor_entries = @intCast(encoder.descriptors.len),
            //     ._unknown0 = 0,
            //     .filename_symbol_table_offset = 0,
            //     .filename_symbol_table_size = 0,
            // }, .little);
            //
            // for (encoder.instructions.items) |i| {
            //     try out.writeInt(u32, @bitCast(i), .little);
            // }
            //
            // for (encoder.descriptors[0..encoder.allocated_descriptors]) |d| {
            //     try out.writeInt(u32, @bitCast(d), .little);
            // }
            //
            // const all_constants: u32 = @intCast(assembler.floating_constants.count() + assembler.integer_constants.count() + assembler.boolean_constants.count());
            // try out.writeStructEndian(shbin.Dvle{
            //     .version = 0,
            //     .type = .vertex,
            //     .merge_output_maps = false,
            //     .executable_main_offset = assembler.labels.get(entry.start).?,
            //     .executable_main_end_offset = assembler.labels.get(entry.end).?,
            //     .used_input_registers = @intCast(assembler.inputs.bits.mask),
            //     .used_output_registers = @intCast(assembler.outputs.bits.mask),
            //     .geometry_type = undefined,
            //     .starting_float_register_fixed = 0,
            //     .fully_defined_vertices_variable = 0,
            //     .vertices_variable = 0,
            //     .constant_table_offset = @intCast(@sizeOf(shbin.Dvle)),
            //     .constant_table_entries = all_constants,
            //     .label_table_offset = @intCast(@sizeOf(shbin.Dvle) + all_constants * @sizeOf(shbin.Dvle.ConstantEntry)),
            //     .label_table_entries = @intCast(assembler.labels.count()),
            //     .output_register_table_offset = @intCast(@sizeOf(shbin.Dvle) + all_constants * @sizeOf(shbin.Dvle.ConstantEntry) + assembler.labels.count() * @sizeOf(shbin.Dvle.LabelEntry)),
            //     .output_register_table_entries = @intCast(assembler.outputs.count()),
            //     .uniform_table_offset = 0,
            //     .uniform_table_entries = 0,
            //     .symbol_table_offset = 0,
            //     .symbol_table_size = 0,
            // }, .little);
            //
            // try output_buffered.flush();
            // return 0;
        },
        .disasm => @panic("TODO"),
    }
}

const std = @import("std");

const zitrus_tooling = @import("zitrus-tooling");
const pica = zitrus_tooling.pica;
const as = pica.as;
const Assembler = as.Assembler;

const shbin = zitrus_tooling.horizon.shbin;
