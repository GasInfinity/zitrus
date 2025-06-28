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
        pub const descriptions = .{ .@"asm" = "assemble a PICA200 zitrus shader assembly file", .disasm = "TODO: disassemble PICA200 shader assembly" };

        @"asm": struct { ofmt: OutputFormat = .shbin, positional: struct {
            pub const descriptions = .{
                .file = "file to assemble",
            };

            file: []const u8,
            trailing: []const []const u8,
        } },
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

            // const output_path = file_path[0..(file_path.len - std.fs.path.extension(file_path))];
            // _ = output_path;
            return 0;
        },
        .disasm => @panic("TODO"),
    }
}

const std = @import("std");

const zitrus_tooling = @import("zitrus-tooling");
const pica = zitrus_tooling.pica;
const as = pica.as;
const Assembler = as.Assembler;
