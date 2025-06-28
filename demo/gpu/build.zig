const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = zitrus_mod.resolved_target,
        .optimize = optimize,
        .single_threaded = true,
    });

    exe_mod.addImport("zitrus", zitrus_mod);

    const exe = zitrus.addExecutable(b, .{
        .name = "gpu.elf",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const bitmap_smdh = zitrus.addMakeSmdh(b, .{
        .name = "gpu.smdh",
        .settings = b.path("smdh-settings.ziggy"),
    });

    const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "gpu.3dsx", .exe = exe, .smdh = bitmap_smdh });

    b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "gpu.3dsx").step);
}
