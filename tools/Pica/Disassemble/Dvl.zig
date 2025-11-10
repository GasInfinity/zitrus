pub const description = "Disassemble DVL (.shbin) shaders, used in official and homebrew 3DS titles.";

pub const descriptions = .{
    .output = "Output file, if none stdout is used",
};

pub const switches = .{
    .output = 'o',
};

output: ?[]const u8,

@"--": struct {
    pub const descriptions = .{
        .input = "Input file, if none stdin is used",
    };

    input: ?[]const u8,
},

pub fn main(args: Dvl, arena: std.mem.Allocator) !u8 {
    const cwd = std.fs.cwd();

    const input_file, const input_should_close = if (args.@"--".input) |in|
        .{ cwd.openFile(in, .{ .mode = .read_only }) catch |err| {
            log.err("could not open input file '{s}': {t}", .{ in, err });
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

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.readerStreaming(&input_buffer);
    const in = &input_reader.interface;

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writerStreaming(&output_buffer);
    const out = &output_writer.interface;

    const hdr = try in.takeStruct(dvl.Header, .little);

    hdr.check() catch |err| {
        log.err("header check failed: {t}", .{err});
        return 1;
    };

    const entrypoint_file_offsets = try in.readSliceEndianAlloc(arena, u32, hdr.entrypoints, .little);
    defer arena.free(entrypoint_file_offsets);

    std.mem.sort(u32, entrypoint_file_offsets, {}, comptime std.sort.asc(u32));

    const program_hdr = try in.takeStruct(dvl.ProgramHeader, .little);

    program_hdr.check() catch |err| {
        log.err("program header check failed: {t}", .{err});
        return 1;
    };

    if (program_hdr.instructions.size > std.math.maxInt(u12)) {
        log.err("dvl has too many instructions! ({} > 4096)", .{program_hdr.instructions.size});
        return 1;
    }

    if (program_hdr.descriptors.size > std.math.maxInt(u7)) {
        log.err("dvl has too many operand descriptors! ({} > 128)", .{program_hdr.instructions.size});
        return 1;
    }

    // TODO: We're assuming Instructions -> Descriptors -> Entrypoints
    try in.discardAll((program_hdr.instructions.offset - @sizeOf(dvl.ProgramHeader)));

    const instructions = try arena.alloc(Instruction, program_hdr.instructions.size);
    try in.readSliceEndian(u32, @ptrCast(instructions), .little);

    try in.discardAll((program_hdr.descriptors.offset - (program_hdr.instructions.offset + program_hdr.instructions.size * @sizeOf(u32))));
    const descriptors = try arena.alloc(OperandDescriptor, program_hdr.descriptors.size);

    // Don't know who designed this format but great! Operand descriptors are 4 BYTES, NOT 8 BRO
    for (descriptors) |*desc| {
        desc.* = @bitCast(try in.takeInt(u32, .little));
        try in.discardAll(4);
    }

    var entry_start: std.AutoArrayHashMapUnmanaged(u12, []const u8) = .empty;
    defer {
        var it = entry_start.iterator();
        while (it.next()) |e| arena.free(e.value_ptr.*);
        entry_start.deinit(arena);
    }

    try out.print("; DVL with {} instruction(s) and {} operand descriptor(s)\n", .{ instructions.len, descriptors.len });
    try out.writeByte('\n');

    var last: u32 = @sizeOf(dvl.Header) + hdr.entrypoints * @sizeOf(u32) + program_hdr.descriptors.offset + program_hdr.descriptors.size * 8;
    for (entrypoint_file_offsets, 0..) |entry_offset, i| {
        if (entry_offset < last) {
            log.err("entrypoints overlap with each other ({} < {})", .{ entry_offset, last });
            return 1;
        }

        try in.discardAll(entry_offset - last);

        const entry = try in.takeStruct(dvl.EntrypointHeader, .little);
        last = entry_offset + @sizeOf(dvl.EntrypointHeader);

        entry.check() catch |err| {
            log.err("invalid entrypoint ({}): {t}, skipping", .{ i, err });
            continue;
        };

        if (entry.entry.start > instructions.len or entry.entry.end > instructions.len) {
            log.err("invalid entrypoint ({}) range {X:0>3} - {X:0>3}, skipping", .{ i, entry.entry.start, entry.entry.end });
            continue;
        }

        switch (entry.type) {
            .vertex => try out.print(".entry E_{X:0>3} vertex\n", .{i}),
            .geometry => switch (entry.geometry.type) {
                .point => try out.print(".entry E_{X:0>3} geometry point {}\n", .{ i, entry.used_input_registers.count() }),
                .variable => try out.print(".entry E_{X:0>3} geometry variable {}\n", .{ i, entry.geometry.fully_defined_vertices }),
                .fixed => switch (entry.geometry.uniform_start.register) {
                    else => try out.print(".entry E_{X:0>3} geometry fixed {} {t}\n", .{ i, entry.geometry.fixed_vertices, entry.geometry.uniform_start.register }),
                    _ => |r| {
                        log.err("invalid entrypoint ({}) fixed geometry uniform start {}, skipping", .{ i, @intFromEnum(r) });
                        continue;
                    },
                },
                _ => {
                    log.err("invalid entrypoint ({}) geometry type {}, skipping", .{ i, @intFromEnum(entry.type) });
                    continue;
                },
            },
            _ => {
                log.err("invalid entrypoint ({}) type {}, skipping", .{ i, @intFromEnum(entry.type) });
                continue;
            },
        }
        try out.writeByte('\n');
        try out.print("; {} used inputs. {} used ouputs\n", .{ entry.used_input_registers.count(), entry.used_output_registers.count() });
        try out.writeByte('\n');

        // NOTE: We do this to support streaming without seeking (stdin!)
        var region_mapping: [5]EntrypointRegion = .{
            .init(.constant_table, entry.constant_table),
            .init(.uniform_table, entry.uniform_table),
            .init(.output_register_table, entry.output_register_table),
            .init(.symbol_table, entry.symbol_table),
            .init(.label_table, entry.label_table),
        };

        std.mem.sort(EntrypointRegion, &region_mapping, {}, EntrypointRegion.lessThan);

        var region_last: u32 = @sizeOf(dvl.EntrypointHeader);
        for (&region_mapping) |map| {
            if (map.blob.size == 0) {
                try out.print("; E_{X:0>3} has no {t}\n", .{ i, map.kind });
                continue;
            }

            if (map.blob.offset < region_last) {
                log.err("entrypoint ({}) region {t} overlaps with previous data ({} < {}), skipping region", .{ i, map.kind, map.blob.offset, region_last });
                continue;
            }

            try in.discardAll(map.blob.offset - region_last);
            region_last = map.blob.offset;

            switch (map.kind) {
                .uniform_table => {
                    for (0..map.blob.size) |current_uniform| {
                        const uniform = try in.takeStruct(dvl.UniformEntry, .little);
                        const start_end_slice: []const dvl.UniformEntry.Register = &.{ uniform.register_start, uniform.register_end };
                        const kind_slice: []const []const u8 = &.{ "start", "end" };

                        for (start_end_slice, kind_slice) |start_end, kind| switch (start_end) {
                            _ => {
                                log.err("invalid entrypoint ({}) uniform ({}) {s} {}", .{ i, current_uniform, kind, @intFromEnum(start_end) });
                                continue;
                            },
                            else => {},
                        };

                        try out.print("; E_{X:0>3} has uniform [{t}-{t}] with symbol offset 0x{X:0>8}\n", .{ i, uniform.register_start, uniform.register_end, uniform.offset });
                    }

                    region_last += map.blob.size * @sizeOf(dvl.UniformEntry);
                },
                .output_register_table => {
                    for (0..map.blob.size) |current_output| {
                        const output = try in.takeStruct(dvl.OutputEntry, .little);

                        if (output.register > std.math.maxInt(u4)) {
                            log.err("invalid entrypoint ({}) output ({}) register {}", .{ i, current_output, output.register });
                            continue;
                        }

                        switch (output.semantic) {
                            else => try out.print(".out E_{X:0>3} {t}.{f} {t}\n", .{ i, @as(shader.register.Destination.Output, @enumFromInt(output.register)), output.mask.native(), output.semantic }),
                            .texture_coordinates_0_w => try out.print(".out E_{X:0>3} {t}.{f} texture_coordinates_0.z\n", .{ i, @as(shader.register.Destination.Output, @enumFromInt(output.register)), output.mask.native() }),
                            _ => {
                                log.err("invalid entrypoint ({}) output ({}) semantic {}", .{ i, current_output, @intFromEnum(output.semantic) });
                                continue;
                            },
                        }
                    }
                    try out.writeByte('\n');

                    region_last += map.blob.size * @sizeOf(dvl.OutputEntry);
                },
                .label_table => {
                    log.warn("TODO: skipping labels...", .{});
                    try in.discardAll(map.blob.size * @sizeOf(dvl.LabelEntry));
                    region_last += map.blob.size * @sizeOf(dvl.LabelEntry);
                },
                .symbol_table => {
                    var symbol_offset: usize = 0;
                    while (symbol_offset < map.blob.size) {
                        const symbol = try in.takeDelimiter(0) orelse &.{};

                        try out.print("; E_{X:0>3} has symbol 0x{X:0>8} {s}\n", .{ i, symbol_offset, symbol });

                        symbol_offset += symbol.len + 1;
                    }
                    try out.writeByte('\n');

                    region_last += map.blob.size;
                },
                .constant_table => {
                    for (0..map.blob.size) |current_constant| {
                        const const_entry = try in.takeStruct(dvl.ConstantEntry, .little);

                        const max_register: u8 = switch (const_entry.type) {
                            .bool => std.math.maxInt(u4),
                            .u8x4 => std.math.maxInt(u2),
                            .f24x4 => 95,
                            _ => {
                                log.err("invalid entrypoint ({}) constant ({}) type {}", .{ i, current_constant, @intFromEnum(const_entry.type) });
                                continue;
                            },
                        };

                        if (const_entry.register > max_register) {
                            log.err("invalid entrypoint ({}) constant ({}) register b{}", .{ i, current_constant, const_entry.register });
                            continue;
                        }

                        const u8x4 = const_entry.data.u8x4;
                        const f24x4 = const_entry.data.f24x4;
                        switch (const_entry.type) {
                            .bool => try out.print(".set E_{X:0>3} b{} {}\n", .{ i, const_entry.register, const_entry.data.bool }),
                            .u8x4 => try out.print(".set E_{X:0>3} i{} ({}, {}, {}, {})\n", .{ i, const_entry.register, u8x4[0], u8x4[1], u8x4[2], u8x4[3] }),
                            .f24x4 => try out.print(".set E_{X:0>3} f{} ({}, {}, {}, {})\n", .{
                                i,
                                const_entry.register,
                                @as(f32, @bitCast(pica.F8_23.of(f24x4[0].value))),
                                @as(f32, @bitCast(pica.F8_23.of(f24x4[1].value))),
                                @as(f32, @bitCast(pica.F8_23.of(f24x4[2].value))),
                                @as(f32, @bitCast(pica.F8_23.of(f24x4[3].value))),
                            }),
                            _ => unreachable,
                        }
                    }
                    try out.writeByte('\n');

                    region_last += map.blob.size * @sizeOf(dvl.ConstantEntry);
                },
            }
        }
        last += region_last - @sizeOf(dvl.EntrypointHeader);

        try entry_start.put(arena, @intCast(entry.entry.start), try std.fmt.allocPrint(arena, "E_{X:0>3}", .{i}));
    }

    for (instructions, 0..) |inst, i| {
        if (entry_start.get(@intCast(i))) |name| {
            try out.print("{s}:\n", .{name});
        }

        try out.print("L_{X:0>3}: {f}\n", .{ i, inst.fmtDisassemble(descriptors) });
    }

    try out.flush();
    _ = try in.discardRemaining();
    return 0;
}

const EntrypointRegion = struct {
    pub const Kind = enum {
        constant_table,
        label_table,
        uniform_table,
        output_register_table,
        symbol_table,
    };

    kind: Kind,
    blob: dvl.Blob,

    pub fn init(region: Kind, blob: dvl.Blob) EntrypointRegion {
        return .{ .kind = region, .blob = blob };
    }

    pub fn lessThan(_: void, a: EntrypointRegion, b: EntrypointRegion) bool {
        return a.blob.offset < b.blob.offset;
    }
};

const Dvl = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const zitrus = @import("zitrus");

const dvl = zitrus.horizon.fmt.dvl;

const pica = zitrus.hardware.pica;
const shader = pica.shader;
const Instruction = shader.encoding.Instruction;
const OperandDescriptor = shader.encoding.OperandDescriptor;
const Component = shader.encoding.Component;
