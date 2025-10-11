const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe = b.addExecutable(.{
        .name = "flappy.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(zitrus.target.arm11.horizon.query),
            .optimize = optimize,
            .single_threaded = true,
            .imports = &.{
                .{ .name = "zitrus", .module = zitrus_mod },
            },
        }),
    });

    exe.root_module.addAnonymousImport("bird", .{ .root_source_file = b.path("assets/bird.bgr") });
    exe.root_module.addAnonymousImport("pipes", .{ .root_source_file = b.path("assets/pipes.bgr") });
    exe.root_module.addAnonymousImport("ground", .{ .root_source_file = b.path("assets/ground.bgr") });
    exe.root_module.addAnonymousImport("titles", .{ .root_source_file = b.path("assets/titles.bgr") });

    exe.link_emit_relocs = true;
    exe.setLinkerScript(zitrus_dep.path(zitrus.target.arm11.horizon.linker_script));
    b.installArtifact(exe);

    const smdh = zitrus.MakeSmdh.init(zitrus_dep, .{
        .settings = b.path("smdh-settings.zon"),
        .icon = b.path("icon.png"),
    });

    const final_3dsx = zitrus.Make3dsx.init(zitrus_dep, .{
        .exe = exe,
        .smdh = smdh.out,
    });

    final_3dsx.install(b, .default);
}
