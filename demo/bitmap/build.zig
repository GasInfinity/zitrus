const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe = b.addExecutable(.{
        .name = "bitmap.elf",
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

    exe.root_module.addAnonymousImport("top-screen", .{ .root_source_file = b.path("assets/top.bgr") });
    exe.root_module.addAnonymousImport("bottom-screen", .{ .root_source_file = b.path("assets/bottom.bgr") });

    exe.link_emit_relocs = true;
    exe.setLinkerScript(zitrus_dep.path(zitrus.target.arm11.horizon.linker_script));
    b.installArtifact(exe);

    const smdh = zitrus.MakeSmdh.init(zitrus_dep, .{
        .settings = b.path("smdh-settings.zon"),
    });

    const final_3dsx = zitrus.Make3dsx.init(zitrus_dep, .{
        .exe = exe,
        .smdh = smdh.out,
    });

    final_3dsx.install(b, .default);
}
