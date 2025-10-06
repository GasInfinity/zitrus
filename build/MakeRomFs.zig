//! A wrapper to simplify making a RomFS with the build system.
//!
//! WARNING: The RomFS WON'T be properly cached due to an upstream issue
//! in the build system. See https://github.com/ziglang/zig/issues/20935
//! You will have to delete your cache directory if you want your RomFS
//! to update, sorry!

pub const Options = struct {
    name: []const u8 = "romfs",

    /// The root directory of the RomFS
    root: std.Build.LazyPath,
};

pub const Config = struct {
    tools_artifact: *Build.Step.Compile,
};

name: []const u8,

/// The underlying `Build.Step.Run` which makes the RomFS.
run: *Build.Step.Run,

/// The generated RomFS file by zitrus. You are encouraged to use this
/// directly.
out: Build.LazyPath,

pub fn init(zitrus_dep: *Build.Dependency, options: Options) MakeRomFs {
    return initInner(zitrus_dep.builder, .{
        .tools_artifact = zitrus_dep.artifact("zitrus"),
    }, options);
}

/// This is intended to be used by **zitrus** itself,
/// prefer `init` instead.
pub fn initInner(b: *Build, config: Config, options: Options) MakeRomFs {
    const name = options.name;

    const make = b.addRunArtifact(config.tools_artifact);
    make.setName(b.fmt("make romfs ({s})", .{name}));
    make.addArgs(&.{ "romfs", "make" });

    make.addDirectoryArg(options.root);
    make.addArg("--output");

    const out = make.addOutputFileArg(options.name);

    return .{
        .name = name,
        .run = make,
        .out = out,
    };
}

const MakeRomFs = @This();

const std = @import("std");
const Build = std.Build;
