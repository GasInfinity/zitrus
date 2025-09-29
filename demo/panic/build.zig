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

    const exe = zitrus.addExecutable(b, .{
        .name = "panic.elf",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const panic_smdh = zitrus.addMakeSmdh(b, .{
        .name = "panic.icn",
        .settings = b.path("smdh-settings.zon"),
    });

    const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "panic.3dsx", .exe = exe, .smdh = panic_smdh });
    b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "panic.3dsx").step);
}
