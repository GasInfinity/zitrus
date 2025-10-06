//! A wrapper to simplify making a SMDH (SMDH) with the build system.

pub const Options = struct {
    pub const Format = enum { zpsh };

    name: []const u8,
    root_source_file: std.Build.LazyPath,
    output_format: Format = .zpsh,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
};

name: []const u8,

/// The underlying `Build.Step.Run` which actually assembles ZPSM.
run: *Build.Step.Run,

/// The generated and assembled output file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) AssembleZpsm {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) AssembleZpsm {
    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("assemble zpsm ({s})", .{options.name}));
    make.addArgs(&.{ "pica", "asm" });
    make.addFileArg(options.root_source_file);

    make.addArg("-o");
    const out = make.addOutputFileArg(options.name);

    return .{
        .name = options.name,
        .run = make,
        .out = out,
    };
}

const AssembleZpsm = @This();

const std = @import("std");
const Build = std.Build;
