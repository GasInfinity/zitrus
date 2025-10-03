// HACK: This generator still omits lots of things!

const spirv = struct {
    pub const Spec = struct {
        pub const OperandKind = struct {
            pub const Category = enum {
                BitEnum,
                ValueEnum,
                Id,
                Literal,
                Composite,
            };

            pub const EnumValue = struct {
                pub const Parameter = struct { kind: []const u8 };

                enumerant: []const u8,
                parameters: []const Parameter = &.{},
                value: union(enum) {
                    int: u32,
                    bitflag: []const u8,

                    pub fn jsonParse(
                        allocator: std.mem.Allocator,
                        source: anytype,
                        options: std.json.ParseOptions,
                    ) std.json.ParseError(@TypeOf(source.*))!@This() {
                        _ = options;
                        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
                            inline .string, .allocated_string => |s| return @This(){ .bitflag = s },
                            inline .number, .allocated_number => |s| return @This(){ .int = try std.fmt.parseInt(u31, s, 10) },
                            else => return error.UnexpectedToken,
                        }
                    }
                    pub const jsonStringify = @compileError("not supported");
                },
            };

            category: Category,
            kind: []const u8,
            /// Only when `category` is a `BitEnum` or `ValueEnum`.
            enumerants: ?[]const EnumValue = &.{},
            bases: []const []const u8 = &.{},
        };

        pub const Instruction = struct {
            pub const Operand = struct {
                pub const Quantifier = enum { @"?", @"*" };

                kind: []const u8,
                name: []const u8 = &.{},
                quantifier: ?Quantifier = null,
            };

            opname: []const u8,
            opcode: u32,
            operands: []const Operand = &.{},
        };

        magic_number: []const u8,
        major_version: u32,
        minor_version: u32,
        revision: u32,
        instructions: []const Instruction = &.{},
        operand_kinds: []const OperandKind = &.{},
    };
};

const Arguments = struct {
    pub const description =
        \\Source generate SPIR-V structures and enums for reading from the spec. 
    ;

    @"--": struct {
        pub const descriptions = .{ .spec = "non-unified SPIR-V specification in JSON", .output = "Filename of the source-generated code" };

        spec: []const u8,
        output: []const u8,
    },
};

pub fn main() !u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa_state.deinit() == .ok);

    const gpa = gpa_state.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const arguments = zdap.parse(args, "gen-spirv-spec", Arguments, .{});

    const spec_source = std.fs.cwd().readFileAlloc(gpa, arguments.@"--".spec, std.math.maxInt(usize)) catch |err| {
        std.debug.print("could not read spec '{s}': {t}", .{ arguments.@"--".spec, err });
        return 1;
    };
    defer gpa.free(spec_source);

    var json_arena = std.heap.ArenaAllocator.init(gpa);
    defer json_arena.deinit();

    var diagnostics: std.json.Diagnostics = .{};

    var json_scanner: std.json.Scanner = .initCompleteInput(json_arena.allocator(), spec_source);
    json_scanner.enableDiagnostics(&diagnostics);
    defer json_scanner.deinit();

    const spec: spirv.Spec = std.json.parseFromTokenSourceLeaky(spirv.Spec, json_arena.allocator(), &json_scanner, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print("could not parse spec '{s}: {t}'\n", .{ arguments.@"--".spec, err });
        std.debug.print("at {}:{}\n", .{ diagnostics.getLine(), diagnostics.getColumn() });
        return 1;
    };

    const output_file = std.fs.cwd().createFile(arguments.@"--".output, .{}) catch |err| {
        std.debug.print("could not open output file '{s}': {t}\n", .{ arguments.@"--".output, err });
        return 1;
    };
    defer output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);
    try generateSpec(&output_writer.interface, gpa, spec);
    try output_writer.interface.flush();
    return 0;
}

