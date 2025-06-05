pub fn build(b: *std.Build) void {
    const zalloc = b.dependency("zalloc", .{});
    const zalloc_mod = zalloc.module("zalloc");

    const zitrus_tooling = b.addModule("zitrus-tooling", .{ .root_source_file = b.path("src/tooling/zitrus.zig") });

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

    buildTools(b, zitrus_tooling);
}

const tools = .{
    .{
        .name = "convert-3dsx",
        .description = "Processes elf files and converts them to 3dsx",
        .path = "tools/convert-3dsx.zig",
    },
};

fn buildTools(b: *std.Build, tooling: *std.Build.Module) void {
    const clap = b.lazyDependency("clap", .{}) orelse unreachable;

    inline for (&tools) |tool_info| {
        const tool = b.addExecutable(.{
            .name = tool_info.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(tool_info.path),
                .target = b.resolveTargetQuery(.{}),
                .strip = true,
                .optimize = .ReleaseFast,
            }),
        });

        tool.root_module.addImport("clap", clap.module("clap"));
        tool.root_module.addImport("zitrus-tooling", tooling);

        b.installArtifact(tool);

        const run_tool = b.addRunArtifact(tool);
        
        if(b.args) |args| {
            run_tool.addArgs(args);
        }

        const run_step = b.step("run-" ++ tool_info.name, tool_info.description);
        run_step.dependOn(&run_tool.step);
    }
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

    exe.setLinkerScript(zitrus.path("3dsx.ld"));
    return exe;
}

// TODO: Add RomFS and SMDH options
pub const Convert3dsxOptions = struct {
    name: []const u8,
    exe: *std.Build.Step.Compile,
};

pub fn addConvert3dsx(b: *std.Build, options: Convert3dsxOptions) std.Build.LazyPath {
    const zitrus = b.dependencyFromBuildZig(@This(), .{});
    const run_convert = b.addRunArtifact(zitrus.artifact("convert-3dsx"));

    run_convert.addArtifactArg(options.exe);
    return run_convert.addOutputFileArg(options.name);
}

const std = @import("std");
const builtin = @import("builtin");
