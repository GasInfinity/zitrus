pub const description = "Disassemble PICA200 shader ISA into zitrus PICA200 shader assembly.";

pub const Format = enum {
    pub const descriptions = .{
        .bin = "RAW PICA200 instructions and operand descriptors",
        .zpsh = "Simpler shader format which is currently specific to zitrus",
        .shbin = "Shader format used in official and homebrew 3DS titles",
    };

    bin,
    zpsh,
    shbin,
};

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
};

pub const switches = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .fmt = "Format of the file",
        .@"..." = "Input files, if none stdin is used (RAW cannot be piped from stdin)",
    };

    fmt: Format,
    @"...": []const []const u8,
},

pub fn main(args: Disassemble, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    const input_file, const input_should_close = if (args.@"--".@"...".len > 0)
        .{ cwd.openFile(args.@"--".@"..."[0], .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ args.@"--".@"..."[0], err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdin(), false };
    defer if (input_should_close) input_file.close();

    const output_file, const output_should_close = if (args.output) |out|
        .{ cwd.createFile(out, .{}) catch |err| {
            log.err("could not open output file '{s}': {t}", .{ out, err });
            return 1;
        }, true }
    else
        .{ std.fs.File.stdout(), false };
    defer if (output_should_close) output_file.close();

    switch (args.@"--".fmt) {
        .bin => @panic("TODO"),
        .shbin => @panic("TODO"),
        .zpsh => {
            const max_buffer = try arena.alignedAlloc(u8, .of(u32), @sizeOf(zpsh.Header) + 4096 * @sizeOf(u32) + 128 * @sizeOf(u32) + 0x10000);
            defer arena.free(max_buffer);

            // TODO: We can avoid having to read the entire ZPSH.
            const zpsh_data = blk: {
                var input_reader = input_file.readerStreaming(&.{});
                const read = try input_reader.interface.readSliceShort(max_buffer);

                break :blk max_buffer[0..read];
            };
            defer arena.free(zpsh_data);

            var buffer: [4096]u8 = undefined;
            var output_writer = output_file.writerStreaming(&buffer);

            const parsed = zpsh.Parsed.initBuffer(zpsh_data) catch |err| {
                log.err("error parsing ZPSH: {t}", .{err});
                return 1;
            };

            var entry_start: std.AutoArrayHashMapUnmanaged(u12, []const u8) = .empty;
            defer entry_start.deinit(arena);

            try output_writer.interface.print("; ZPSH with {} instruction(s) and {} operand descriptor(s)\n", .{ parsed.instructions.len, parsed.operand_descriptors.len });

            var entry_it = parsed.entrypointIterator();

            while (entry_it.next()) |entry| {
                try output_writer.interface.print(".entry {s} ", .{ entry.name });

                switch (entry.info.type) {
                    .vertex => try output_writer.interface.print("vertex\n", .{}),
                    .geometry_point => try output_writer.interface.print("geometry point {}\n", .{@as(u5, entry.info.geometry.point.inputs_minus_one) + 1}),
                    .geometry_variable => try output_writer.interface.print("geometry variable {}\n", .{entry.info.geometry.variable.full_vertices}),
                    .geometry_fixed => try output_writer.interface.print("geometry fixed {} {t}\n", .{@as(u5, entry.info.geometry.fixed.vertices_minus_one) + 1, entry.info.geometry.fixed.uniform_start}),
                }

                try output_writer.interface.writeByte('\n');

                {
                    var out_it = entry.output_set.iterator();
                    var i: u8 = 0;

                    while (out_it.next()) |o| : (i += 1) {
                        const map = entry.output_map[i];
                        const semantics: []const pica.OutputMap.Semantic = &.{ map.x, map.y, map.z, map.w };

                        var mask: Component.Mask = .{};

                        for (semantics, 0..) |s, p| {
                            switch (s) {
                                .unused => continue,
                                else => mask = mask.copyWith(@intCast(p), true),
                            }
                        }

                        // TODO: Proper output mapping
                        try output_writer.interface.print("; .out {s} {t}.{f}\n", .{ entry.name, o, mask });
                    }

                    if(i > 0) try output_writer.interface.writeByte('\n');
                }

                {
                    var float_it = entry.floating_constant_set.iterator();
                    var i: u8 = 0;

                    while (float_it.next()) |float| : (i += 1) {
                        const packed_constant = entry.floating_constants[i];
                        const unpacked_constant: [4]pica.F7_16 = packed_constant.unpack();
                        const constant: [4]f32 = .{
                            @bitCast(pica.F8_23.of(unpacked_constant[0])),
                            @bitCast(pica.F8_23.of(unpacked_constant[1])),
                            @bitCast(pica.F8_23.of(unpacked_constant[2])),
                            @bitCast(pica.F8_23.of(unpacked_constant[3])),
                        };

                        try output_writer.interface.print(".set {s} {t} ({}, {}, {}, {})", .{ entry.name, float, constant[0], constant[1], constant[2], constant[3] });
                    }

                    if (i > 0) try output_writer.interface.writeByte('\n');
                }

                {
                    var int_it = entry.integer_constant_set.iterator();
                    var i: u8 = 0;

                    while (int_it.next()) |int| : (i += 1) {
                        const constant = entry.integer_constants[i];
                        try output_writer.interface.print(".set {s} {t} ({}, {}, {}, {})", .{ entry.name, int, constant[0], constant[1], constant[2], constant[3] });
                    }

                    if (i > 0) try output_writer.interface.writeByte('\n');
                }

                var bool_it = entry.boolean_constant_set.iterator();
                while (bool_it.next()) |b| {
                    try output_writer.interface.print(".set {s} {t} {}\n", .{ entry.name, b, true });
                }

                if (entry.boolean_constant_set.count() > 0) try output_writer.interface.writeByte('\n');
                try entry_start.put(arena, entry.offset, entry.name);
            }

            for (parsed.instructions, 0..) |inst, i| {
                if (entry_start.get(@intCast(i))) |name| {
                    try output_writer.interface.print("{s}:\n", .{name});
                }

                try output_writer.interface.print("L_{X:0>3}: {f}\n", .{ i, inst.fmtDisassemble(parsed.operand_descriptors) });
            }

            try output_writer.interface.flush();
            return 0;
        },
    }
}

const Disassemble = @This();

const log = std.log.scoped(.pica);

const std = @import("std");

const zitrus = @import("zitrus");

const zpsh = zitrus.fmt.zpsh;

const pica = zitrus.hardware.pica;
const shader = pica.shader;
const Component = shader.encoding.Component;
