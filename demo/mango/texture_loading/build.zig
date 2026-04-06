const std = @import("std");
const zitrus = @import("zitrus");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const common_dep = b.dependency("common", .{});
    const zitrus_dep = b.dependency("zitrus", .{});
    const zitrus_mod = zitrus_dep.module("zitrus");

    const zigimg_dep = b.dependency("zigimg", .{});

    const exe = b.addExecutable(.{
        .name = "texture_loading.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .arm,
                .os_tag = .@"3ds",
            }),
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zitrus", .module = zitrus_mod },
                .{ .name = "common", .module = common_dep.module("common") },
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            },
        }),
        .zig_lib_dir = zitrus_dep.namedLazyPath("juice/zig_lib"),
    });

    const shader = zitrus.AssemblePsm.init(zitrus_dep, .{
        .name = "position_uv.psh",
        .root_source_file = b.path("assets/position_uv.psm"),
    });

    exe.root_module.addAnonymousImport("position_uv.psh", .{ .root_source_file = shader.out });
    exe.root_module.addAnonymousImport("test.bgr", .{ .root_source_file = b.path("assets/test.bgr") });

    exe.pie = true;
    exe.setLinkerScript(zitrus_dep.namedLazyPath("horizon/ld"));
    b.installArtifact(exe);

    const smdh = zitrus.MakeSmdh.init(zitrus_dep, .{
        .settings = b.path("smdh-settings.zon"),
    });

    const final_3dsx = zitrus.Make3dsx.init(zitrus_dep, .{
        .exe = exe,
        .smdh = smdh.out,
    });

    final_3dsx.install(b, .default);

    const link: zitrus.Link3dsx = .init(zitrus_dep, .{
        .@"3dsx" = final_3dsx.out,
    });

    const link_step = b.step("link", "Link (send and execute) the 3dsx to a 3ds");
    link_step.dependOn(&link.run.step);

    if (b.args) |args| link.run.addArgs(args);
}
