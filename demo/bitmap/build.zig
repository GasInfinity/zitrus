const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(zitrus.target.horizon_arm11),
        .optimize = optimize,
        .single_threaded = true,
    });

    exe_mod.addImport("zitrus", zitrus_mod);
    exe_mod.addAnonymousImport("top-screen", .{ .root_source_file = b.path("assets/top.bgr") });
    exe_mod.addAnonymousImport("bottom-screen", .{ .root_source_file = b.path("assets/bottom.bgr") });

    const exe = zitrus.addExecutable(b, .{
        .name = "bitmap.elf",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const bitmap_smdh = zitrus.addMakeSmdh(b, .{
        .name = "bitmap.smdh",
        .settings = b.path("smdh-settings.ziggy"),
    });

    const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "bitmap.3dsx", .exe = exe, .smdh = bitmap_smdh });

    b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "bitmap.3dsx").step);
}
