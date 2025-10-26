pub const version = "0.0.0-pre1";

pub const Make3dsx = @import("build/Make3dsx.zig");
pub const MakeSmdh = @import("build/MakeSmdh.zig");
pub const MakeRomFs = @import("build/MakeRomFs.zig");
pub const AssembleZpsm = @import("build/AssembleZpsm.zig");

pub const target = struct {
    pub const arm11 = struct {
        pub const horizon = struct {
            /// Default linkerscript for ARM11 code executing in HOS userspace.
            pub const linker_script = "build/ld/arm-3ds.ld";

            /// Default test runner running in HOS as an application.
            pub const application_test_runner = "src/horizon/testing/application_test_runner.zig";

            /// Deprecated: Will eventually be replaced by 'arm-3ds' (zig 0.16.0)
            pub const query: std.Target.Query = .{
                .cpu_arch = .arm,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.mpcore },
                .abi = .eabihf,
                .os_tag = .other,
                // .cpu_features_add = std.Target.arm.featureSet(&.{.read_tp_tpidrurw}),
            };
        };

        pub const freestanding = struct {
            pub const query: std.Target.Query = .{
                .cpu_arch = .arm,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.mpcore },
                .abi = .eabihf,
                .os_tag = .freestanding,
            };
        };
    };

    pub const arm9 = struct {
        pub const freestanding = struct {
            pub const query: std.Target.Query = .{
                .cpu_arch = .arm,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm946e_s },
                .abi = .eabi,
                .os_tag = .freestanding,
            };
        };
    };
};

pub fn build(b: *Build) void {
    const release = b.option(bool, "release", "Perform a release build") orelse false;

    const optimize = b.standardOptimizeOption(.{});
    const tools_target = b.standardTargetOptions(.{});

    const zalloc_dep = b.dependency("zalloc", .{});
    const zalloc = zalloc_dep.module("zalloc");

    const zsflt_dep = b.dependency("zsflt", .{});
    const zsflt = zsflt_dep.module("zsflt");

    const zdap_dep = b.dependency("zdap", .{});
    const zdap = zdap_dep.module("zdap");

    const zigimg_dep = b.dependency("zigimg", .{});
    const zigimg = zigimg_dep.module("zigimg");

    const config = b.addOptions();

    // TODO: Add commit hash if not a release
    config.addOption([]const u8, "version", version);

    const zitrus = b.addModule("zitrus", .{
        .root_source_file = b.path("src/zitrus.zig"),
        .imports = &.{
            .{ .name = "zalloc", .module = zalloc },
            .{ .name = "zsflt", .module = zsflt },
        },
    });

    zitrus.addImport("zitrus", zitrus);

    if (release) {
        buildReleases(b, config, zdap, zigimg, zitrus);
        return;
    }

    // XXX: Yes, this is really needed for each target / optimize...
    const zitrus_lib = b.addLibrary(.{
        .name = "zitrus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zitrus.zig"),
            .target = b.resolveTargetQuery(target.arm11.horizon.query),
            .imports = &.{
                .{ .name = "zalloc", .module = zalloc },
                .{ .name = "zsflt", .module = zsflt },
            },
        }),
        .linkage = .static,
    });

    zitrus_lib.root_module.addImport("zitrus", zitrus_lib.root_module);
    // b.installArtifact(zitrus_lib);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = zitrus_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs");
    docs_step.dependOn(&install_docs.step);

    const tools, const tools_exe = buildTools(b, config, optimize, tools_target, zdap, zigimg, zitrus);

    const mod_tests = b.addTest(.{
        .name = "zitrus-mod-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zitrus.zig"),
            .target = b.resolveTargetQuery(.{}),
            .imports = &.{
                .{ .name = "zalloc", .module = zalloc },
                .{ .name = "zsflt", .module = zsflt },
            },
        }),
    });
    mod_tests.root_module.addImport("zitrus", mod_tests.root_module);
    const exe_tests = b.addTest(.{ .name = "zitrus-exe-tests", .root_module = tools });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const run_tests_step = b.step("test", "Runs zitrus tests");
    run_tests_step.dependOn(&run_mod_tests.step);
    run_tests_step.dependOn(&run_exe_tests.step);

    b.installArtifact(tools_exe);

    const run_tool = b.addRunArtifact(tools_exe);

    if (b.args) |args| {
        run_tool.addArgs(args);
    }

    const run_step = b.step("run", "Runs zitrus tools");
    run_step.dependOn(&run_tool.step);
    buildTests(b, zitrus, tools_exe);
    buildScripts(b, zdap);
}

