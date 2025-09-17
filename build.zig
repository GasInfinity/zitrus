pub const target = struct {
    pub const arm9: std.Target.Query = .{
        .cpu_arch = .arm,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm946e_s },
        .abi = .eabihf,
        .os_tag = .freestanding,
    };

    pub const arm11: std.Target.Query = .{
        .cpu_arch = .arm,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.mpcore },
        .abi = .eabihf,
        .os_tag = .freestanding,
    };

    pub const horizon_arm11: std.Target.Query = .{
        .cpu_arch = .arm,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.mpcore },
        .abi = .eabihf,
        .os_tag = .other,
        // .cpu_features_add = std.Target.arm.featureSet(&.{.read_tp_tpidrurw}),
    };
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const tools_target = b.standardTargetOptions(.{});

    const zalloc = b.dependency("zalloc", .{});
    const zalloc_mod = zalloc.module("zalloc");

    const zsflt = b.dependency("zsflt", .{});
    const zsflt_mod = zsflt.module("zsflt");

    const zitrus = b.addModule("zitrus", .{
        .root_source_file = b.path("src/zitrus.zig"),
    });

    // Yes, zitrus uses zitrus, thanks zig for not being c
    zitrus.addImport("zitrus", zitrus);
    zitrus.addImport("zalloc", zalloc_mod);
    zitrus.addImport("zsflt", zsflt_mod);

    const static_zitrus_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/zitrus.zig"),
        .target = b.resolveTargetQuery(target.horizon_arm11),
    });

    const static_zitrus_lib = b.addLibrary(.{
        .name = "zitrus",
        .root_module = static_zitrus_lib_mod,
        .linkage = .static,
    });

    static_zitrus_lib.root_module.addImport("zitrus", static_zitrus_lib.root_module);
    static_zitrus_lib.root_module.addImport("zalloc", zalloc_mod);
    static_zitrus_lib.root_module.addImport("zsflt", zsflt_mod);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = static_zitrus_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs");
    docs_step.dependOn(&install_docs.step);

    const zitrus_tests_mod = b.createModule(.{ .root_source_file = b.path("src/zitrus.zig"), .target = b.resolveTargetQuery(.{}) });

    zitrus_tests_mod.addImport("zitrus", zitrus_tests_mod);
    zitrus_tests_mod.addImport("zalloc", zalloc_mod);
    zitrus_tests_mod.addImport("zsflt", zsflt_mod);

    const zitrus_tests = b.addTest(.{
        .name = "zitrus-tests",
        .root_module = zitrus_tests_mod,
    });

    const run_tests = b.addRunArtifact(zitrus_tests);
    const run_tests_step = b.step("test", "Runs zitrus tests");
    run_tests_step.dependOn(&run_tests.step);

    buildTools(b, optimize, tools_target, zitrus);
    buildTests(b, zitrus);
}

fn buildTools(b: *std.Build, optimize: std.builtin.OptimizeMode, tools_target: std.Build.ResolvedTarget, zitrus_mod: *std.Build.Module) void {
    const no_bin = b.option(bool, "no-bin", "Don't emit a binary (incremental compilation)") orelse false;

    const tools = b.createModule(.{
        .root_source_file = b.path("tools/main.zig"),
        .target = tools_target,
        .optimize = optimize,
    });

    tools.addImport("zitrus", zitrus_mod);

    const flags = b.dependency("flags", .{});
    tools.addImport("flags", flags.module("flags"));

    const ziggy = b.dependency("ziggy", .{});
    tools.addImport("ziggy", ziggy.module("ziggy"));

    // TODO: wait until it gets updated
    // const zigimg = b.dependency("zigimg", .{});
    // tools.addImport("zigimg", zigimg.module("zigimg"));

    const tool_tests = b.addTest(.{ .name = "zitrus-tools-tests", .root_module = tools });

    const run_tool_tests = b.addRunArtifact(tool_tests);
    const run_tool_tests_step = b.step("test-tools", "Runs zitrus-tools tests");
    run_tool_tests_step.dependOn(&run_tool_tests.step);

    const tools_executable = b.addExecutable(.{ .name = "zitrus-tools", .root_module = tools });

    if (no_bin) {
        b.getInstallStep().dependOn(&tools_executable.step);
    } else b.installArtifact(tools_executable);

    const run_tool = b.addRunArtifact(tools_executable);

    if (b.args) |args| {
        run_tool.addArgs(args);
    }

    const run_step = b.step("run-tools", "Runs zitrus-tools");
    run_step.dependOn(&run_tool.step);
}

const StandaloneTest = struct {
    name: []const u8,
    path: []const u8,
};

const standalone_tests: []const StandaloneTest = &.{
    .{ .name = "hos", .path = "test/hos.zig" },
    .{ .name = "mango", .path = "test/mango.zig" },
};

