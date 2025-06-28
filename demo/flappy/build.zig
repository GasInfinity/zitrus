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
    exe_mod.addAnonymousImport("bird", .{ .root_source_file = b.path("assets/bird.bgr") });
    exe_mod.addAnonymousImport("pipes", .{ .root_source_file = b.path("assets/pipes.bgr") });
    exe_mod.addAnonymousImport("ground", .{ .root_source_file = b.path("assets/ground.bgr") });
    exe_mod.addAnonymousImport("titles", .{ .root_source_file = b.path("assets/titles.bgr") });

    const exe = zitrus.addExecutable(b, .{
        .name = "flappy.elf",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const flappy_smdh = zitrus.addMakeSmdh(b, .{
        .name = "flappy.smdh",
        .settings = b.path("smdh-settings.ziggy"),
        .icon = b.path("icon.png"),
    });

    const final_3dsx = zitrus.addMake3dsx(b, .{ .name = "flappy.3dsx", .exe = exe, .smdh = flappy_smdh });

    b.getInstallStep().dependOn(&b.addInstallBinFile(final_3dsx, "flappy.3dsx").step);
}
