pub fn build(b: *std.Build) void {
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

var convert_3dsx_artifact: ?*std.Build.Step.Compile = null;

fn getConvert3dsx(b: *std.Build) *std.Build.Step.Compile {
    if (convert_3dsx_artifact) |c| {
        return c;
    }

    const zitrus = b.dependencyFromBuildZig(@This(), .{});
    const clap = zitrus.builder.lazyDependency("clap", .{}) orelse unreachable;

    const artifact = b.addExecutable(.{
        .name = "convert-3dsx",
        .root_module = b.createModule(.{ .root_source_file = zitrus.path("tools/convert-3dsx.zig"), .target = b.resolveTargetQuery(.{}) }),
    });

    artifact.root_module.addImport("clap", clap.module("clap"));
    artifact.root_module.addImport("zitrus-tooling", zitrus.module("zitrus-tooling"));

    convert_3dsx_artifact = artifact;
    return artifact;
}

// TODO: Add RomFS and SMDH options
pub const Convert3dsxOptions = struct {
    name: []const u8,
    exe: *std.Build.Step.Compile,
};

pub fn addConvert3dsx(b: *std.Build, options: Convert3dsxOptions) std.Build.LazyPath {
    const run_convert = b.addRunArtifact(getConvert3dsx(b));

    run_convert.addArtifactArg(options.exe);
    return run_convert.addOutputFileArg(options.name);
}

const std = @import("std");
const builtin = @import("builtin");
