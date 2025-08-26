const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const no_bin = b.option(bool, "no-bin", "Don't emit a binary (incremental compilation)") orelse false;

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(zitrus.target.horizon_arm11),
        .optimize = optimize,
        .single_threaded = true,
    });

    exe_mod.addImport("zitrus", zitrus_mod);
    exe_mod.addAnonymousImport("simple.zpsh", .{ .root_source_file = zitrus.addAssembleZpsm(b, .{
        .name = "simple.zpsh",
        .root_source_file = b.path("assets/simple.zpsm"),
    }) });
    exe_mod.addAnonymousImport("test.bgr", .{ .root_source_file = b.path("assets/test.bgr") });

    const exe = zitrus.addExecutable(b, .{
        .name = "gpu.elf",
        .root_module = exe_mod,
    });

    if(no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);

        const bitmap_smdh = zitrus.addMakeSmdh(b, .{
            .name = "gpu.icn",
            .settings = b.path("smdh-settings.ziggy"),
        });

        const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "gpu.3dsx", .exe = exe, .smdh = bitmap_smdh });

        b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "gpu.3dsx").step);
    }
}
