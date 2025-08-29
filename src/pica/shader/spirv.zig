const spec = @import("spirv/spec.zig");

const testing = std.testing;

test "embed spv" {
    const vtx_spv = @embedFile("vtx.spv");

    var fixed_reader: std.Io.Reader = .fixed(vtx_spv);

    const file_magic = try fixed_reader.takeArray(4);
    const file_endianness = spec.detectEndianness(file_magic.*) orelse unreachable;
    const file_version = try fixed_reader.takeStruct(spec.Version, file_endianness);
    std.debug.print("Version: {}.{}\n", .{ file_version.major, file_version.minor });

    const file_generator = try fixed_reader.takeInt(u32, file_endianness);
    std.debug.print("Generator: {}\n", .{file_generator});

    const file_bound = try fixed_reader.takeInt(u32, file_endianness);
    std.debug.print("Bound: {}\n", .{file_bound});

    const file_schema = try fixed_reader.takeInt(u32, file_endianness);
    std.debug.print("Schema: {}\n", .{file_schema});

    var inst_it: spec.InstructionIterator = .init(&fixed_reader, file_endianness);

    const gpa = std.testing.allocator;
    while (try inst_it.next(gpa)) |inst| switch (inst) {
        .nop => std.debug.print("nop\n", .{}),
        .undef => |info| std.debug.print("undef {}\n", .{info}),
        .capability => |cap| std.debug.print("capability seen: {}, supported: {}\n", .{ cap, cap.isSupported() }),
        .ext_inst_import => |import| {
            std.debug.print("Extended instruction: {s}\n", .{import.name});
            gpa.free(import.name);
        },
        .memory_model => |model| std.debug.print("{} and {}\n", .{ model.addressing, model.memory }),
        .entry_point => |entry| {
            std.debug.print("Entry {} {s}, {any}\n", .{ entry.execution_mode, entry.name, entry.interface });
            gpa.free(entry.name);
            gpa.free(entry.interface);
        },
        .decorate => |info| {
            std.debug.print("Decorate: {} {} {}\n", .{ info.decoration, info.target, info.extra });
        },
        .member_decorate => |info| {
            std.debug.print("MemberDecorate: {} {} {} {}\n", .{ info.decoration, info.type, info.member, info.extra });
        },
        else => {},
    };
}

const std = @import("std");