const release_targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86, .os_tag = .linux },
    .{ .cpu_arch = .x86, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .freebsd },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .freebsd },
    .{ .cpu_arch = .riscv64, .os_tag = .linux },
};

fn buildReleases(b: *Build, config: *Build.Step.Options, zdap: *Build.Module, zigimg: *Build.Module, zitrus: *Build.Module) void {
    for (release_targets) |release_target| {
        _, const tools = buildTools(b, config, .ReleaseSafe, b.resolveTargetQuery(release_target), zdap, zigimg, zitrus);

        tools.root_module.strip = true;

        const tools_output = b.addInstallArtifact(tools, .{
            .dest_dir = .{
                .override = .{
                    .custom = release_target.zigTriple(b.allocator) catch @panic("OOM"),
                },
            },
        });

        b.getInstallStep().dependOn(&tools_output.step);
    }
}

fn buildTools(b: *Build, config: *Build.Step.Options, optimize: std.builtin.OptimizeMode, mod_target: Build.ResolvedTarget, zdap: *Build.Module, zigimg: *Build.Module, zitrus: *Build.Module) struct { *Build.Module, *Build.Step.Compile } {
    const tools = b.createModule(.{
        .root_source_file = b.path("tools/main.zig"),
        .target = mod_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zitrus", .module = zitrus },
            .{ .name = "zdap", .module = zdap },
            .{ .name = "zigimg", .module = zigimg },
        },
    });

    tools.addOptions("zitrus-config", config);

    return .{ tools, b.addExecutable(.{
        .name = "zitrus",
        .root_module = tools,
    }) };
}

const Script = struct { name: []const u8, path: []const u8 };
const scripts: []const Script = &.{
    .{ .name = "gen-spirv-spec", .path = "scripts/gen-spirv-spec.zig" },
};

fn buildScripts(b: *Build, zdap: *Build.Module) void {
    inline for (scripts) |script| {
        const script_exe = b.addExecutable(.{
            .name = script.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(script.path),
                .target = b.resolveTargetQuery(.{}),
                .optimize = .Debug,
                .imports = &.{
                    .{ .name = "zdap", .module = zdap },
                },
            }),
        });

        const run_script_step = b.step("run-script-" ++ script.name, "Run " ++ script.name);
        const run_script = b.addRunArtifact(script_exe);

        if (b.args) |args| {
            run_script.addArgs(args);
        }

        run_script_step.dependOn(&run_script.step);
    }
}

const StandaloneTest = struct {
    name: []const u8,
    path: []const u8,
};

const standalone_tests: []const StandaloneTest = &.{
    .{ .name = "hos", .path = "test/hos.zig" },
    .{ .name = "mango", .path = "test/mango.zig" },
};

fn buildTests(b: *Build, zitrus: *Build.Module, zitrus_tools: *Build.Step.Compile) void {
    const build_tests_step = b.step("build-tests", "Builds tests for the running on the 3ds");

    inline for (standalone_tests) |standalone_test| {
        const tests_exe = b.addTest(.{
            .name = standalone_test.name,
            .test_runner = .{ .mode = .simple, .path = b.path(target.arm11.horizon.application_test_runner) },
            .root_module = b.createModule(.{
                .root_source_file = b.path(standalone_test.path),
                .target = b.resolveTargetQuery(target.arm11.horizon.query),
                .optimize = .ReleaseSafe,
                .imports = &.{
                    .{ .name = "zitrus", .module = zitrus },
                },
            }),
        });
        tests_exe.pie = true;
        tests_exe.setLinkerScript(b.path(target.arm11.horizon.linker_script));

        const tests_3dsx = Make3dsx.initInner(b, .{
            .tools_artifact = zitrus_tools,
        }, .{
            .name = standalone_test.name,
            .exe = tests_exe,
        });

        const build_test_step = b.step("build-test-" ++ standalone_test.name, "Builds the '" ++ standalone_test.name ++ "' test for running on the 3ds");

        const install_lib_test = b.addInstallArtifact(tests_exe, .{ .dest_sub_path = "tests/" ++ standalone_test.name ++ ".elf" });
        const install_lib_3dsx_test = b.addInstallBinFile(tests_3dsx.out, "tests/" ++ standalone_test.name ++ ".3dsx");

        build_test_step.dependOn(&install_lib_test.step);
        build_test_step.dependOn(&install_lib_3dsx_test.step);
        build_tests_step.dependOn(build_test_step);
    }
}

const builtin = @import("builtin");
const std = @import("std");

const Build = std.Build;
