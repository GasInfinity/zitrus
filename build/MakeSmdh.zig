//! A wrapper to simplify making a SMDH (SMDH) with the build system.

pub const Options = struct {
    name: []const u8 = "smdh.icn",
    settings: std.Build.LazyPath,
    icon: ?std.Build.LazyPath = null,
    small_icon: ?std.Build.LazyPath = null,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
    default_icon: Build.LazyPath,
};

name: []const u8,

/// The underlying `Build.Step.Run` which actually makes the SMDH.
run: *Build.Step.Run,

/// The generated SMDH (ICN) file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) MakeSmdh {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
        .default_icon = zitrus_dep.path("assets/zitrus-logo-smdh.png"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) MakeSmdh {
    const name = options.name;

    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make smdh ({s})", .{name}));
    make.addArgs(&.{ "smdh", "make" });

    make.addFileArg(options.settings);

    if (options.icon) |icon| {
        make.addFileArg(icon);

        if (options.small_icon) |small_icon| {
            make.addFileArg(small_icon);
        }
    } else {
        if (options.small_icon != null) {
            make.step.dependOn(&b.addFail("cannot set smdh small icon when no large icon was provided").step);
        }

        make.addFileArg(config.default_icon);
    }

    make.addArg("--output");
    const out = make.addOutputFileArg(options.name);

    return .{
        .name = name,
        .run = make,
        .out = out,
    };
}

const MakeSmdh = @This();

const std = @import("std");
const Build = std.Build;