fn buildTests(b: *std.Build, zitrus_mod: *std.Build.Module) void {
    const build_tests_step = b.step("build-tests", "Builds tests for the running on the 3ds");

    // HACK: Yes, this is truly a big hack
    var self_dep: std.Build.Dependency = .{
        .builder = b,
    };

    inline for (standalone_tests) |standalone_test| {
        const tests_exe = addTestDependency(b, &self_dep, .{
            .name = standalone_test.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(standalone_test.path),
                .target = b.resolveTargetQuery(target.horizon_arm11),
                .optimize = .ReleaseSafe,
                .imports = &.{
                    .{ .name = "zitrus", .module = zitrus_mod },
                },
            }),
        });

        const tests_3dsx = addMake3dsxDependency(b, &self_dep, .{
            .name = standalone_test.name,
            .exe = tests_exe,
        });

        const build_test_step = b.step("build-test-" ++ standalone_test.name, "Builds the '" ++ standalone_test.name ++ "' test for running on the 3ds");

        const install_lib_test = b.addInstallArtifact(tests_exe, .{ .dest_sub_path = "tests/" ++ standalone_test.name ++ ".elf" });
        const install_lib_3dsx_test = b.addInstallBinFile(tests_3dsx, "tests/" ++ standalone_test.name ++ ".3dsx");

        build_test_step.dependOn(&install_lib_test.step);
        build_test_step.dependOn(&install_lib_3dsx_test.step);
        build_tests_step.dependOn(build_test_step);
    }
}

pub const ExecutableOptions = struct {
    name: []const u8,
    root_module: *std.Build.Module,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?std.Build.LazyPath = null,
};

pub fn addExecutable(b: *std.Build, options: ExecutableOptions) *std.Build.Step.Compile {
    const zitrus = zitrusDependency(b);

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = options.root_module,
        .version = options.version,
        .linkage = .static,
        .max_rss = options.max_rss,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
    });

    exe.link_emit_relocs = true;
    exe.root_module.strip = false;
    exe.setLinkerScript(zitrus.path("arm-3ds.ld"));
    return exe;
}

pub const TestOptions = struct {
    name: []const u8 = "test",
    root_module: *std.Build.Module,
    max_rss: usize = 0,
    filters: []const []const u8 = &.{},
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?std.Build.LazyPath = null,

    emit_object: bool = false,
};

pub fn addTest(b: *std.Build, options: Make3dsxOptions) std.Build.LazyPath {
    return addTest(b, zitrusDependency(b), options);
}

fn addTestDependency(b: *std.Build, zitrus: *std.Build.Dependency, options: TestOptions) *std.Build.Step.Compile {
    const exe = b.addTest(.{
        .name = options.name,
        .root_module = options.root_module,
        .max_rss = options.max_rss,
        .filters = options.filters,
        .test_runner = .{ .mode = .simple, .path = zitrus.path("src/horizon/testing/application_test_runner.zig") },
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,

        .emit_object = options.emit_object,
    });

    exe.link_emit_relocs = true;
    exe.setLinkerScript(zitrus.path("arm-3ds.ld"));
    return exe;
}

// TODO: Add RomFS option
pub const Make3dsxOptions = struct {
    name: []const u8,
    exe: *std.Build.Step.Compile,
    smdh: ?std.Build.LazyPath = null,
};

pub fn addMake3dsx(b: *std.Build, options: Make3dsxOptions) std.Build.LazyPath {
    return addMake3dsxDependency(b, zitrusDependency(b), options);
}

fn addMake3dsxDependency(b: *std.Build, zitrus: *std.Build.Dependency, options: Make3dsxOptions) std.Build.LazyPath {
    const run_make = b.addRunArtifact(zitrus.artifact("zitrus-tools"));
    run_make.addArgs(&.{ "3dsx", "make" });

    run_make.addArtifactArg(options.exe);

    if (options.smdh) |smdh| {
        run_make.addArg("--smdh");
        run_make.addFileArg(smdh);
    }

    return run_make.addOutputFileArg(options.name);
}

pub const MakeSmdhOptions = struct {
    name: []const u8,
    settings: std.Build.LazyPath,
    icon: ?std.Build.LazyPath = null,
    small_icon: ?std.Build.LazyPath = null,
};

pub fn addMakeSmdh(b: *std.Build, options: MakeSmdhOptions) std.Build.LazyPath {
    const zitrus = zitrusDependency(b);
    const run_make = b.addRunArtifact(zitrus.artifact("zitrus-tools"));
    run_make.addArgs(&.{ "smdh", "make" });

    const smdh = run_make.addOutputFileArg(options.name);
    run_make.addFileArg(options.settings);

    if (options.icon) |icon| {
        run_make.addFileArg(icon);

        if (options.small_icon) |small_icon| {
            run_make.addFileArg(small_icon);
        }
    } else {
        if (options.small_icon != null) {
            run_make.step.dependOn(&b.addFail("cannot set smdh small icon when no large icon was provided").step);
        }

        run_make.addFileArg(zitrus.path("assets/zitrus-logo-smdh.png"));
    }

    return smdh;
}

pub const AssembleZpsmOptions = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
};

pub fn addAssembleZpsm(b: *std.Build, options: AssembleZpsmOptions) std.Build.LazyPath {
    const zitrus = zitrusDependency(b);
    const run_assemble_zpsm = b.addRunArtifact(zitrus.artifact("zitrus-tools"));
    run_assemble_zpsm.addArgs(&.{ "pica", "asm" });
    run_assemble_zpsm.addFileArg(options.root_source_file);
    run_assemble_zpsm.addArg("-o");
    return run_assemble_zpsm.addOutputFileArg(options.name);
}

fn zitrusDependency(b: *std.Build) *std.Build.Dependency {
    return b.dependencyFromBuildZig(@This(), .{});
}

const std = @import("std");
const builtin = @import("builtin");
