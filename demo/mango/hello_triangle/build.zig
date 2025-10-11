const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const exe = b.addExecutable(.{
        .name = "hello_triangle.elf",
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

    const position_shader = zitrus.AssembleZpsm.init(zitrus_dep, .{
        .name = "position.zpsh",
        .root_source_file = b.path("assets/position.zpsm"),
    });

    exe.root_module.addAnonymousImport("position.zpsh", .{ .root_source_file = position_shader.out });
    exe.root_module.strip = false;
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
