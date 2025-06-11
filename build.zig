pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const zalloc = b.dependency("zalloc", .{});
    const zalloc_mod = zalloc.module("zalloc");

    const zitrus_tooling = b.addModule("zitrus-tooling", .{ .root_source_file = b.path("src/tooling/zitrus.zig") });
    zitrus_tooling.addImport("zitrus-tooling", zitrus_tooling);

    const zitrus = b.addModule("zitrus", .{
        .root_source_file = b.path("src/zitrus.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .arm,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.mpcore },
            .abi = .eabihf,
            .os_tag = .other,
        }),
    });

    // Yes, zitrus uses zitrus, thanks zig for not being c
    zitrus.addImport("zitrus", zitrus);
    zitrus.addImport("zitrus-tooling", zitrus_tooling);
    zitrus.addImport("zalloc", zalloc_mod);

    const zitrus_tooling_tests = b.addTest(.{
        .name = "zitrus-tooling-tests",
        .root_source_file = b.path("src/tooling/zitrus.zig"),
        .target = b.resolveTargetQuery(.{})
    });

    // Bro? Why do I need to do this again? Target handling is so bad rn
    zitrus_tooling_tests.root_module.addImport("zitrus-tooling", zitrus_tooling_tests.root_module);

    const run_tooling_tests = b.addRunArtifact(zitrus_tooling_tests);
    const run_tooling_tests_step = b.step("test-tooling", "Runs zitrus-tooling tests");
    run_tooling_tests_step.dependOn(&run_tooling_tests.step);

    buildTools(b, optimize, target, zitrus_tooling);
}

fn buildTools(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.Build.ResolvedTarget, tooling: *std.Build.Module) void {
    const tools = b.createModule(.{
        .root_source_file = b.path("tools/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    tools.addImport("zitrus-tooling", tooling);

    const clap = b.dependency("clap", .{});
    tools.addImport("clap", clap.module("clap"));

    const ziggy = b.dependency("ziggy", .{});
    tools.addImport("ziggy", ziggy.module("ziggy"));

    const zigimg = b.dependency("zigimg", .{});
    tools.addImport("zigimg", zigimg.module("zigimg"));

    const tool_tests = b.addTest(.{ .name = "zitrus-tools-tests", .root_module = tools });

    const run_tool_tests = b.addRunArtifact(tool_tests);
    const run_tool_tests_step = b.step("test-tools", "Runs zitrus-tools tests");
    run_tool_tests_step.dependOn(&run_tool_tests.step);

    const tools_executable = b.addExecutable(.{ .name = "zitrus-tools", .root_module = tools });

    b.installArtifact(tools_executable);

    const run_tool = b.addRunArtifact(tools_executable);

    if (b.args) |args| {
        run_tool.addArgs(args);
    }

    const run_step = b.step("run-tools", "Runs zitrus-tools");
    run_step.dependOn(&run_tool.step);
}

pub const ExecutableOptions = struct {
    name: []const u8,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?std.Build.LazyPath = null,

    root_module: ?*std.Build.Module = null,
};

pub fn addExecutable(b: *std.Build, options: ExecutableOptions) *std.Build.Step.Compile {
    const zitrus = b.dependencyFromBuildZig(@This(), .{});

    const exe = b.addExecutable(.{
        .name = options.name,
        .version = options.version,
        .linkage = .static,
        .max_rss = options.max_rss,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
        .root_module = options.root_module,
    });

    exe.link_emit_relocs = true;
    exe.root_module.strip = false;
    exe.setLinkerScript(zitrus.path("3dsx.ld"));
    return exe;
}

// TODO: Add RomFS option
pub const Make3dsxOptions = struct {
    name: []const u8,
    exe: *std.Build.Step.Compile,
    smdh: ?std.Build.LazyPath = null,
};

pub fn addMake3dsx(b: *std.Build, options: Make3dsxOptions) std.Build.LazyPath {
    const zitrus = b.dependencyFromBuildZig(@This(), .{});
    const run_make = b.addRunArtifact(zitrus.artifact("zitrus-tools"));
    run_make.addArg("make-3dsx");
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
    const zitrus = b.dependencyFromBuildZig(@This(), .{});
    const run_make = b.addRunArtifact(zitrus.artifact("zitrus-tools"));
    run_make.addArg("make-smdh");

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

        run_make.addFileArg(zitrus.path("assets/smdh-icon.png"));
    }

    return smdh;
}

const std = @import("std");
const builtin = @import("builtin");
