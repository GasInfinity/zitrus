pub const description = "Disassemble ZPSH shaders, a new and currently unstable shader format which is specific to zitrus.";

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

pub fn main(args: Zpsh, arena: std.mem.Allocator) !u8 {
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

    const hdr: zpsh.Header = try in.takeStruct(zpsh.Header, .little);

    hdr.check() catch |err| {
        log.err("could not read zpsh: {t}", .{err});
        return 1;
    };

    try in.discardAll(@as(usize, hdr.header_size) * @sizeOf(u32) - @sizeOf(zpsh.Header));

    const instructions = try arena.alloc(Instruction, hdr.shader.instructions());
    defer arena.free(instructions);
    try in.readSliceEndian(u32, @ptrCast(instructions), .little);

    var descriptors_buf: [128]OperandDescriptor = undefined;
    const descriptors = descriptors_buf[0..hdr.shader.descriptors];
    try in.readSliceEndian(u32, @ptrCast(descriptors), .little);

    const string_table = try arena.alloc(u8, (hdr.entry_string_table_size * @sizeOf(u32)));
    defer arena.free(string_table);
    try in.readSliceAll(string_table);

    try out.print("; ZPSH with {} instruction(s) and {} operand descriptor(s)\n", .{ instructions.len, descriptors.len });
    try out.writeByte('\n');

    var entry_labels: std.AutoArrayHashMapUnmanaged(u12, []const u8) = .empty;
    defer entry_labels.deinit(arena);

    for (0..hdr.shader.entrypoints) |current_entry| {
        const entry = try in.takeStruct(zpsh.EntrypointHeader, .little);
        const entry_name = blk: {
            const remaining = string_table[entry.name_string_offset..];
            const len = std.mem.indexOfScalar(u8, remaining, 0) orelse len: {
                log.err("invalid entrypoint ({}) name, it must be null-terminated!", .{current_entry});
                break :len remaining.len;
            };

            break :blk remaining[0..len];
        };

        if (entry.instruction_offset > std.math.maxInt(u12)) {
            log.err("invalid entrypoint ({} - {s}) offset, it must belong to the shader ({} > 4095)! skipping", .{ current_entry, entry_name, entry.instruction_offset });
            continue;
        }

        try entry_labels.put(arena, @intCast(entry.instruction_offset), entry_name);
        try out.print(".entry {s} ", .{entry_name});

        switch (entry.info.type) {
            .vertex => try out.print("vertex\n", .{}),
            .geometry_point => try out.print("geometry point {}\n", .{@as(u5, entry.info.geometry.point.inputs_minus_one) + 1}),
            .geometry_variable => try out.print("geometry variable {}\n", .{entry.info.geometry.variable.full_vertices}),
            .geometry_fixed => try out.print("geometry fixed {} {t}\n", .{ @as(u5, entry.info.geometry.fixed.vertices_minus_one) + 1, entry.info.geometry.fixed.uniform_start }),
        }

        try out.writeByte('\n');

        {
            const bool_set = entry.boolean_constant_mask.toSet();
            var bool_it = bool_set.iterator();
            while (bool_it.next()) |b| {
                try out.print(".set {s} {t} {}\n", .{ entry_name, b, true });
            }

            if (bool_set.count() > 0) try out.writeByte('\n');
        }

        {
            const int_set = entry.integer_constant_mask.toSet();
            var int_it = int_set.iterator();
            var i: u8 = 0;

            while (int_it.next()) |int| : (i += 1) {
                const constant: *[4]u8 = try in.takeArray(4);
                try out.print(".set {s} {t} ({}, {}, {}, {})", .{ entry_name, int, constant[0], constant[1], constant[2], constant[3] });
            }

            if (i > 0) try out.writeByte('\n');
        }

        {
            const float_set = entry.floating_constant_mask.toSet();
            var float_it = float_set.iterator();
            var i: u8 = 0;

            while (float_it.next()) |float| : (i += 1) {
                const packed_constant = try in.takeStruct(pica.F7_16x4, .little);
                const unpacked_constant: [4]pica.F7_16 = packed_constant.unpack();
                const constant: [4]f32 = .{
                    @bitCast(pica.F8_23.of(unpacked_constant[0])),
                    @bitCast(pica.F8_23.of(unpacked_constant[1])),
                    @bitCast(pica.F8_23.of(unpacked_constant[2])),
                    @bitCast(pica.F8_23.of(unpacked_constant[3])),
                };

                try out.print(".set {s} {t} ({}, {}, {}, {})", .{ entry_name, float, constant[0], constant[1], constant[2], constant[3] });
            }

            if (i > 0) try out.writeByte('\n');
        }

        {
            const out_set = entry.output_mask.toSet();
            var out_it = out_set.iterator();
            var i: u8 = 0;

            while (out_it.next()) |o| : (i += 1) {
                const map = try in.takeStruct(pica.OutputMap, .little);
                const semantics: []const pica.OutputMap.Semantic = &.{ map.x, map.y, map.z, map.w };

                var mask: Component.Mask = .{};

                for (semantics, 0..) |s, p| {
                    switch (s) {
                        .unused => continue,
                        else => mask = mask.copyWith(@intCast(p), true),
                    }
                }

                // TODO: Proper output mapping
                try out.print("; .out {s} {t}.{f}\n", .{ entry_name, o, mask });
            }

            if (i > 0) try out.writeByte('\n');
        }
    }

    for (instructions, 0..) |inst, i| {
        if (entry_labels.get(@intCast(i))) |name| {
            try out.print("{s}:\n", .{name});
        }

        try out.print("L_{X:0>3}: {f}\n", .{ i, inst.fmtDisassemble(descriptors) });
    }

    try out.flush();
    return 0;
}

const Zpsh = @This();

const log = std.log.scoped(.pica);

const std = @import("std");
const zitrus = @import("zitrus");

const zpsh = zitrus.fmt.zpsh;

const pica = zitrus.hardware.pica;
const shader = pica.shader;
const Instruction = shader.encoding.Instruction;
const OperandDescriptor = shader.encoding.OperandDescriptor;
const Component = shader.encoding.Component;
