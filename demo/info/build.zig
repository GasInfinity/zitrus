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
    exe_mod.addAnonymousImport("6x8-font", .{ .root_source_file = b.path("assets/6x8-bitmap-font.gray") });

    const exe = zitrus.addExecutable(b, .{
        .name = "info.elf",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const info_smdh = zitrus.addMakeSmdh(b, .{
        .name = "info.smdh",
        .settings = b.path("smdh-settings.ziggy"),
    });

    const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "info.3dsx", .exe = exe, .smdh = info_smdh });
    b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "info.3dsx").step);
}
