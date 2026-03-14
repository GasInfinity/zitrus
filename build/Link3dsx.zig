//! A wrapper to simplify linking (sending) a 3dsx file to a 3ds.

pub const Options = struct {
    @"3dsx": std.Build.LazyPath,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
};

/// The underlying `Build.Step.Run` which links the 3dsx.
run: *Build.Step.Run,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) Link3dsx {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) Link3dsx {
    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("link 3dsx", .{}));
    make.addArgs(&.{ "3dsx", "link" });
    make.addFileArg(options.@"3dsx");

    return .{
        .run = make,
    };
}

const Link3dsx = @This();

const std = @import("std");
const Build = std.Build;
