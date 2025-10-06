const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const no_bin = b.option(bool, "no-bin", "Don't emit a binary (incremental compilation)") orelse false;

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const simple_shader = zitrus.AssembleZpsm.init(zitrus_dep, .{
        .name = "simple.zpsh",
        .root_source_file = b.path("assets/simple.zpsm"),
    });

    const exe = b.addExecutable(.{
        .name = "gpu.elf",
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

    exe.root_module.addAnonymousImport("simple.zpsh", .{ .root_source_file = simple_shader.out });
    exe.root_module.addAnonymousImport("test.bgr", .{ .root_source_file = b.path("assets/test.bgr") });

    exe.link_emit_relocs = true;
    exe.setLinkerScript(zitrus_dep.path(zitrus.target.arm11.horizon.linker_script));

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
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
}