fn generateSpec(writer: *std.Io.Writer, gpa: std.mem.Allocator, spec: spirv.Spec) !void {
    try writer.writeAll(
        \\//! This file has been generated with `gen-spirv-spec`. Do not modify it!
        \\ 
        \\pub const Id = enum(u32) { _ };
        \\pub const LiteralInteger = u32;
        \\pub const LiteralExtInstInteger = enum(u32) { _ };
        \\pub const LiteralSpecConstantOpInteger = enum(u32) { _ };
        \\pub const LiteralContextDependentNumber = enum(u32) { _ };
        \\pub const LiteralString = []const u8;
        \\
    );

    try writer.print("pub const magic_number: u32 = {s};\n", .{spec.magic_number});
    try writer.print("pub const major_version = {};\n", .{spec.major_version});
    try writer.print("pub const minor_version = {};\n", .{spec.minor_version});
    try writer.print("pub const revision = {};\n", .{spec.revision});
    try writer.writeByte('\n');

    var seen_map: std.AutoArrayHashMapUnmanaged(u32, []const u8) = .empty;
    defer seen_map.deinit(gpa);

    for (spec.operand_kinds) |operand_kind| switch (operand_kind.category) {
        .BitEnum => {
            // TODO: Bitenum extra parameters (if needed!)
            try writer.print("pub const {f} = packed struct(u32) {{\n", .{std.zig.fmtId(operand_kind.kind)});

            if (operand_kind.enumerants) |enumerants| {
                for (enumerants) |enumerant| {
                    try writer.print("    {f}: bool,\n", .{std.zig.fmtId(enumerant.enumerant)});
                }

                try writer.print("    _: u{} = 0,\n", .{32 - enumerants.len});
            }

            try writer.writeAll("};\n");
        },
        .ValueEnum => {
            try writer.print("pub const {f} = union(Kind) {{\n", .{std.zig.fmtId(operand_kind.kind)});
            try writer.print("    pub const Kind = enum(u32) {{\n", .{});

            if (operand_kind.enumerants) |enumerants| {
                try seen_map.reinit(gpa, &.{}, &.{});

                for (enumerants) |enumerant| {
                    if (seen_map.get(enumerant.value.int)) |last| {
                        try writer.print("        // pub const {f}: {f} = .{f};\n", .{ std.zig.fmtId(enumerant.enumerant), std.zig.fmtId(operand_kind.kind), std.zig.fmtId(last) });
                        continue;
                    }

                    try seen_map.put(gpa, enumerant.value.int, enumerant.enumerant);
                    try writer.print("        {f} = {},\n", .{ std.zig.fmtId(enumerant.enumerant), enumerant.value.int });
                }
            }

            try writer.print("        _,\n", .{});
            try writer.writeAll("    };\n");

            if (operand_kind.enumerants) |enumerants| for (enumerants) |enumerant| {
                if (seen_map.get(enumerant.value.int)) |seen| if (!std.mem.eql(u8, seen, enumerant.enumerant)) {
                    continue;
                };

                try writer.print("    {f}", .{std.zig.fmtId(enumerant.enumerant)});

                switch (enumerant.parameters.len) {
                    0 => try writer.writeAll(",\n"),
                    1 => try writer.print(": {s},\n", .{enumerant.parameters[0].kind}),
                    else => {
                        try writer.writeAll(": struct {\n");

                        for (enumerant.parameters) |parameter| {
                            try writer.print("        {s},\n", .{parameter.kind});
                        }

                        try writer.writeAll("    },\n");
                    },
                }
            };

            try writer.writeAll("};\n");
        },
        .Id => try writer.print("pub const {s} = Id;\n", .{operand_kind.kind}),
        .Literal => {}, // Already written above
        .Composite => {
            try writer.print("pub const {s} = struct {{\n", .{operand_kind.kind});
            if (operand_kind.bases.len > 0) for (operand_kind.bases) |base| {
                try writer.print("    {s},\n", .{base});
            };
            try writer.writeAll("};\n");
        },
    };

    if (spec.instructions.len > 0) {
        try writer.writeAll(
            \\pub const instruction = struct {
            \\    pub const Opcode = enum(u16) {
            \\
        );

        // Write opcodes
        for (spec.instructions) |inst| try writer.print("        {s} = {},\n", .{ inst.opname, inst.opcode });
        try writer.writeAll("    };\n");

        for (spec.instructions) |inst| {
            try writer.print("    pub const {s} = struct {{\n", .{inst.opname});

            for (inst.operands) |op| {
                if (op.quantifier) |quantifier| switch (quantifier) {
                    .@"?" => try writer.print("        ?{s},\n", .{op.kind}),
                    .@"*" => try writer.print("        []const {s},\n", .{op.kind}),
                } else try writer.print("        {s},\n", .{op.kind});
            }

            try writer.writeAll("    };\n");
        }
        try writer.writeAll("};\n");
    }
}

const std = @import("std");
const zdap = @import("zdap");
