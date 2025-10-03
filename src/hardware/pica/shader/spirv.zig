//! TODO: So, here's the thing. SPIR-V -> PICA200 SH ISA:
//! - Shader + Matrix + Geometry capabilities supported.
//! - Logical addressing mode + Simple/GLSL450 memory model.
//! - Output semantics are hardcoded to locations, which means:
//!     - location: 0 -> color (vec4), 1 -> texture coordinate 0 (vec3 includes w, vec2 doesn't), 2 -> tc1 (vec2), 3 -> tc2 (vec2), 4 -> view (vec3) , 5 -> normal (vec4).
//!     - gl_Position == position
//! - TODO (GasInfinity): What do we do with Geometry Shaders? Currently not even the assembler supports geometry entrypoint, they need some investigation + testing!
//!
//!
//! See https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html

const spec = void; //@import("spirv/spec.zig");
const Reader = void; //@import("spirv/Reader.zig");

const testing = std.testing;

test "embed spv" {
    if (true) return;

    const vtx_spv = @embedFile("spirv/vtx.spv");
    var fixed_reader: std.Io.Reader = .fixed(vtx_spv);
    const spv_reader: Reader = try .init(&fixed_reader);

    std.debug.print("Version: {}.{}\n", .{ spv_reader.version.major, spv_reader.version.minor });
    std.debug.print("Bound: {}\n", .{spv_reader.bound});

    while (try spv_reader.peekPrefix()) |pref| if (pref.opcode == .OpCapability) {
        const inst = (try spv_reader.takeInstruction()).?;
        const capability = try spv_reader.decodeInstruction(spec.instruction.OpCapability, inst);

        switch (capability[0]) {
            .Shader, .Matrix, .Geometry => {},
            else => return error.UnsupportedCapability,
        }
    } else break;

    while (try spv_reader.peekPrefix()) |pref| if (pref.opcode == .OpExtension) {
        std.debug.print("OpExtension\n", .{});
        _ = try spv_reader.takeInstruction();
    } else break;

    while (try spv_reader.peekPrefix()) |pref| if (pref.opcode == .OpExtInstImport) {
        std.debug.print("OpExtInstImport\n", .{});
        _ = try spv_reader.takeInstruction();
    } else break;

    const addressing_model, const memory_model = model: {
        const pref = try spv_reader.peekPrefix();
        if (pref == null) return error.ExpectedMemoryModel;

        const memory_model_inst = (try spv_reader.takeInstruction()).?;

        break :model try spv_reader.decodeInstruction(spec.instruction.OpMemoryModel, memory_model_inst);
    };

    if (addressing_model != .Logical or (memory_model != .Simple and memory_model != .GLSL450)) return error.InvalidMemoryModel;

    while (try spv_reader.peekPrefix()) |pref| if (pref.opcode == .OpEntryPoint) {
        std.debug.print("OpEntryPoint\n", .{});
        _ = try spv_reader.takeInstruction();
    } else break;

    // Debug instructions can be skipped safely.
    while (try spv_reader.peekPrefix()) |pref| switch (pref.opcode) {
        .OpString, .OpSourceExtension, .OpSource, .OpSourceContinued, .OpName, .OpMemberName, .OpModuleProcessed => _ = try spv_reader.takeInstruction(),
        else => break,
    };

    while (try spv_reader.peekPrefix()) |pref| switch (pref.opcode) {
        .OpDecorate, .OpMemberDecorate => {
            const inst = try spv_reader.takeInstruction();
            _ = inst;
        },
        else => break,
    };

    // We can safely ignore all other types as we'll never see them, we'll bail early in OpCapability.
    while (try spv_reader.peekPrefix()) |pref| switch (pref.opcode) {
        .OpVariable => _ = try spv_reader.takeInstruction(),

        .OpUndef => _ = try spv_reader.takeInstruction(),
        .OpTypeVoid => _ = try spv_reader.takeInstruction(),
        .OpTypeBool => _ = try spv_reader.takeInstruction(),
        .OpTypeInt => _ = try spv_reader.takeInstruction(),
        .OpTypeFloat => _ = try spv_reader.takeInstruction(),
        .OpTypeVector => _ = try spv_reader.takeInstruction(),
        .OpTypeMatrix => _ = try spv_reader.takeInstruction(),
        .OpTypeArray, .OpTypeRuntimeArray => _ = try spv_reader.takeInstruction(),
        .OpTypePointer => _ = try spv_reader.takeInstruction(),
        .OpTypeFunction => _ = try spv_reader.takeInstruction(),

        .OpConstantTrue, .OpConstantFalse => _ = try spv_reader.takeInstruction(),

        .OpConstant => _ = try spv_reader.takeInstruction(),
        .OpConstantComposite => _ = try spv_reader.takeInstruction(),
        .OpConstantNull => _ = try spv_reader.takeInstruction(),

        // XXX: Is this needed?
        .OpSpecConstant, .OpSpecConstantTrue, .OpSpecConstantFalse => _ = try spv_reader.takeInstruction(),

        // 100% unsupported types.
        .OpTypeImage, .OpTypeSampler, .OpTypeSampledImage => return error.UnsupportedType,

        // First time they appear and can be skipped safely.
        .OpLine, .OpNoLine, .OpExtInst => _ = try spv_reader.takeInstruction(),
        else => break,
    };

    while (try spv_reader.peekPrefix()) |pref| switch (pref.opcode) {
        else => break,
    };
}

const builtin = @import("builtin");
const std = @import("std");
